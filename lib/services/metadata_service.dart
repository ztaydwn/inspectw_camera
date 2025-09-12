import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models.dart';
import 'isolate_helpers.dart';
import 'photo_metadata.dart';
import 'storage_service.dart';

class MetadataService with ChangeNotifier {
  final _uuid = const Uuid();
  final _storage = StorageService();
  bool _inited = false;

  // project -> list of PhotoEntry
  final Map<String, List<PhotoEntry>> _cache = {};
  // project -> set of suggestions
  final Map<String, Map<String, int>> _suggestions = {};
  // project -> location name -> status
  final Map<String, Map<String, LocationStatus>> _locationStatusCache = {};

  // --- Background Saving State ---
  int _savingCount = 0;
  int get savingCount => _savingCount;

  Future<void> init() async {
    if (_inited) return;
    await _storage.init();
    _inited = true;
  }

  // --- New method to handle background photo saving ---
  Future<PhotoEntry?> saveNewPhoto({
    required XFile xFile,
    required String description,
    required String project,
    required String location,
    double? aspect,
  }) async {
    _savingCount++;
    notifyListeners();

    final params = SavePhotoParams(
      xFile: xFile,
      description: description,
      project: project,
      location: location,
      aspect: aspect,
      token: RootIsolateToken.instance!,
    );

    try {
      final result = await compute(savePhotoIsolate, params);
      if (result == null) {
        debugPrint('[MetadataService] Isolate failed to save photo');
        return null;
      }
      // Back on the main thread, add the photo to our internal cache
      final newEntry = await addPhoto(
        project: project,
        location: location,
        fileName: result.fileName,
        relativePath: result.relativePath,
        description: result.description,
        takenAt: DateTime.now(),
      );
      return newEntry;
    } catch (e) {
      debugPrint('[MetadataService] Error saving photo: $e');
      return null;
    } finally {
      _savingCount--;
      notifyListeners();
    }
  }

  // --- New method to handle imported photos ---
  Future<PhotoEntry> saveImportedPhoto({
    required XFile xfile,
    required String project,
    required String location,
    required String description,
  }) async {
    await init();

    // 1. Verificar que el archivo temporal existe
    final xfilePath = xfile.path;
    if (!await File(xfilePath).exists()) {
      throw Exception('El archivo temporal no existe');
    }

    File? tempCopy;
    try {
      // 2. Crear copia temporal por si falla algo
      tempCopy = await File(xfilePath).copy('${xfilePath}_temp');

      // 3. Preparar el directorio y nombre del archivo
      final locationDir = await _storage.ensureLocation(project, location);
      final newFileName = '${_uuid.v4()}.jpg';
      final destinationPath = p.join(locationDir.path, newFileName);

      // 4. Copiar el archivo a su ubicación final
      await xfile.saveTo(destinationPath);

      // 5. Crear la ruta relativa
      final relativePath =
          p.url.join('projects', project, location, newFileName);
      final internalPath = 'internal/$relativePath';

      // 6. Agregar la metadata
      final newEntry = await addPhoto(
        project: project,
        location: location,
        fileName: newFileName,
        relativePath: internalPath,
        description: description,
        takenAt: DateTime.now(),
      );

      // 7. Limpiar archivo temporal
      if (await tempCopy.exists()) {
        //se puede borrar tempCopy != null &&
        await tempCopy.delete();
      }

      return newEntry;
    } catch (e) {
      // En caso de error, limpiar archivos temporales
      if (tempCopy != null && await tempCopy.exists()) {
        await tempCopy.delete();
      }
      debugPrint('[MetadataService] Error importing photo: $e');
      rethrow;
    }
  }

  Future<List<String>> listProjects() async {
    final root = Directory('${_storage.rootPath}/projects');
    if (!await root.exists()) return [];
    return root
        .listSync()
        .whereType<Directory>()
        .map((e) => p.basename(e.path))
        .toList()
      ..sort();
  }

  Future<void> createProject(String project) async {
    await _storage.ensureProject(project);
    await _load(project);
  }

