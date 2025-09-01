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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          project: widget.project,
          location: widget.location,
          preselectedSubgroup: item.title,
          stayAfterCapture: true,
        ),
      ),
    );
    _loadChecklist();
  }

  Future<void> _cycleItemStatus(ChecklistItem item) async {
    await _meta.cycleChecklistItemStatus(
      widget.project,
      widget.location,
      item.id,
    );
    _loadChecklist();
  }

  void _showLegend() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leyenda de Símbolos'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.check_box_outline_blank, color: Colors.grey),
              title: Text('Pendiente'),
              subtitle: Text('La observación aún no ha sido revisada.'),
            ),
            ListTile(
              leading: Icon(Icons.check_box, color: Colors.green),
              title: Text('Completado'),
              subtitle: Text(
                  'La observación fue revisada y se tomaron las acciones necesarias.'),
            ),
            ListTile(
              leading: Icon(Icons.indeterminate_check_box, color: Colors.red),
              title: Text('Omitido / No Aplica'),
              subtitle: Text(
                  'La observación no aplica para esta ubicación o fue omitida.'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Checklist: ${widget.location}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showLegend,
            tooltip: 'Mostrar Leyenda',
          ),
        ],
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
                      final Widget icon;
                      switch (item.status) {
                        case ChecklistItemStatus.completed:
                          icon =
                              const Icon(Icons.check_box, color: Colors.green);
                          break;
                        case ChecklistItemStatus.omitted:
                          icon = const Icon(Icons.indeterminate_check_box,
                              color: Colors.red);
                          break;
                        case ChecklistItemStatus.pending:
                          icon = const Icon(Icons.check_box_outline_blank);
                          break;
                      }

                      return ListTile(
                        onTap: () => _cycleItemStatus(item),
                        leading: icon,
                        title: Text(item.title),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FutureBuilder<List<PhotoEntry>>(
                              future: _meta.listPhotosWithDescriptionPrefix(
                                widget.project,
                                widget.location,
                                item.title,
                              ),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData ||
                                    snapshot.data!.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final count = snapshot.data!.length;
                                return TextButton.icon(
                                  icon: const Icon(Icons.photo_library_outlined,
                                      size: 16),
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
                                    ).then((_) => _loadChecklist());
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
