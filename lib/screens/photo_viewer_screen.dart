// NUEVO WIDGET: Pantalla para ver foto a pantalla completa, con acciones
import 'package:flutter/material.dart';
import '../services/metadata_service.dart';
import 'dart:io';

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
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Editar descripción', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: null,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: 'Nueva descripción'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, _controller.text.trim());
              },
              child: const Text('Guardar'),
            )
          ],
        ),
      ),
    );
  }
}
