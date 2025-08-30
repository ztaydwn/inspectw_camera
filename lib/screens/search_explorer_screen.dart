import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../services/metadata_service.dart';
import '../services/storage_service.dart';
import 'photo_viewer_screen.dart';
import 'dart:io';

class SearchExplorerScreen extends StatefulWidget {
  final String project;

  const SearchExplorerScreen({super.key, required this.project});

  @override
  State<SearchExplorerScreen> createState() => _SearchExplorerScreenState();
}

class _SearchExplorerScreenState extends State<SearchExplorerScreen> {
  late final MetadataService _metadata;
  late final StorageService _storage;
  List<PhotoEntry> _photos = [];
  final Map<String, File> _resolvedFiles = {};
  bool _loading = false;
  final _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _metadata = context.read<MetadataService>();
    _storage = StorageService();
    _storage.init();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _photos = [];
        _resolvedFiles.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
    });
    final allPhotos = await _metadata.listPhotos(widget.project);
    final filteredPhotos = allPhotos
        .where((p) => p.description.toLowerCase().contains(query.toLowerCase()))
        .toList();

    _resolvedFiles.clear();
    for (final pEntry in filteredPhotos) {
      final file = await _storage.dcimFileFromRelativePath(pEntry.relativePath);
      if (file != null && await file.exists()) {
        _resolvedFiles[pEntry.id] = file;
      }
    }

    setState(() {
      _photos = filteredPhotos;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar por descripción...',
            border: InputBorder.none,
          ),
          onChanged: _search,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _photos.length,
              itemBuilder: (context, index) {
                final photo = _photos[index];
                final fileToShow = _resolvedFiles[photo.id];
                if (fileToShow == null) {
                  return const SizedBox.shrink(); // Or a placeholder
                }
                return ListTile(
                  leading: Image.file(
                    fileToShow,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                  title: Text(photo.description),
                  subtitle: Text('Ubicación: ${photo.location}'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PhotoViewerScreen(
                          imagePath: fileToShow.path,
                          description: photo.description,
                          project: widget.project,
                          photoId: photo.id,
                          onDeleted: () {
                            _search(_searchController.text);
                            Navigator.pop(context);
                          },
                          onDescriptionUpdated: (newDesc) async {
                            await _metadata.updateDescription(
                                widget.project, photo.id, newDesc);
                            _search(_searchController.text);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
