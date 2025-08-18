// lib/services/storage_service.dart — v5.2 (DCIM helpers fixed)
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:media_store_plus/media_store_plus.dart';

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

    // Reconstruct the content URI from the stored relativePath.
    // The relativePath is actually the .path segment of the content URI.
    // Example: relativePath = '/external_primary/images/media/1000090241'
    // Full URI should be: 'content://media/external_primary/images/media/1000090241'
    final Uri contentUri = Uri.parse('content://media' + relativePath);

    try {
      final mediaStore = MediaStore();
      final File? file = await mediaStore.getFileFromUri(contentUri);
      return file;
    } catch (e) {
      print('Error resolving file from URI: $e');
      return null;
    }
  }
}
