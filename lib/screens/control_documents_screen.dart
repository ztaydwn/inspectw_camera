import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/metadata_service.dart';

class ControlDocumentsScreen extends StatefulWidget {
  final String project;
  const ControlDocumentsScreen({super.key, required this.project});

  @override
  State<ControlDocumentsScreen> createState() => _ControlDocumentsScreenState();
}

class _ControlDocumentsScreenState extends State<ControlDocumentsScreen> {
  late Future<ControlDocumentsSheet> _future;
  ControlDocumentsSheet? _sheet;
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    _future =
        context.read<MetadataService>().getControlDocuments(widget.project);
    _future.then((value) {
      _sheet = value;
      _controllers.clear();
      for (final item in value.items) {
        _controllers.add(TextEditingController(text: item.observation));
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de documentación de seguridad'),
        actions: [
          IconButton(
            tooltip: 'Exportar TXT',
            icon: const Icon(Icons.description_outlined),
            onPressed: () async {
              final path = await context
                  .read<MetadataService>()
                  .exportControlDocumentsFile(widget.project);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(path != null
                    ? 'Exportado: control_documents.txt'
                    : 'No se pudo exportar'),
              ));
            },
          ),
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.save),
            onPressed: _save,
          )
        ],
      ),
      body: FutureBuilder<ControlDocumentsSheet>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final data = _sheet ?? snapshot.data!;
          if (_controllers.length != data.items.length) {
            _controllers
              ..clear()
              ..addAll(data.items
                  .map((e) => TextEditingController(text: e.observation)));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: data.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = data.items[index];
              final controller = _controllers[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item.number}. ${item.title}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SegmentedButton<ControlDocStatus>(
                        segments: const [
                          ButtonSegment(
                              value: ControlDocStatus.observado,
                              label: Text('Observado'),
                              icon: Icon(Icons.report_problem_outlined)),
                          ButtonSegment(
                              value: ControlDocStatus.noAplica,
                              label: Text('No aplica'),
                              icon: Icon(Icons.block_outlined)),
                        ],
                        selected: {item.status},
                        onSelectionChanged: (sel) {
                          setState(() => item.status = sel.first);
                        },
                      ),
                      if (item.status == ControlDocStatus.observado) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: controller,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Detalle de la observación',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => item.observation = v,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const SizedBox(height: 8),
    );
  }

  Future<void> _save() async {
    if (_sheet == null) return;
    await context
        .read<MetadataService>()
        .saveControlDocuments(widget.project, _sheet!);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Guardado')));
  }
}
