// lib/screens/project_screen.dart — v6.1 (fix zip type cast error)
import 'dart:io';
import 'package:archive/archive_io.dart';
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
      // 1) Determine source directory and collect files
      Directory? source;
      List<File> files = [];
      // 1. Buscar en internal (project folder)
      final internalRoot =
          Directory(p.join(storage.rootPath, 'projects', widget.project));

      if (await internalRoot.exists()) {
        final entities = await internalRoot.list(recursive: true).toList();
        files = entities.whereType<File>().toList();
        if (files.isNotEmpty) source = internalRoot;
      }

      if (source == null && Platform.isAndroid) {
        final permStatus = await Permission.storage.request();
        if (permStatus.isGranted) {
          // 2. Buscar en DCIM (fotos)
          final dcimProject = await storage.dcimProjectDir(widget.project);
          if (dcimProject != null && await dcimProject.exists()) {
            final entities = await dcimProject.list(recursive: true).toList();
            files = entities
                .whereType<File>()
                .where((f) =>
                    f.path.toLowerCase().endsWith('.jpg') ||
                    f.path.toLowerCase().endsWith('.jpeg') ||
                    f.path.toLowerCase().endsWith('.png'))
                .toList();
            if (files.isNotEmpty) {
              source = dcimProject;
              debugPrint(
                  '[ZIP] Using DCIM: ${dcimProject.path} (files=${files.length})');
            }
          }
        }
      }

      if (source == null || files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No photos found to export.')));
        }
        return null;
      }

      // 2) Create the ZIP file
      final zipName =
          '${widget.project}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.zip';
      final zipPath = p.join(Directory.systemTemp.path, zipName);
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);

      for (final file in files) {
        // FIX: Do not cast to File, addFile expects an ArchiveFile. This is already correct.
        encoder.addFile(file); // Aquí `file` es del tipo `File`, y es correcto
      }
      encoder.close();

      debugPrint(
          '[ZIP] Source=${source.path} files=${files.length} -> $zipPath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('ZIP created with ${files.length} file(s).')));
      }
      return zipPath;
    } catch (e) {
      debugPrint('[ZIP] Error building ZIP: $e');
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
