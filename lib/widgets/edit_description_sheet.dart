import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../constants.dart';

class EditDescriptionSheet extends StatefulWidget {
  final String initial;
  const EditDescriptionSheet({super.key, required this.initial});

  @override
  State<EditDescriptionSheet> createState() => _EditDescriptionSheetState();
}

class _EditDescriptionSheetState extends State<EditDescriptionSheet> {
  String? _selectedGroup;
  String? _selectedDescription;
  List<String> _descriptionsForGroup = [];
  late TextEditingController _detailsController;

  // Voice-to-text variables
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
    _findInitialValues();
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speech.initialize();
    setState(() {});
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
            // Handle multiple separators for backward compatibility
            if (detail.startsWith(':') ||
                detail.startsWith('-') ||
                detail.startsWith('+')) {
              detail = detail.substring(1).trim();
            }
            _detailsController.text = detail;
          });
          return; // Found a match, exit
        }
      }
    }

    // If no preset was matched, assume the whole thing is a custom description.
    setState(() {
      if (kDescriptionGroups.isNotEmpty) {
        _selectedGroup = kDescriptionGroups.keys.first;
        _descriptionsForGroup = kDescriptionGroups[_selectedGroup]!;
        if (_descriptionsForGroup.isNotEmpty) {
          _selectedDescription = _descriptionsForGroup.first;
        }
      }
      _detailsController.text = widget.initial;
    });
  }

  @override
  void dispose() {
    _detailsController.dispose();
    _speech.stop();
    super.dispose();
  }

  void _toggleListening() {
    if (!_speechEnabled) return;
    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    } else {
      _speech.listen(
        onResult: (result) {
          setState(() {
            _detailsController.text = result.recognizedWords;
          });
        },
        localeId: 'es-ES',
      );
      setState(() => _isListening = true);
    }
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
              Text('Editar descripción',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedGroup,
                decoration: const InputDecoration(
                    labelText: 'Grupo', border: OutlineInputBorder()),
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
                decoration: const InputDecoration(
                    labelText: 'Descripción', border: OutlineInputBorder()),
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
              const SizedBox(height: 12),
              TextField(
                controller: _detailsController,
                decoration: InputDecoration(
                  labelText: 'Detalle (opcional)',
                  hintText: _isListening
                      ? 'Escuchando...'
                      : 'Añade información adicional aquí',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    color: _isListening
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                    onPressed: _toggleListening,
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final preset = _selectedDescription ?? '';
                      final detail = _detailsController.text.trim();
                      final finalDescription =
                          detail.isEmpty ? preset : '$preset + $detail';
                      Navigator.pop(context, finalDescription);
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
