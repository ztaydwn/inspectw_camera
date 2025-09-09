import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // For XFile
import 'package:provider/provider.dart';

import '../services/metadata_service.dart';
import '../widgets/description_input.dart';

class ImportReviewScreen extends StatefulWidget {
  final List<XFile> files;
  final String project;
  final String location;

  const ImportReviewScreen({
    super.key,
    required this.files,
    required this.project,
    required this.location,
  });

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  int _currentIndex = 0;
  bool _isSaving = false;
  String? _currentDescription;

  @override
  void initState() {
    super.initState();
    // Pre-fill description if it's a common format like 'IMG_YYYYMMDD_HHMMSS'
    _currentDescription =
        _extractDescriptionFromName(widget.files[_currentIndex].name);
  }

  String _extractDescriptionFromName(String fileName) {
    // Basic example: remove extension and replace underscores
    try {
      return fileName.split('.').first.replaceAll('_', ' ');
    } catch (e) {
      return '';
    }
  }

  Future<void> _addOrEditDescription() async {
    final metadataService = context.read<MetadataService>();
    // Fetch suggestions for the autocomplete
    final suggestions = await metadataService.suggestions(widget.project, '');
    if (!mounted) return;
    final description = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => DescriptionInput(
        project: widget.project,
        initial: _currentDescription,
        presets: suggestions,
      ),
      isScrollControlled: true,
    );

    if (description != null) {
      setState(() {
        _currentDescription = description;
      });
    }
  }

  Future<void> _saveAndNext() async {
    if (_currentDescription == null || _currentDescription!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, añade una descripción.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final metadataService = context.read<MetadataService>();
    // This function will be created in the next step
    await metadataService.saveImportedPhoto(
      xfile: widget.files[_currentIndex],
      project: widget.project,
      location: widget.location,
      description: _currentDescription!,
    );

    if (!mounted) return;

    if (_currentIndex < widget.files.length - 1) {
      setState(() {
        _currentIndex++;
        _currentDescription =
            _extractDescriptionFromName(widget.files[_currentIndex].name);
        _isSaving = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Todas las fotos han sido importadas!')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFile = widget.files[_currentIndex];
    final progress = '${_currentIndex + 1} de ${widget.files.length}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Importar Foto ($progress)'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: Image.file(File(currentFile.path)),
              ),
            ),
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Guardando foto...'),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    child: ListTile(
                      title: Text(_currentDescription ??
                          'Toca para añadir descripción'),
                      subtitle: const Text('Descripción'),
                      trailing: const Icon(Icons.edit, color: Colors.blue),
                      onTap: _addOrEditDescription,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: Text(_currentIndex < widget.files.length - 1
                        ? 'Guardar y Siguiente'
                        : 'Guardar y Finalizar'),
                    onPressed: _saveAndNext,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar Importación'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
