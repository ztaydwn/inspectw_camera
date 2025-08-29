// lib/services/storage_service.dart — v5.2 (DCIM helpers fixed)
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:flutter/foundation.dart'; // Add this import for debugPrint
import '../constants.dart'; // Para kAppFolder

class StorageService {
  static final StorageService _i = StorageService._();
  StorageService._();
  factory StorageService() => _i;

  late Directory _appDir;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _appDir =
        await getApplicationDocumentsDirectory(); // /data/user/0/<pkg>/app_flutter
    await Directory(p.join(_appDir.path, 'projects')).create(recursive: true);
    _ready = true;
  }

  String get rootPath => _appDir.path;

  Future<Directory> ensureProject(String project) async {
    final d = Directory(p.join(_appDir.path, 'projects', project));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> ensureLocation(String project, String location) async {
    final d = Directory(p.join(_appDir.path, 'projects', project, location));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  File metadataFile(String project) =>
      File('${_appDir.path}/projects/$project/metadata.json');

  /// JSON con el conteo/sugerencias de descripciones (mapa: "texto" -> usos)
  File descriptionsFile(String project) =>
      File('${_appDir.path}/projects/$project/descriptions.json');

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
  }

  /// Devuelve el archivo en DCIM a partir de la ruta relativa guardada en metadatos.
  /// This now expects the relativePath to be the .path of a content URI.
  Future<File?> dcimFileFromRelativePath(String relativePath) async {
    if (!Platform.isAndroid) {
      // For non-Android platforms, assume relativePath is a direct file path
      // or handle as appropriate for the platform.
      // For now, returning null as this is an Android-specific issue.
      return null;
    }

    try {
      await MediaStore.ensureInitialized();
    } catch (e) {
      debugPrint('Error initializing MediaStore: $e');
      return null;
    }

    // Reconstruct the content URI from the stored relativePath.
    // The relativePath is actually the .path segment of the content URI.
    // Example: relativePath = '/external_primary/images/media/1000090241'
    // Full URI should be: 'content://media/external_primary/images/media/1000090241'
    final Uri contentUri = Uri.parse('content://media$relativePath');

    try {
      final mediaStore = MediaStore();
      // Corrected method call: use getFile instead of getFileFromUri
      final String? filePath =
          await mediaStore.getFilePathFromUri(uriString: contentUri.toString());
      if (filePath == null) return null;
      final File file = File(filePath);
      return file;
    } catch (e) {
      // Use a logger or debugPrint instead of print
      debugPrint('Error resolving file from URI: $e');
      return null;
    }
  }

  Future<int> projectSizeBytes(String project) async {
    await init();
    final dir = Directory(p.join(_appDir.path, 'projects', project));
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

  /// Exporta los archivos de datos del proyecto (metadata.json, descriptions.json)
  /// a la carpeta pública de "Descargas" del dispositivo.
  /// Devuelve la ruta a la carpeta donde se guardaron los archivos.
  Future<List<String>> exportProjectDataToDownloads(String project) async {
    await init();

    final metaFile = metadataFile(project);
    final descFile = descriptionsFile(project);
    final savedFileNames = <String>[];

    // 1. Inicializar MediaStore
    final mediaStore = MediaStore();
    await MediaStore.ensureInitialized();
    // Asigna el nombre de la carpeta principal para tus exportaciones
    MediaStore.appFolder = kAppFolder;

    // 2. Helper para guardar un archivo usando MediaStore
    Future<void> save(File file) async {
      if (await file.exists()) {
        // MediaStore toma el archivo de la ruta temporal (privada) de tu app
        // y lo guarda correctamente en la carpeta pública de Descargas.
        await mediaStore.saveFile(
          tempFilePath: file.path,
          dirType: DirType.download,
          dirName: DirName.download,
          // Crea una subcarpeta para el proyecto dentro de la carpeta de la app
          relativePath: '$kAppFolder/$project',
        );
        savedFileNames.add(p.basename(file.path));
        debugPrint('Saved ${file.path} via MediaStore');
      }
    }

    // 3. Guardar ambos archivos
    await save(metaFile);
    await save(descFile);

    if (savedFileNames.isEmpty) {
      throw Exception(
          'No se encontraron archivos de datos para exportar en el proyecto "$project".');
    }

    return savedFileNames;
  }
}
