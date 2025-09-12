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
  String? _selectedSet;
  String? _selectedGroup;
  Map<String, List<String>> _groupsForSet = {};
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
    // Iterate through all sets and all groups to find the matching preset
    for (var setEntry in kAllDescriptionGroupSets.entries) {
      final setName = setEntry.key;
      final groupSet = setEntry.value;
      for (var groupEntry in groupSet.entries) {
        final groupName = groupEntry.key;
        final descriptions = groupEntry.value;
        for (var preset in descriptions) {
          if (widget.initial.startsWith(preset)) {
            setState(() {
              _selectedSet = setName;
              _groupsForSet = groupSet;
              _selectedGroup = groupName;
              _descriptionsForGroup = descriptions;
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
    }

    // If no preset was matched, assume the whole thing is a custom description.
    // Initialize with the first available set/group/description.
    setState(() {
      if (kAllDescriptionGroupSets.isNotEmpty) {
        _selectedSet = kAllDescriptionGroupSets.keys.first;
        _groupsForSet = kAllDescriptionGroupSets[_selectedSet]!;
        if (_groupsForSet.isNotEmpty) {
          _selectedGroup = _groupsForSet.keys.first;
          _descriptionsForGroup = _groupsForSet[_selectedGroup]!;
          if (_descriptionsForGroup.isNotEmpty) {
            _selectedDescription = _descriptionsForGroup.first;
          }
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
              const SizedBox(height: 24),

              // Checklist Set Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedSet,
                decoration: const InputDecoration(
                    labelText: 'Checklist', border: OutlineInputBorder()),
                items: kAllDescriptionGroupSets.keys.map((String setName) {
                  return DropdownMenuItem<String>(
                    value: setName,
                    child: Text(setName),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue == null) return;
                  setState(() {
                    _selectedSet = newValue;
                    _groupsForSet = kAllDescriptionGroupSets[newValue]!;
                    _selectedGroup = _groupsForSet.keys.first;
                    _descriptionsForGroup = _groupsForSet[_selectedGroup]!;
                    _selectedDescription = _descriptionsForGroup.first;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Group Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedGroup,
                decoration: const InputDecoration(
                    labelText: 'Grupo', border: OutlineInputBorder()),
                items: _groupsForSet.keys.map((String group) {
                  return DropdownMenuItem<String>(
                    value: group,
                    child: Text(group),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue == null) return;
                  setState(() {
                    _selectedGroup = newValue;
                    _descriptionsForGroup = _groupsForSet[newValue]!;
                    _selectedDescription = _descriptionsForGroup.first;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Description Dropdown
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
                    _selectedDescription = newValue;
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
