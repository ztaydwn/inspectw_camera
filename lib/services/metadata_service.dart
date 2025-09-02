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

  Future<List<String>> listProjects() async {
    final root = Directory(_storage.rootPath);
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
    final dir = Directory('${_storage.rootPath}/projects/$project');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _cache.remove(project);
    _suggestions.remove(project);
    _locationStatusCache.remove(project);
    // Also delete the project data file
    final dataFile = _storage.projectDataFile(project);
    if (await dataFile.exists()) {
      await dataFile.delete();
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
    await _storage.renameLocation(project, oldName, newName);

    // Update photo entries
    await _load(project);
    final photos = _cache[project]!;
    for (var photo in photos) {
      if (photo.location == oldName) {
        photo.location = newName;
        // This assumes a specific relative path structure, which is brittle.
        // A better approach would be to reconstruct it based on components.
        photo.relativePath = photo.relativePath.replaceFirst('/$oldName/', '/$newName/');
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
    // The photo is in DCIM, not in the app's private storage
    final file = await _storage.dcimFileFromRelativePath(entry.relativePath);
    try {
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    list.removeAt(idx);
    await _persist(project);
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
      report.writeln('Nombre del establecimiento: ${projectData.establishmentName}');
      report.writeln('Propietario: ${projectData.owner}');
      report.writeln('Dirección: ${projectData.address}');
      report.writeln('Día de la inspección: ${DateFormat('yyyy-MM-dd').format(projectData.inspectionDate)}');
      report.writeln('Especialidad: ${projectData.specialty}');
      report.writeln('Profesionales Designados: ${projectData.designatedProfessionals}');
      report.writeln('Personal de acompañamiento: ${projectData.accompanyingPersonnel}');
      report.writeln('Comentarios del proceso de inspección: ${projectData.inspectionProcessComments}');
      report.writeln('Función del establecimiento: ${projectData.establishmentFunction}');
      report.writeln('Área ocupada: ${projectData.occupiedArea}');
      report.writeln('Cantidad de pisos: ${projectData.floorCount}');
      report.writeln('Riesgo: ${projectData.risk}');
      report.writeln('Situación formal: ${projectData.formalSituation}');
      report.writeln('Observaciones especiales: ${projectData.specialObservations}');
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
      final f = await _storage.dcimFileFromRelativePath(photo.relativePath);
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
      descriptions.writeln('Nombre del establecimiento: ${projectData.establishmentName}');
      descriptions.writeln('Propietario: ${projectData.owner}');
      descriptions.writeln('Dirección: ${projectData.address}');
      descriptions.writeln('Día de la inspección: ${DateFormat('yyyy-MM-dd').format(projectData.inspectionDate)}');
      descriptions.writeln('Especialidad: ${projectData.specialty}');
      descriptions.writeln('Profesionales Designados: ${projectData.designatedProfessionals}');
      descriptions.writeln('Personal de acompañamiento: ${projectData.accompanyingPersonnel}');
      descriptions.writeln('Comentarios del proceso de inspección: ${projectData.inspectionProcessComments}');
      descriptions.writeln('Función del establecimiento: ${projectData.establishmentFunction}');
      descriptions.writeln('Área ocupada: ${projectData.occupiedArea}');
      descriptions.writeln('Cantidad de pisos: ${projectData.floorCount}');
      descriptions.writeln('Riesgo: ${projectData.risk}');
      descriptions.writeln('Situación formal: ${projectData.formalSituation}');
      descriptions.writeln('Observaciones especiales: ${projectData.specialObservations}');
      descriptions.writeln('--- ');
    }
    
    if (allPhotos.isEmpty) {
      descriptions.writeln('No photo metadata found for this project.');
      return descriptions.toString();
    }

    final photosWithPaths = <PhotoEntry>[];
    for (final photo in allPhotos) {
      final f = await _storage.dcimFileFromRelativePath(photo.relativePath);
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

    await compute(persistMetadataIsolate, { // can reuse the same isolate
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
      final itemIndex = checklist.items.indexWhere((item) => item.id == checklistItemId);
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
        final nextStatusIndex = (item.status.index + 1) % ChecklistItemStatus.values.length;
        item.status = ChecklistItemStatus.values[nextStatusIndex];
        await saveChecklist(project, checklist);
      }
    }
  }
}