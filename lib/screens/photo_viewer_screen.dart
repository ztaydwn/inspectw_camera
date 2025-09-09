// NUEVO WIDGET: Pantalla para ver foto a pantalla completa, con acciones
import 'package:flutter/material.dart';
import '../services/metadata_service.dart';
import 'dart:io';
import '../widgets/edit_description_sheet.dart';

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
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            tooltip: 'Editar Descripción',
            onPressed: () async {
              final newDesc = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (ctx) => EditDescriptionSheet(
                  initial: description,
                ),
              );
              if (newDesc != null && newDesc != description) {
                onDescriptionUpdated(newDesc);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: 'Eliminar Foto',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('¿Eliminar esta foto?'),
                  content: const Text('La foto y su descripción se eliminarán permanentemente.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cacheWidth = (constraints.maxWidth * MediaQuery.of(context).devicePixelRatio).round();
            
            return Image.file(
              File(imagePath),
              fit: BoxFit.contain,
              cacheWidth: cacheWidth,
            );
          },
        ),
      ),
    );
  }
}