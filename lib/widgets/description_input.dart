import 'package:flutter/material.dart';
import 'package:diacritic/diacritic.dart'; // opcional, para quitar tildes
import 'package:speech_to_text/speech_to_text.dart' as stt;

class DescriptionInput extends StatefulWidget {
  final String project;
  final String? initial;
  final List<String> presets;
  const DescriptionInput({
    super.key,
    required this.project,
    this.initial,
    this.presets = const [],
  });

  @override
  State<DescriptionInput> createState() => _DescriptionInputState();
}

class _DescriptionInputState extends State<DescriptionInput> {
  final c = TextEditingController();
  List<String> _matches = [];

  // Voice-to-text variables
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechEnabled = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) c.text = widget.initial!;
    _matches = widget.presets;
    c.addListener(_onChanged);
    _initSpeech();
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    c.dispose();
    super.dispose();
  }

  /// Initialize speech-to-text
  void _initSpeech() async {
    _speech = stt.SpeechToText();
    _speechEnabled = await _speech.initialize(
      onStatus: (val) {
        setState(() {
          _isListening = val == 'listening';
        });
      },
      onError: (val) {
        setState(() {
          _isListening = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Error de reconocimiento de voz: ${val.errorMsg}')),
          );
        }
      },
    );
    setState(() {});
  }

  /// Start/Stop listening
  void _toggleListening() async {
    if (!_speechEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reconocimiento de voz no disponible')),
      );
      return;
    }

    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _lastWords = val.recognizedWords;
              if (val.finalResult) {
                // Agregar el texto reconocido al campo existente
                if (c.text.isNotEmpty && !c.text.endsWith(' ')) {
                  c.text = '${c.text} $_lastWords';
                } else {
                  c.text = '${c.text}$_lastWords';
                }
                c.selection = TextSelection.fromPosition(
                  TextPosition(offset: c.text.length),
                );
                _onChanged(); // Actualizar las sugerencias
              }
            });
          },
          localeId: 'es-ES', // Español
        );
      } else {
        setState(() => _isListening = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No se pudo iniciar el reconocimiento de voz')),
          );
        }
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  String _norm(String s) =>
      removeDiacritics(s.toLowerCase().trim()); // sin tildes

  void _onChanged() {
    final q = _norm(c.text);
    setState(() {
      if (q.isEmpty) {
        _matches = widget.presets;
      } else {
        _matches = widget.presets
            // prioriza empieza-con, luego contiene
            .where((e) => _norm(e).startsWith(q) || _norm(e).contains(q))
            .toList();
      }
    });
  }

  void _apply(String txt) {
    c.text = txt;
    c.selection =
        TextSelection.fromPosition(TextPosition(offset: c.text.length));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Campo de texto con botón de voz
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: c,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Descripción',
                    hintText: _isListening
                        ? 'Escuchando...'
                        : 'Escribe o habla tu descripción',
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              const SizedBox(width: 8),
              // Botón de voice-to-text
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                ),
                child: IconButton(
                  onPressed: _speechEnabled ? _toggleListening : null,
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening
                        ? Colors.red
                        : (_speechEnabled ? Colors.blue : Colors.grey),
                  ),
                  tooltip: _isListening
                      ? 'Detener grabación'
                      : 'Iniciar reconocimiento de voz',
                ),
              ),
            ],
          ),

          // Indicador visual cuando está escuchando
          if (_isListening) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withValues(alpha: 0.1)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic, color: Colors.red, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Escuchando...',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 6),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Mostrar texto reconocido en tiempo real
          if (_isListening && _lastWords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Reconocido: $_lastWords',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Lista de sugerencias (autocompletar)
          if (_matches.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _matches.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_matches[i]),
                  onTap: () => _apply(_matches[i]),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Botones de acción
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancelar'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context, c.text.trim()),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
