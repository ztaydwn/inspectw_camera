// lib/services/storage_service.dart — v5.2 (DCIM helpers fixed)
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:flutter/foundation.dart'; // Add this import for debugPrint
import 'package:permission_handler/permission_handler.dart';
import '../constants.dart'; // Para kAppFolder

class StorageService {
  static final StorageService _i = StorageService._();
  StorageService._();
  factory StorageService() => _i;

  late Directory _appDir;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    debugPrint('StorageService init started.');

    if (Platform.isAndroid) {
      // 1. Request permissions
      final status = await Permission.storage.request();
      if (status.isGranted) {
        debugPrint('Storage permission granted.');
        // 2. Try to get the external storage directory
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          _appDir = Directory(p.join(externalDir.path, 'InspectW_Projects'));
          debugPrint('Using external storage path: ${_appDir.path}');
        } else {
          // Fallback to app documents if external storage is not available
          _appDir = await getApplicationDocumentsDirectory();
          debugPrint('External storage not available, falling back to app documents: ${_appDir.path}');
        }
      } else {
        debugPrint('Storage permission denied.');
        // If permission is denied, fallback to the safer app-specific directory
        _appDir = await getApplicationDocumentsDirectory();
        debugPrint('Falling back to app documents due to denied permissions: ${_appDir.path}');
      }
    } else if (Platform.isIOS) {
      // iOS doesn't require special permissions for the app's documents directory
      final externalDir = await getApplicationDocumentsDirectory();
       _appDir = Directory(p.join(externalDir.path, 'InspectW_Projects'));
       debugPrint('Using app documents directory for iOS: ${_appDir.path}');
    }
    else {
      // For desktop platforms, use application documents directory
      _appDir = await getApplicationDocumentsDirectory();
      debugPrint('Using app documents directory for desktop: ${_appDir.path}');
    }

    try {
      await _appDir.create(recursive: true); // Create the base directory for projects
      debugPrint('Project directory ensured at: ${_appDir.path}');
    } catch (e) {
      debugPrint('Error creating project directory: $e');
      // If creation fails, fallback to a safe directory
      _appDir = await getApplicationDocumentsDirectory();
      await _appDir.create(recursive: true);
      debugPrint('Fell back to app documents directory after creation error: ${_appDir.path}');
    }
    
    _ready = true;
    debugPrint('StorageService init finished.');
  }

  String get rootPath => _appDir.path;

  Future<Directory> ensureProject(String project) async {
    final d = Directory(p.join(_appDir.path, project));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> ensureLocation(String project, String location) async {
    final d = Directory(p.join(_appDir.path, project, location));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> renameLocation(
      String project, String oldLocation, String newLocation) async {
    final oldPath = p.join(_appDir.path, project, oldLocation);
    final newPath = p.join(_appDir.path, project, newLocation);

    final oldDir = Directory(oldPath);
    if (await oldDir.exists()) {
      await oldDir.rename(newPath);
    }
  }

  Future<void> deleteLocationDir(String project, String location) async {
    final path = p.join(_appDir.path, project, location);
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  File metadataFile(String project) =>
      File('${_appDir.path}/$project/metadata.json');

  /// JSON con el conteo/sugerencias de descripciones (mapa: "texto" -> usos)
  File descriptionsFile(String project) =>
      File('${_appDir.path}/$project/descriptions.json');

  File locationStatusFile(String project) =>
      File('${_appDir.path}/$project/location_status.json');

  File projectDataFile(String project) =>
      File('${_appDir.path}/$project/project_data.json');

  Future<Directory> ensureChecklistDir(String project) async {
    final d = Directory(p.join(_appDir.path, project, 'checklists'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  File checklistFile(String project, String location) =>
      File('${_appDir.path}/$project/checklists/$location.json');

  /// Returns the public DCIM directory on Android.
  /// Creates the directory if it does not exist.
  ///
  /// Throws [UnsupportedError] if called on a non-Android platform.
  Future<Directory> dcimBase() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('DCIM directory is only available on Android');
    }

    const dcimPath = '/storage/emulated/0/DCIM';
    final dir = Directory(dcimPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Crea ambos archivos si no existen, con contenido inicial válido
  Future<void> ensureProjectDataFiles(String project) async {
    final meta = metadataFile(project);
    if (!await meta.exists()) {
      await meta.writeAsString('[]', flush: true); // lista vacía de fotos
    }
    final desc = descriptionsFile(project);
    if (!await desc.exists()) {
      await desc.writeAsString('{}',
          flush: true); // objeto vacío de descripciones
    }
    final status = locationStatusFile(project);
    if (!await status.exists()) {
      await status.writeAsString('[]', flush: true); // lista vacía de estados
    }
  }

  /// Devuelve el archivo en DCIM a partir de la ruta relativa guardada en metadatos.
  /// Esta función ahora soporta tanto rutas de archivo directas (antiguas) como
  /// rutas de content URI (nuevas) para retrocompatibilidad.
  Future<File?> dcimFileFromRelativePath(String relativePath) async {
    if (!Platform.isAndroid) {
      return null;
    }

    // --- Lógica de Retrocompatibilidad ---
    // Si la ruta parece una ruta de archivo directa y antigua, úsala directamente.
    if (relativePath.startsWith('/storage/')) {
      final file = File(relativePath);
      if (await file.exists()) {
        return file;
      }
      // Si el archivo no existe en la ruta antigua, no se puede hacer más.
      return null;
    }

    // --- Lógica Nueva (Content URI) ---
    // Si no es una ruta antigua, se asume que es el formato nuevo de content URI.
    try {
      await MediaStore.ensureInitialized();
    } catch (e) {
      debugPrint('Error initializing MediaStore: $e');
      return null;
    }

    // Reconstruye el content URI a partir de la ruta relativa guardada.
    final Uri contentUri = Uri.parse('content://media$relativePath');

    try {
      final mediaStore = MediaStore();
      final String? filePath =
          await mediaStore.getFilePathFromUri(uriString: contentUri.toString());

      if (filePath == null) {
        debugPrint('Could not resolve file path from URI: $contentUri');
        return null;
      }
      return File(filePath);
    } catch (e) {
      debugPrint('Error resolving file from URI: $e');
      return null;
    }
  }

  Future<int> projectSizeBytes(String project) async {
    await init();
    final dir = Directory(p.join(_appDir.path, project));
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final f in dir.list(recursive: true)) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting file: $e');
    }
  }

  /// Exporta un reporte de texto a la carpeta pública de "Descargas" del dispositivo.
  /// Retorna el nombre del archivo guardado.
  Future<String> exportReportToDownloads({
    required String project,
    required String reportContent,
  }) async {
    await init();

    if (reportContent.isEmpty) {
      throw Exception('El contenido del reporte está vacío.');
    }

    final mediaStore = MediaStore();
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = kAppFolder;

    final tempDir = await getTemporaryDirectory();
    final fileName = '${project}_report.txt';
    final tempReportFile = File(p.join(tempDir.path, fileName));
    await tempReportFile.writeAsString(reportContent);

    await mediaStore.saveFile(
      tempFilePath: tempReportFile.path,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: p.join(kAppFolder, project),
    );

    // MediaStore MUEVE el archivo, así que no necesitamos borrar el temporal.
    return fileName;
  }
}