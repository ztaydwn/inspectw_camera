// lib/screens/project_screen.dart — v7 (performance refactor)
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/isolate_helpers.dart';
import '../services/storage_service.dart';
import '../services/metadata_service.dart';
import '../models.dart';
import 'gallery_screen.dart';
import 'camera_screen.dart';
import '../constants.dart';

class ProjectScreen extends StatefulWidget {
  final String project;
  const ProjectScreen({super.key, required this.project});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late final StorageService storage;
  late final MetadataService meta;
  bool _isExporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    storage = StorageService();
    meta = context.read<MetadataService>();
  }

  Future<void> _addLocation() async {
    final c = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva ubicación'),
        content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Crear')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await meta.createLocation(widget.project, name);
      if (mounted) setState(() {});
    }
  }

  Future<String?> _buildZipForProject() async {
    setState(() => _isExporting = true);
    try {
      final allPhotos = await meta.listPhotos(widget.project);
      if (allPhotos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No photo metadata found for this project.')));
        }
        return null;
      }

      final photosWithPaths = <PhotoEntry>[];
      final resolvedPaths = <String>[];
      for (final photo in allPhotos) {
        final f = await storage.dcimFileFromRelativePath(photo.relativePath);
        if (f != null && await f.exists()) {
          photosWithPaths.add(photo);
          resolvedPaths.add(f.path);
        }
      }

      if (photosWithPaths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No photo files found for this project.')));
        }
        return null;
      }

      final descriptions = StringBuffer();
      descriptions.writeln('Project: ${widget.project}');
      descriptions.writeln(
          'Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
      descriptions.writeln('---');

      for (final photo in photosWithPaths) {
        descriptions.writeln('[${photo.location}] ${photo.fileName}');
        descriptions.writeln('  Description: ${photo.description}');
        descriptions.writeln(
            '  Taken at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.takenAt)}');
        descriptions.writeln();
      }

      if (Platform.isAndroid) {
        PermissionStatus permStatus;
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          permStatus = await Permission.photos.request();
        } else {
          permStatus = await Permission.storage.request();
        }

        if (!permStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Storage permission denied.')));
          }
          return null;
        }
      }

      final params = CreateZipParams(
        photos: photosWithPaths,
        project: widget.project,
        descriptions: descriptions.toString(),
        resolvedPaths: resolvedPaths,
      );

      final zipPath = await compute(createZipIsolate, params);

      if (zipPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to create ZIP file.')));
        }
        return null;
      }

      debugPrint(
          '[ZIP] Created $zipPath with ${photosWithPaths.length} entries.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('ZIP created with ${photosWithPaths.length} photo(s).')));
      }
      return zipPath;
    } catch (e, s) {
      debugPrint('[ZIP] Error building ZIP: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error creating ZIP: $e')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportProject() async {
    final zipPath = await _buildZipForProject();
    if (zipPath == null) return;

    try {
      await MediaStore.ensureInitialized();
      MediaStore.appFolder = kAppFolder;
      await MediaStore().saveFile(
        tempFilePath: zipPath,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath: '$kAppFolder/${widget.project}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ZIP saved to Downloads/$kAppFolder')));
      }
    } catch (e) {
      debugPrint('[ZIP] Error saving to MediaStore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save ZIP to Downloads: $e')));
      }
    } finally {
      try {
        final tmpZip = File(zipPath);
        if (await tmpZip.exists()) {
          await tmpZip.delete();
        } else {
          debugPrint('[ZIP] Temp not found (already moved/cleaned): $zipPath');
        }
      } catch (e) {
        debugPrint('[ZIP] Failed to delete temp file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Proyecto: ${widget.project}'),
        actions: [
          _isExporting
              ? const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3))),
                )
              : IconButton(
                  onPressed: _exportProject, icon: const Icon(Icons.ios_share)),
        ],
      ),
      body: FutureBuilder<List<String>>(
        future: meta.listLocations(widget.project),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final items = snap.data ?? [];
          return Column(
            children: [
              if (items.isEmpty)
                const ListTile(
                    title: Text('Sin ubicaciones. Crea la primera.')),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final loc = items[i];
                    return ListTile(
                      title: Text(loc),
                      leading: const Icon(Icons.place_outlined),
                      trailing: IconButton(
                        icon: const Icon(Icons.camera_alt_outlined),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CameraScreen(
                                  project: widget.project, location: loc),
                            )),
                      ),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GalleryScreen(
                                project: widget.project, location: loc),
                          )),
                    );
                  },
                ),
              )
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLocation,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Nueva ubicación'),
      ),
    );
  }
}
