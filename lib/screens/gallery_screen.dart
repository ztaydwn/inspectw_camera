// lib/screens/gallery_screen.dart — v6 (path fix)
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
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
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    storage = StorageService();
    meta = context.read<MetadataService>();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);

    await storage.init();

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      PermissionStatus permStatus;
      if (androidInfo.version.sdkInt >= 33) {
        permStatus = await Permission.photos.request();
      } else {
        permStatus = await Permission.storage.request();
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
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }

    final photoEntries =
        await meta.listPhotos(widget.project, location: widget.location);

    _resolvedFiles.clear();
    for (final pEntry in photoEntries) {
      final file = await storage.dcimFileFromRelativePath(pEntry.relativePath);

      if (file != null && await file.exists()) {
        _resolvedFiles[pEntry.id] = file;
      } else {
        debugPrint(
            'File not found for relative path: ${pEntry.relativePath}');
      }
    }

    photos = photoEntries;
    if (mounted) {
      setState(() => _isLoading = false);
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
            child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Eliminar')),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePhoto(p);
    }
  }

  Future<void> _deletePhoto(PhotoEntry p) async {
    await meta.deletePhoto(widget.project, p.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.project} / ${widget.location}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : photos.isEmpty
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
                        child: fileToShow != null
                            ? Image.file(fileToShow,
                                fit: BoxFit.cover, cacheWidth: 512)
                            : Container(
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.broken_image_outlined)),
                      ),
                    );
                  },
                ),
    );
  }
}