  Future<void> deleteProject(String project) async {
    // 1. Verificar si hay operaciones pendientes
    if (_savingCount > 0) {
      throw Exception(
          'No se puede eliminar el proyecto mientras hay operaciones pendientes');
    }

    try {
      // 2. Limpiar todas las referencias en memoria
      _cache.remove(project);
      _suggestions.remove(project);
      _locationStatusCache.remove(project);

      // 3. Eliminar directorio del proyecto
      final dir = Directory(p.join(_storage.rootPath, 'projects', project));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[MetadataService] Error deleting project: $e');
      // Recargar el proyecto en caso de error
      await _load(project);
      rethrow;
    }
  }

  Future<List<String>> listLocations(String project) async {
    final dir = await _storage.ensureProject(project);
    return dir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.split('/').last != '') // all
        .map((e) => p.basename(e.path))
        .where((name) => name != '')
        .where((name) => name != 'projects') // sanity
        .where((name) => name != '')
        .toList();
  }

  Future<void> createLocation(String project, String location) async {
    await _storage.ensureLocation(project, location);
  }

  Future<void> renameLocation(
      String project, String oldName, String newName) async {
    // Validar que el nuevo nombre no exista
    if (await _storage.locationExists(project, newName)) {
      throw Exception('Ya existe una ubicación con ese nombre');
    }

    // Validar caracteres inválidos en el nombre
    if (newName.contains(RegExp(r'[<>:"/\\|?*]'))) {
      throw Exception('El nombre contiene caracteres inválidos');
    }

    // Proceder con el renombrado
    await _storage.renameLocation(project, oldName, newName);

    // Update photo entries
    await _load(project);
    final photos = _cache[project]!;
    for (var photo in photos) {
      if (photo.location == oldName) {
        photo.location = newName;

        if (photo.relativePath.startsWith('internal/')) {
          // Path is like: internal/projects/<project>/<location>/<filename>
          // We need to replace the <location> part.
          // Using split/join is more robust than string replacement.
          final pathSegments = photo.relativePath.split('/');
          // Expected structure: [internal, projects, projectName, locationName, fileName]
          // We look for the location name as the second to last segment.
          if (pathSegments.length > 1 &&
              pathSegments[pathSegments.length - 2] == oldName) {
            pathSegments[pathSegments.length - 2] = newName;
            photo.relativePath = pathSegments.join('/');
          } else {
            // If the path structure is not what we expect, we log it.
            // The original replacement logic was buggy and is now removed.
            // Not changing the path is safer than corrupting it.
            debugPrint(
                '[MetadataService] Could not update path for ${photo.relativePath}: unexpected structure during rename.');
          }
        }
        // For non-internal (DCIM) photos, the relativePath does not contain the
        // location name, so we don't need to change it. The photo is linked
        // to the location via the `photo.location` field, which is already updated.
      }
    }

    // Update location statuses
    await _loadLocationStatus(project);
    final statuses = _locationStatusCache[project]!;
    if (statuses.containsKey(oldName)) {
      final status = statuses.remove(oldName)!;
      status.locationName = newName;
      statuses[newName] = status;
    }

    // Persist changes
    await _persist(project);
    await _persistLocationStatus(project);
    notifyListeners();
  }

  Future<void> deleteLocation(String project, String location) async {
    await _load(project);

    // 1. Delete all photos associated with the location
    final photosInLocation = _cache[project]!
        .where((p) => p.location == location)
        .toList(); // Create a copy to avoid concurrent modification issues

    for (final photo in photosInLocation) {
      await deletePhotoById(project, photo.id);
    }

    // 2. Delete the checklist file if it exists
    final checklistFile = _storage.checklistFile(project, location);
    if (await checklistFile.exists()) {
      await checklistFile.delete();
    }

    // 3. Delete the location status
    await _loadLocationStatus(project);
    _locationStatusCache[project]?.remove(location);
    await _persistLocationStatus(project);

    // 4. Delete the location directory from app storage
    await _storage.deleteLocationDir(project, location);

    // 5. Persist metadata changes and notify listeners
    await _persist(project);
    notifyListeners();
  }

  Future<void> _load(String project) async {
    if (_cache.containsKey(project)) return;

    final f = _storage.metadataFile(project);
    if (await f.exists()) {
      final content = await f.readAsString();
      if (content.isNotEmpty) {
        final data = await compute(jsonDecode, content) as List;
        _cache[project] = data.map((e) => PhotoEntry.fromJson(e)).toList();
      } else {
        _cache[project] = [];
      }
    } else {
      _cache[project] = [];
    }

    final s = _storage.descriptionsFile(project);
    if (await s.exists()) {
      final content = await s.readAsString();
      if (content.isNotEmpty) {
        final data = await compute(jsonDecode, content) as Map<String, dynamic>;
        _suggestions[project] = data.map((k, v) => MapEntry(k, v as int));
      } else {
        _suggestions[project] = {};
      }
    } else {
      _suggestions[project] = {};
    }
  }

  Future<List<PhotoEntry>> listPhotos(String project,
      {String? location}) async {
    await _load(project);
    final all = _cache[project]!;
    if (location == null) return all;
    return all.where((e) => e.location == location).toList();
  }

  Future<PhotoEntry?> getPhotoById(String project, String photoId) async {
    await _load(project);
    final all = _cache[project]!;
    try {
      return all.firstWhere((p) => p.id == photoId);
    } catch (e) {
      return null;
    }
  }

  Future<List<PhotoEntry>> listPhotosWithDescriptionPrefix(
      String project, String location, String prefix) async {
    await _load(project);
    final all = _cache[project]!;
    final photosInLocation = all.where((e) => e.location == location);

    final normalizedPrefix = prefix.toLowerCase();

    return photosInLocation.where((photo) {
      return photo.description.toLowerCase().startsWith(normalizedPrefix);
    }).toList();
  }

  Future<PhotoEntry> addPhoto({
    required String project,
    required String location,
    required String fileName,
    required String relativePath,
    required String description,
    required DateTime takenAt,
  }) async {
    await _load(project);
    final entry = PhotoEntry(
      id: _uuid.v4(),
      project: project,
      location: location,
      fileName: fileName,
      relativePath: relativePath,
      description: description,
      takenAt: takenAt,
    );
    _cache[project]!.add(entry);
    _suggestions[project]![description] =
        (_suggestions[project]![description] ?? 0) + 1;
    await _persist(project);
    return entry;
  }

  Future<void> updateDescription(
      String project, String photoId, String desc) async {
    await _load(project);
    final list = _cache[project]!;
    final idx = list.indexWhere((e) => e.id == photoId);
    if (idx >= 0) {
      list[idx].description = desc;
      _suggestions[project]![desc] = (_suggestions[project]![desc] ?? 0) + 1;
      await _persist(project);
    }
  }

  Future<void> deletePhotoById(String project, String photoId) async {
    await _load(project);
    final list = _cache[project]!;
    final idx = list.indexWhere((e) => e.id == photoId);
    if (idx < 0) return;

    final entry = list[idx];

    // 1. Actualizar contadores de sugerencias
    if (_suggestions[project]?.containsKey(entry.description) ?? false) {
      final count = _suggestions[project]![entry.description]!;
      if (count <= 1) {
        _suggestions[project]!.remove(entry.description);
      } else {
        _suggestions[project]![entry.description] = count - 1;
      }
    }

    // 2. Limpiar referencias en checklists
    final locations = await listLocations(project);
    for (final location in locations) {
      final checklist = await getChecklist(project, location);
      if (checklist != null) {
        bool changed = false;
        for (final item in checklist.items) {
          if (item.photoId == photoId) {
            item.photoId = null;
            changed = true;
          }
        }
        if (changed) {
          await saveChecklist(project, checklist);
        }
      }
    }

    // 3. Eliminar archivo físico
    final file = await _storage.resolvePhotoFile(entry);
    try {
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[MetadataService] Error deleting photo file: $e');
    }

    // 4. Eliminar metadata y persistir cambios
    list.removeAt(idx);
    await _persist(project);
    notifyListeners();
  }

  Future<void> _persist(String project) async {
    final f = _storage.metadataFile(project);
    await compute(persistMetadataIsolate, {
      'file': f,
      'content': _cache[project]!,
    });

    final s = _storage.descriptionsFile(project);
    await compute(persistMetadataIsolate, {
      'file': s,
      'content': _suggestions[project],
    });
  }

  Future<List<String>> suggestions(String project, String query) async {
    await _load(project);
    final map = _suggestions[project]!;
    final q = query.toLowerCase();
    final filtered = map.keys.where((k) => k.toLowerCase().contains(q)).toList()
      ..sort((a, b) => (map[b]!).compareTo(map[a]!));
    return filtered.take(20).toList();
  }

  Future<List<PhotoMetadata>> getAllPhotosForProject(String project) async {
    final dir = await _storage.ensureProject(project);
    final files = await dir.list(recursive: true).toList();
    final imageFiles = files.whereType<File>().where((f) {
      final name = f.path.toLowerCase();
      return name.endsWith('.jpg') || name.endsWith('.jpeg');
    });

    return Future.wait(
        imageFiles.map((f) => PhotoMetadata.fromImageFile(f.path)));
  }

  /// Generates a human-readable text report with project data.
  Future<String> generateProjectDataReport(String project) async {
    final projectData = await getProjectData(project);
    final report = StringBuffer();
    report.writeln('Project: $project');
    report.writeln(
        'Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    report.writeln('---');

    if (projectData != null) {
      report.writeln('DATOS DEL PROYECTO:');
      report.writeln(
          'Nombre del establecimiento: ${projectData.establishmentName}');
      report.writeln('Propietario: ${projectData.owner}');
      report.writeln('Dirección: ${projectData.address}');
      report.writeln(
          'Día de la inspección: ${DateFormat('yyyy-MM-dd').format(projectData.inspectionDate)}');
      report.writeln('Especialidad: ${projectData.specialty}');
      report.writeln(
          'Profesionales Designados: ${projectData.designatedProfessionals}');
      report.writeln(
          'Personal de acompañamiento: ${projectData.accompanyingPersonnel}');
      report.writeln(
          'Comentarios del proceso de inspección: ${projectData.inspectionProcessComments}');
      report.writeln(
          'Función del establecimiento: ${projectData.establishmentFunction}');
      report.writeln('Área ocupada: ${projectData.occupiedArea}');
      report.writeln('Cantidad de pisos: ${projectData.floorCount}');
      report.writeln('Riesgo: ${projectData.risk}');
      report.writeln('Situación formal: ${projectData.formalSituation}');
      report.writeln(
          'Observaciones especiales: ${projectData.specialObservations}');
      report.writeln('--- ');
    }
    return report.toString();
  }

  /// Generates a human-readable text report for all photos in a project.
  Future<String> generatePhotoDescriptionsReport(String project) async {
    final allPhotos = await listPhotos(project);
    final descriptions = StringBuffer();

    if (allPhotos.isEmpty) {
      descriptions.writeln('No photo metadata found for this project.');
      return descriptions.toString();
    }

    final photosWithPaths = <PhotoEntry>[];
    for (final photo in allPhotos) {
      final f = await _storage.resolvePhotoFile(photo);
      if (f != null && await f.exists()) {
        photosWithPaths.add(photo);
      }
    }

    if (photosWithPaths.isEmpty) {
      descriptions.writeln('No photo files found for this project.');
    } else {
      for (final photo in photosWithPaths) {
        descriptions.writeln('[${photo.location}] ${photo.fileName}');
        descriptions.writeln('  Description: ${photo.description}');
        descriptions.writeln(
            '  Taken at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.takenAt)}');
        descriptions.writeln();
      }
    }
    return descriptions.toString();
  }

  /// Generates a human-readable text report for all photos in a project.
  Future<String> generateProjectReport(String project) async {
    final projectData = await getProjectData(project);
    final allPhotos = await listPhotos(project);

    final descriptions = StringBuffer();
    descriptions.writeln('Project: $project');
    descriptions.writeln(
        'Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    descriptions.writeln('---');

    if (projectData != null) {
      descriptions.writeln('DATOS DEL PROYECTO:');
      descriptions.writeln(
          'Nombre del establecimiento: ${projectData.establishmentName}');
      descriptions.writeln('Propietario: ${projectData.owner}');
      descriptions.writeln('Dirección: ${projectData.address}');
      descriptions.writeln(
          'Día de la inspección: ${DateFormat('yyyy-MM-dd').format(projectData.inspectionDate)}');
      descriptions.writeln('Especialidad: ${projectData.specialty}');
      descriptions.writeln(
          'Profesionales Designados: ${projectData.designatedProfessionals}');
      descriptions.writeln(
          'Personal de acompañamiento: ${projectData.accompanyingPersonnel}');
      descriptions.writeln(
          'Comentarios del proceso de inspección: ${projectData.inspectionProcessComments}');
      descriptions.writeln(
          'Función del establecimiento: ${projectData.establishmentFunction}');
      descriptions.writeln('Área ocupada: ${projectData.occupiedArea}');
      descriptions.writeln('Cantidad de pisos: ${projectData.floorCount}');
      descriptions.writeln('Riesgo: ${projectData.risk}');
      descriptions.writeln('Situación formal: ${projectData.formalSituation}');
      descriptions.writeln(
          'Observaciones especiales: ${projectData.specialObservations}');
      descriptions.writeln('--- ');
    }

    if (allPhotos.isEmpty) {
      descriptions.writeln('No photo metadata found for this project.');
      return descriptions.toString();
    }

    final photosWithPaths = <PhotoEntry>[];
    for (final photo in allPhotos) {
      final f = await _storage.resolvePhotoFile(photo);
      if (f != null && await f.exists()) {
        photosWithPaths.add(photo);
      }
    }

    if (photosWithPaths.isEmpty) {
      descriptions.writeln('No photo files found for this project.');
    } else {
      for (final photo in photosWithPaths) {
        descriptions.writeln('[${photo.location}] ${photo.fileName}');
        descriptions.writeln('  Description: ${photo.description}');
        descriptions.writeln(
            '  Taken at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.takenAt)}');
        descriptions.writeln();
      }
    }
    return descriptions.toString();
  }

  // --- Location Status Methods ---

  Future<void> _loadLocationStatus(String project) async {
    if (_locationStatusCache.containsKey(project)) return;

    final f = _storage.locationStatusFile(project);
    if (await f.exists()) {
      final content = await f.readAsString();
      if (content.isNotEmpty) {
        final data = await compute(jsonDecode, content) as List;
        final statuses = data.map((e) => LocationStatus.fromJson(e));
        _locationStatusCache[project] = {
          for (var s in statuses) s.locationName: s
        };
      } else {
        _locationStatusCache[project] = {};
      }
    } else {
      _locationStatusCache[project] = {};
    }
  }

  Future<List<LocationStatus>> getLocationStatuses(String project) async {
    await _load(project); // ensure photos are loaded to get all locations
    await _loadLocationStatus(project);

    final allLocationNames = await listLocations(project);
    final savedStatuses = _locationStatusCache[project] ?? {};

    final allStatuses = allLocationNames.map((name) {
      return savedStatuses[name] ?? LocationStatus(locationName: name);
    }).toList();

    // Update cache with any new locations
    for (var status in allStatuses) {
      if (!savedStatuses.containsKey(status.locationName)) {
        savedStatuses[status.locationName] = status;
      }
    }
    _locationStatusCache[project] = savedStatuses;

    return allStatuses;
  }

  Future<void> updateLocationStatus(
      String project, String locationName, bool isCompleted) async {
    await _loadLocationStatus(project);
    final statuses = _locationStatusCache[project]!;
    if (statuses.containsKey(locationName)) {
      statuses[locationName]!.isCompleted = isCompleted;
    } else {
      statuses[locationName] =
          LocationStatus(locationName: locationName, isCompleted: isCompleted);
    }
    await _persistLocationStatus(project);
    notifyListeners();
  }

  Future<void> _persistLocationStatus(String project) async {
    if (!_locationStatusCache.containsKey(project)) return;

    final f = _storage.locationStatusFile(project);
    final statuses = _locationStatusCache[project]!.values.toList();

    await compute(persistMetadataIsolate, {
      // can reuse the same isolate
      'file': f,
      'content': statuses,
    });
  }

  // --- Project Data Methods ---

  Future<ProjectData?> getProjectData(String project) async {
    final f = _storage.projectDataFile(project);
    if (await f.exists()) {
      final content = await f.readAsString();
      if (content.isNotEmpty) {
        final data = await compute(jsonDecode, content) as Map<String, dynamic>;
        return ProjectData.fromJson(data);
      }
    }
    return ProjectData(inspectionDate: DateTime.now());
  }

  Future<void> saveProjectData(String project, ProjectData data) async {
    final f = _storage.projectDataFile(project);
    await compute(persistMetadataIsolate, {
      'file': f,
      'content': data.toJson(),
    });
    notifyListeners();
  }

  // --- Checklist Methods ---

  Future<Checklist?> getChecklist(String project, String location) async {
    final file = _storage.checklistFile(project, location);
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        final json = await compute(jsonDecode, content) as Map<String, dynamic>;
        return Checklist.fromJson(json);
      }
    }
    return null;
  }

  Future<Checklist> createChecklistFromTemplate(
      String project, String location, ChecklistTemplate template) async {
    final newChecklist = Checklist(
      locationName: location,
      templateName: template.name,
      items: template.items
          .map((itemTemplate) => ChecklistItem(
                id: _uuid.v4(),
                title: itemTemplate.title,
              ))
          .toList(),
    );
    await saveChecklist(project, newChecklist);
    return newChecklist;
  }

  Future<void> saveChecklist(String project, Checklist checklist) async {
    await _storage.ensureChecklistDir(project);
    final file = _storage.checklistFile(project, checklist.locationName);
    await compute(persistMetadataIsolate, {
      'file': file,
      'content': checklist.toJson(),
    });
    notifyListeners();
  }

  Future<void> updateChecklistItem(String project, String location,
      String checklistItemId, String photoId) async {
    final checklist = await getChecklist(project, location);
    if (checklist != null) {
      final itemIndex =
          checklist.items.indexWhere((item) => item.id == checklistItemId);
      if (itemIndex != -1) {
        checklist.items[itemIndex].status = ChecklistItemStatus.completed;
        checklist.items[itemIndex].photoId = photoId;
        await saveChecklist(project, checklist);
      }
    }
  }

  Future<void> cycleChecklistItemStatus(
      String project, String location, String checklistItemId) async {
    final checklist = await getChecklist(project, location);
    if (checklist != null) {
      final itemIndex =
          checklist.items.indexWhere((item) => item.id == checklistItemId);
      if (itemIndex != -1) {
        final item = checklist.items[itemIndex];
        // Cycle: pending -> completed -> omitted -> pending
        final nextStatusIndex =
            (item.status.index + 1) % ChecklistItemStatus.values.length;
        item.status = ChecklistItemStatus.values[nextStatusIndex];
        await saveChecklist(project, checklist);
      }
    }
  }

  // --- Raw Data Export Methods ---

  /// Exports the raw metadata.json file to the Downloads folder.
  Future<String?> exportMetadataFile(String project) async {
    final metaFile = _storage.metadataFile(project);
    if (!await metaFile.exists()) {
      throw Exception('metadata.json not found for project $project');
    }
    final content = await metaFile.readAsString();

    return await _storage.exportReportToDownloads(
      project: project,
      reportContent: content,
      customFileName: '${project}_metadata_backup.json',
    );
  }

  /// Exports the raw descriptions.json file to the Downloads folder.
  Future<String?> exportDescriptionsFile(String project) async {
    final descFile = _storage.descriptionsFile(project);
    if (!await descFile.exists()) {
      throw Exception('descriptions.json not found for project $project');
    }
    final content = await descFile.readAsString();

    return await _storage.exportReportToDownloads(
      project: project,
      reportContent: content,
      customFileName: '${project}_descriptions_backup.json',
    );
  }

  /// Generates a human-readable text report for ALL photo entries, even if the underlying file is missing.
  Future<String> generateTolerantPhotoDescriptionsReport(String project) async {
    final allPhotos = await listPhotos(project);
    final descriptions = StringBuffer();

    if (allPhotos.isEmpty) {
      descriptions.writeln('No photo metadata found for this project.');
      return descriptions.toString();
    }

    descriptions
        .writeln('--- INICIO DEL REPORTE COMPLETO DE DESCRIPCIONES ---');
    descriptions.writeln('Proyecto: $project');
    descriptions.writeln(
        'Exportado el: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    descriptions.writeln(
        'Este reporte incluye TODAS las entradas de metadatos, incluyendo aquellas cuyo archivo de foto no se pudo encontrar.');
    descriptions.writeln('---');

    // This version does NOT check for file existence. It reports on all metadata entries.
    for (final photo in allPhotos) {
      descriptions.writeln('[${photo.location}] ${photo.fileName}');
      descriptions.writeln('  Description: ${photo.description}');
      descriptions.writeln(
          '  Taken at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.takenAt)}');

      // Add a warning if the file is missing
      final f = await _storage.resolvePhotoFile(photo);
      if (f == null || !await f.exists()) {
        descriptions.writeln(
            '  [AVISO: Archivo de foto no encontrado en la ruta: ${photo.relativePath}]');
      }
      descriptions.writeln(); // Add a blank line for readability
    }

    descriptions.writeln('--- FIN DEL REPORTE ---');
    return descriptions.toString();
  }
}
