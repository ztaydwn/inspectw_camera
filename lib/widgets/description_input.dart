import 'package:flutter/material.dart';
import 'package:diacritic/diacritic.dart'; // opcional, para quitar tildes

class DescriptionInput extends StatefulWidget {
  final String project;
  final String? initial;
  final List<String> presets;
  const DescriptionInput(
      {super.key,
      required this.project,
      this.initial,
      this.presets = const []});

  @override
  State<DescriptionInput> createState() => _DescriptionInputState();
}

class _DescriptionInputState extends State<DescriptionInput> {
  final c = TextEditingController();
  List<String> _matches = [];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) c.text = widget.initial!;
    _matches = widget.presets;
    c.addListener(_onChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    c.dispose();
    super.dispose();
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Descripción'),
          minLines: 1,
          maxLines: 4,
        ),
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
        Row(children: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar')),
          const Spacer(),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Guardar')),
        ]),
      ]),
    );
  }
}
