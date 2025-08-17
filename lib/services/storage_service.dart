// lib/services/storage_service.dart — v5.2 (DCIM helpers fixed)
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
    // La forma más consistente de acceder a la carpeta pública DCIM es usando
    // su ruta estándar. Los métodos de path_provider tienden a devolver
    // directorios específicos de la app (dentro de /Android/data), que no
    // es lo que queremos para una galería pública.
    final publicDcim = Directory('/storage/emulated/0/DCIM');
    if (await publicDcim.exists()) {
      return publicDcim;
    }

    // Un fallback común en dispositivos más antiguos.
    final legacyPublicDcim = Directory('/sdcard/DCIM');
    if (await legacyPublicDcim.exists()) {
      return legacyPublicDcim;
    }

    // Si ninguna de las rutas públicas existe, es posible que el almacenamiento
    // no esté disponible o la estructura sea no estándar. Devolvemos null.
    return null;
  }

  /// Devuelve el archivo en DCIM a partir de la ruta relativa guardada en metadatos.
  Future<File?> dcimFileFromRelativePath(String relativePath) async {
    final base = await dcimBase();
    if (base == null) return null;
    return File(p.join(base.path, relativePath));
  }
}
