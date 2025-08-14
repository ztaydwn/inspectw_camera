import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import '../services/metadata_service.dart';

class DescriptionInput extends StatefulWidget {
  final String project;
  final String? initial;
  const DescriptionInput({super.key, required this.project, this.initial});

  @override
  State<DescriptionInput> createState() => _DescriptionInputState();
}

class _DescriptionInputState extends State<DescriptionInput> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.read<MetadataService>();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Descripción de la foto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TypeAheadField<String>(
            suggestionsCallback: (pattern) async => meta.suggestions(widget.project, pattern),
            builder: (context, controller, focusNode) => TextField(
              controller: _c,
              focusNode: focusNode,
              decoration: const InputDecoration(
                hintText: 'Ej.: Extintor sin señalización',
                border: OutlineInputBorder(),
              ),
            ),
            itemBuilder: (context, suggestion) => ListTile(title: Text(suggestion)),
            onSelected: (v) => setState(() => _c.text = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, _c.text.trim()),
            child: const Text('Guardar'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
