// NUEVO WIDGET: Pantalla para ver foto a pantalla completa, con acciones
import 'package:flutter/material.dart';
import '../services/metadata_service.dart';
import 'dart:io';
import '../constants.dart';

class PhotoViewerScreen extends StatelessWidget {
  final String imagePath;
  final String description;
  final String project;
  final String photoId;
  final VoidCallback onDeleted;
  final ValueChanged<String> onDescriptionUpdated;

  const PhotoViewerScreen({
    super.key,
    required this.imagePath,
    required this.description,
    required this.project,
    required this.photoId,
    required this.onDeleted,
    required this.onDescriptionUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () async {
              final newDesc = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (ctx) => _EditDescriptionSheet(
                  initial: description,
                ),
              );
              if (newDesc != null && newDesc != description) {
                onDescriptionUpdated(newDesc);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('¿Eliminar esta foto?'),
                  content: const Text('También se eliminará su descripción.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar')),
                  ],
                ),
              );
              if (confirm == true) {
                await MetadataService().deletePhotoById(project, photoId);
                onDeleted();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Center(
        // OPTIMIZATION: Use a LayoutBuilder to get the constraints of the parent widget.
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate the cacheWidth based on the device's pixel ratio.
            // This ensures the image is decoded at a resolution appropriate for the screen,
            // not at its full original resolution, saving memory and CPU.
            final cacheWidth = (constraints.maxWidth * MediaQuery.of(context).devicePixelRatio).round();
            
            return Image.file(
              File(imagePath),
              fit: BoxFit.contain,
              // Pass the calculated cacheWidth to the Image.file constructor.
              cacheWidth: cacheWidth,
            );
          },
        ),
      ),
    );
  }
}

class _EditDescriptionSheet extends StatefulWidget {
  final String initial;
  const _EditDescriptionSheet({required this.initial});

  @override
  State<_EditDescriptionSheet> createState() => _EditDescriptionSheetState();
}

class _EditDescriptionSheetState extends State<_EditDescriptionSheet> {
  String? _selectedGroup;
  String? _selectedDescription;
  List<String> _descriptionsForGroup = [];
  late TextEditingController _detailsController;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();

    // Find the initial group, preset, and detail
    _findInitialValues();
  }

  void _findInitialValues() {
    for (var groupEntry in kDescriptionGroups.entries) {
      for (var preset in groupEntry.value) {
        if (widget.initial.startsWith(preset)) {
          setState(() {
            _selectedGroup = groupEntry.key;
            _descriptionsForGroup = groupEntry.value;
            _selectedDescription = preset;

            String detail = widget.initial.substring(preset.length).trim();
            if (detail.startsWith(':') || detail.startsWith('-')) {
              detail = detail.substring(1).trim();
            }
            _detailsController.text = detail;
          });
          return; // Found a match, exit
        }
      }
    }

    // If no preset was matched, assume the whole thing is a custom description.
    // We set a default group and description, and put the initial value in details.
    setState(() {
      _selectedGroup = kDescriptionGroups.keys.first;
      _descriptionsForGroup = kDescriptionGroups[_selectedGroup]!;
      _selectedDescription = _descriptionsForGroup.first;
      _detailsController.text = widget.initial;
    });
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Editar descripción', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedGroup,
                decoration: const InputDecoration(labelText: 'Grupo'),
                items: kDescriptionGroups.keys.map((String group) {
                  return DropdownMenuItem<String>(
                    value: group,
                    child: Text(group),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedGroup = newValue!;
                    _descriptionsForGroup = kDescriptionGroups[_selectedGroup]!;
                    if (!_descriptionsForGroup.contains(_selectedDescription)) {
                      _selectedDescription = _descriptionsForGroup.first;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedDescription,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Descripción'),
                items: _descriptionsForGroup.map((String description) {
                  return DropdownMenuItem<String>(
                    value: description,
                    child: RichText(
                      text: TextSpan(
                        text: description,
                        style: DefaultTextStyle.of(context).style,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedDescription = newValue!;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailsController,
                decoration: const InputDecoration(
                  labelText: 'Detalle (opcional)',
                  hintText: 'Añade información adicional aquí',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final preset = _selectedDescription ?? '';
                  final detail = _detailsController.text.trim();
                  final finalDescription =
                      detail.isEmpty ? preset : '$preset: $detail';
                  Navigator.pop(context, finalDescription);
                },
                child: const Text('Guardar'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
