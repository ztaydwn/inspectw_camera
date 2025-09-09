import 'package:intl/intl.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_store_plus/media_store_plus.dart';
import '../services/storage_service.dart';
import '../services/metadata_service.dart';
import '../models.dart';
import 'photo_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  final String project;
  final String location;
  final String? descriptionPrefix;

  const GalleryScreen({
    super.key,
    required this.project,
    required this.location,
    this.descriptionPrefix,
  });

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

      try {
        await MediaStore.ensureInitialized();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se puede acceder a la galería.'),
          ));
          setState(() => _isLoading = false);
        }
        return;
      }
    }

    final List<PhotoEntry> photoEntries;
    if (widget.descriptionPrefix != null) {
      photoEntries = await meta.listPhotosWithDescriptionPrefix(
        widget.project,
        widget.location,
        widget.descriptionPrefix!,
      );
    } else {
      photoEntries =
          await meta.listPhotos(widget.project, location: widget.location);
    }

    _resolvedFiles.clear();
    for (final pEntry in photoEntries) {
      final file = await storage.resolvePhotoFile(pEntry);

      if (file != null && await file.exists()) {
        _resolvedFiles[pEntry.id] = file;
      } else {
        debugPrint('File not found for relative path: ${pEntry.relativePath}');
      }
    }

    photos = photoEntries;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.descriptionPrefix ?? widget.location;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.project} / $title')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : photos.isEmpty
              ? const Center(child: Text('Sin fotos todavía.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: photos.length,
                  itemBuilder: (context, i) {
                    final pEntry = photos[i];
                    final fileToShow = _resolvedFiles[pEntry.id];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 4.0, horizontal: 8.0),
                      child: ListTile(
                        leading: fileToShow != null
                            ? Image.file(fileToShow,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                cacheWidth: 256)
                            : Container(
                                width: 80,
                                height: 80,
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                        title: Text(
                          pEntry.description.isEmpty
                              ? '(sin descripción)'
                              : pEntry.description,
                        ),
                        subtitle: Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(pEntry.takenAt),
                        ),
                        onTap: () async {
                          if (fileToShow == null) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PhotoViewerScreen(
                                imagePath: fileToShow.path,
                                description: pEntry.description,
                                project: widget.project,
                                photoId: pEntry.id,
                                onDeleted: () {
                                  _load();
                                  Navigator.pop(context); // volver a la galería
                                },
                                onDescriptionUpdated: (newDesc) async {
                                  await meta.updateDescription(
                                      widget.project, pEntry.id, newDesc);
                                  _load();
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
