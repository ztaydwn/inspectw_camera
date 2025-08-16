// lib/screens/project_screen.dart — v6.1 (fix zip type cast error)
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/storage_service.dart';
import '../services/metadata_service.dart';
import 'gallery_screen.dart';
import 'camera_screen.dart';

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
      // 1) Get all photo metadata for the project
      final allPhotos = await meta.listPhotos(widget.project);
      if (allPhotos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No photo metadata found for this project.')));
        }
        return null;
      }

      // 2) Find the corresponding files in DCIM and prepare for ZIP
      final filesToZip = <ArchiveFile>[];
      final descriptions = StringBuffer();
      descriptions.writeln('Project: ${widget.project}');
      descriptions.writeln(
          'Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
      descriptions.writeln('---');

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

        for (final photo in allPhotos) {
          final fileInDcim = await storage.dcimFile(
              photo.project, photo.location, photo.fileName);
          debugPrint('Looking for file: ${fileInDcim?.path}');
          if (fileInDcim != null && await fileInDcim.exists()) {
            final bytes = await fileInDcim.readAsBytes();
            final archivePath = p.join(photo.location, photo.fileName);
            filesToZip.add(ArchiveFile(archivePath, bytes.length, bytes));

            // Add entry to descriptions file
            descriptions.writeln('[${photo.location}] ${photo.fileName}');
            descriptions.writeln('  Description: ${photo.description}');
            descriptions.writeln(
                '  Taken at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.takenAt)}');
            descriptions.writeln();
          }
        }
      }

      if (filesToZip.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No photos found in DCIM gallery to export.')));
        }
        return null;
      }

      // Add descriptions file to the zip
      final descBytes = utf8.encode(descriptions.toString());
      filesToZip
          .add(ArchiveFile('descriptions.txt', descBytes.length, descBytes));

      // 3) Create the ZIP file
      final zipName =
          '${widget.project}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.zip';
      final zipPath = p.join(Directory.systemTemp.path, zipName);
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);

      for (final file in filesToZip) {
        encoder.addArchiveFile(file);
      }
      encoder.close();

      debugPrint('[ZIP] Created $zipPath with ${filesToZip.length} entries.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('ZIP created with ${filesToZip.length - 1} photo(s).')));
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
      MediaStore.appFolder = 'InspectW';
      await MediaStore().saveFile(
        tempFilePath: zipPath,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath: 'InspectW/${widget.project}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ZIP saved to Downloads/InspectW')));
      }
    } catch (e) {
      debugPrint('[ZIP] Error saving to MediaStore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save ZIP to Downloads: $e')));
      }
    } finally {
      try {
        await File(zipPath).delete();
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