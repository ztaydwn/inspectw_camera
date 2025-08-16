// lib/screens/gallery_screen.dart — v5.1 (fallback a DCIM si falta interno)
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/storage_service.dart';
import '../services/metadata_service.dart';
import '../models.dart';
import '../widgets/description_input.dart';

class GalleryScreen extends StatefulWidget {
  final String project;
  final String location;
  const GalleryScreen(
      {super.key, required this.project, required this.location});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late final StorageService storage;
  late final MetadataService meta;
  List<PhotoEntry> photos = [];
  final Map<String, File> _resolvedFiles = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    storage = StorageService();
    meta = context.read<MetadataService>();
    _load();
  }

  Future<void> _load() async {
    // Primero, inicializamos el servicio de almacenamiento para asegurar que las
    // rutas a los archivos se puedan resolver correctamente.
    await storage.init();

    PermissionStatus permStatus;

    // Manejo de permisos diferenciado para Android
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      // En Android 13 (API 33) o superior, se usan permisos granulares.
      if (androidInfo.version.sdkInt >= 33) {
        permStatus = await Permission.photos.request();
      } else {
        permStatus = await Permission.storage.request();
      }
    } else {
      // Para iOS y otras plataformas, Permission.photos es el equivalente.
      permStatus = await Permission.photos.request();
    }
    if (!permStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Permiso denegado. No se pueden mostrar fotos de la galería.'),
          action: SnackBarAction(
            label: 'Abrir ajustes',
            onPressed: openAppSettings,
          ),
        ));
      }
      return; // No podemos continuar sin permisos
    }

    // Carga la lista de fotos una sola vez para mayor eficiencia.
    final photoEntries =
        await meta.listPhotos(widget.project, location: widget.location);

    final dcimDir = await storage.dcimBase();
    if (dcimDir == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No se pudo encontrar el directorio DCIM para leer las fotos.'),
        ));
      }
      return;
    }

    _resolvedFiles.clear();
    for (final pEntry in photoEntries) {
      // La ruta relativa guardada en los metadatos es la fuente de verdad.
      final file = File(path.join(dcimDir.path, pEntry.relativePath));

      if (await file.exists()) {
        _resolvedFiles[pEntry.id] = file;
      } else {
        debugPrint('File not found at expected path: ${file.path}');
      }
    }

    // Asigna la lista de fotos cargada al estado.
    photos = photoEntries;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _editDescription(PhotoEntry p) async {
    final desc = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child:
            DescriptionInput(project: widget.project, initial: p.description),
      ),
    );
    if (desc != null) {
      await meta.updateDescription(widget.project, p.id, desc);
      await _load();
    }
  }

  Future<void> _showDeleteDialog(PhotoEntry p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text(
            '¿Estás seguro de que quieres eliminar esta foto? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePhoto(p);
    }
  }

  Future<void> _deletePhoto(PhotoEntry p) async {
    await meta.deletePhoto(widget.project, p.id);
    // Recargamos la galería para que la UI se actualice
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.project} / ${widget.location}')),
      body: photos.isEmpty
          ? const Center(child: Text('Sin fotos todavía.'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final pEntry = photos[i];
                final fileToShow = _resolvedFiles[pEntry.id];
                final exists = fileToShow?.existsSync() ?? false;

                return GestureDetector(
                  onTap: () => _editDescription(pEntry),
                  onLongPress: () => _showDeleteDialog(pEntry),
                  child: GridTile(
                    footer: GridTileBar(
                      backgroundColor: Colors.black54,
                      title: Text(
                        pEntry.description.isEmpty
                            ? '(sin descripción)'
                            : pEntry.description,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    child: exists
                        ? Image.file(fileToShow!,
                            fit: BoxFit.cover, cacheWidth: 512)
                        : Container(
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.broken_image)),
                  ),
                );
              },
            ),
    );
  }
}
