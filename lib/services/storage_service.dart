// lib/services/storage_service.dart — v5.1 (DCIM helpers)
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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

  /// No pide permisos aquí; pídelo en la UI (READ_MEDIA_IMAGES o READ_EXTERNAL_STORAGE).
  Future<Directory?> dcimBase() async {
    if (!Platform.isAndroid) return null;

    try {
      // Vía oficial de path_provider
      final list =
          await getExternalStorageDirectories(type: StorageDirectory.dcim);
      if (list != null && list.isNotEmpty) {
        return list.first;
      }
    } catch (_) {
      // continúa al fallback
      // Fallback común (puede variar según el OEM)
      final guess = Directory('/storage/emulated/0/DCIM');
      if (await guess.exists()) return guess;

      // Otro fallback posible
      final legacy = Directory('/sdcard/DCIM');
      if (await legacy.exists()) return legacy;

      return null;
    }
    return null;
  }

  Future<Directory?> dcimProjectDir(String project) async {
    final base = await dcimBase();
    if (base == null) return null;
    return Directory(p.join(base.path, 'InspectW', project));
  }

  /// (Opcional) /DCIM/InspectW/<project>/<location>
  Future<Directory?> dcimLocationDir(String project, String location) async {
    final prj = await dcimProjectDir(project);
    if (prj == null) return null;
    return Directory(p.join(prj.path, location));
  }

  /// (Opcional) /DCIM/InspectW/<project>/<location>/<fileName>
  Future<File?> dcimFile(
      String project, String location, String fileName) async {
    final loc = await dcimLocationDir(project, location);
    if (loc == null) return null;
    return File(p.join(loc.path, fileName));
  }
}
