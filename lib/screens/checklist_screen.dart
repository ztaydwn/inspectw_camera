import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../services/metadata_service.dart';
import '../services/storage_service.dart';
import 'camera_screen.dart';
import 'photo_viewer_screen.dart';

class ChecklistScreen extends StatefulWidget {
  final String project;
  final String location;

  const ChecklistScreen(
      {super.key, required this.project, required this.location});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  late final MetadataService _meta;
  late final StorageService _storage;
  Checklist? _checklist;
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _meta = context.read<MetadataService>();
      _storage = StorageService();
      _isInitialized = true;
      _loadChecklist();
    }
  }

  bool _isInitialized = false;

  Future<void> _loadChecklist() async {
    setState(() => _isLoading = true);
    final checklist = await _meta.getChecklist(widget.project, widget.location);
    setState(() {
      _checklist = checklist;
      _isLoading = false;
    });
  }

  Future<void> _viewPhoto(ChecklistItem item) async {
    if (item.photoId == null) return;

    final photo = await _meta.getPhotoById(widget.project, item.photoId!);
    if (photo == null || !mounted) return;

    final file = await _storage.dcimFileFromRelativePath(photo.relativePath);
    if (!mounted || file == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoViewerScreen(
          imagePath: file.path,
          description: photo.description,
          project: widget.project,
          photoId: photo.id,
          onDeleted: () {
            if (mounted) {
              Navigator.pop(context);
              _loadChecklist();
            }
          },
          onDescriptionUpdated: (newDesc) {
            _meta.updateDescription(widget.project, photo.id, newDesc);
          },
        ),
      ),
    );
  }

  Future<void> _takePhoto(ChecklistItem item) async {
    final newPhoto = await Navigator.push<PhotoEntry>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          project: widget.project,
          location: widget.location,
          initialDescription: item.title,
        ),
      ),
    );

    if (newPhoto != null && mounted) {
      await _meta.updateChecklistItem(
        widget.project,
        widget.location,
        item.id,
        newPhoto.id,
      );
      _loadChecklist();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Checklist: ${widget.location}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _checklist == null
              ? const Center(child: Text('No se pudo cargar el checklist.'))
              : ListView.builder(
                  itemCount: _checklist!.items.length,
                  itemBuilder: (context, index) {
                    final item = _checklist!.items[index];
                    return ListTile(
                      leading: Icon(item.isCompleted
                          ? Icons.check_box
                          : Icons.check_box_outline_blank),
                      title: Text(item.title),
                      trailing: item.isCompleted
                          ? IconButton(
                              icon: const Icon(Icons.photo),
                              onPressed: () => _viewPhoto(item),
                            )
                          : FilledButton.tonal(
                              child: const Text('Tomar Foto'),
                              onPressed: () => _takePhoto(item),
                            ),
                    );
                  },
                ),
    );
  }
}
