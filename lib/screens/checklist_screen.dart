import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../services/metadata_service.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';

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
  Checklist? _checklist;
  bool _isLoading = true;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _meta = context.read<MetadataService>();
      _isInitialized = true;
      _loadChecklist();
    }
  }

  Future<void> _loadChecklist() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    final checklist = await _meta.getChecklist(widget.project, widget.location);
    if (mounted) {
      setState(() {
        _checklist = checklist;
        _isLoading = false;
      });
    }
  }

  Future<void> _takePhoto(ChecklistItem item) async {
    // Navigate to camera with preselected subgroup and stay after capture
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          project: widget.project,
          location: widget.location,
          preselectedSubgroup: item.title,
          stayAfterCapture: true, // Stay on camera screen
        ),
      ),
    );
    // Since we can take multiple photos, we don't link a single photo back
    // to the checklist item here. We also don't mark it as complete automatically.
    // We refresh the checklist to show any status changes made manually.
    _loadChecklist();
  }

  Future<void> _toggleItemCompletion(ChecklistItem item) async {
    await _meta.toggleChecklistItemStatus(
      widget.project,
      widget.location,
      item.id,
    );
    _loadChecklist();
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
              : RefreshIndicator(
                  onRefresh: _loadChecklist,
                  child: ListView.builder(
                    itemCount: _checklist!.items.length,
                    itemBuilder: (context, index) {
                      final item = _checklist!.items[index];
                      return ListTile(
                        onTap: () {
                          // Allow toggling completion regardless of photo
                          _toggleItemCompletion(item);
                        },
                        leading: Icon(item.isCompleted
                            ? Icons.check_box
                            : Icons.check_box_outline_blank),
                        title: Text(item.title),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // FutureBuilder to show photo count and link to gallery
                            FutureBuilder<List<PhotoEntry>>(
                              future: _meta.listPhotosWithDescriptionPrefix(
                                widget.project,
                                widget.location,
                                item.title,
                              ),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final count = snapshot.data!.length;
                                return TextButton.icon(
                                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                                  label: Text('$count'),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => GalleryScreen(
                                          project: widget.project,
                                          location: widget.location,
                                          descriptionPrefix: item.title,
                                        ),
                                      ),
                                    ).then((_) => _loadChecklist()); // Refresh on return
                                  },
                                );
                              },
                            ),
                            const SizedBox(width: 4),
                            FilledButton.tonal(
                              child: const Text('Foto'),
                              onPressed: () => _takePhoto(item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
