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
        child: Image.file(
          File(imagePath),
          fit: BoxFit.contain,
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

  @override
  void initState() {
    super.initState();

    // Find the initial group and description
    for (var group in kDescriptionGroups.entries) {
      if (group.value.contains(widget.initial)) {
        _selectedGroup = group.key;
        _selectedDescription = widget.initial;
        _descriptionsForGroup = group.value;
        break;
      }
    }

    // If not found (e.g., custom description), set defaults
    if (_selectedGroup == null) {
      _selectedGroup = kDescriptionGroups.keys.first;
      _descriptionsForGroup = kDescriptionGroups[_selectedGroup]!;
      _selectedDescription = _descriptionsForGroup.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
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
                  // Reset description if it's not in the new group
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
                  child: Text(description, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedDescription = newValue!;
                });
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, _selectedDescription);
              },
              child: const Text('Guardar'),
            )
          ],
        ),
      ),
    );
  }
}
