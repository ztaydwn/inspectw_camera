
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/metadata_service.dart';

class ProjectDataScreen extends StatefulWidget {
  final String project;

  const ProjectDataScreen({super.key, required this.project});

  @override
  State<ProjectDataScreen> createState() => _ProjectDataScreenState();
}

class _ProjectDataScreenState extends State<ProjectDataScreen> {
  final _formKey = GlobalKey<FormState>();
  late Future<ProjectData?> _dataFuture;
  ProjectData? _projectData;

  final _establishmentNameController = TextEditingController();
  final _ownerController = TextEditingController();
  final _addressController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _designatedProfessionalsController = TextEditingController();
  final _accompanyingPersonnelController = TextEditingController();
  final _inspectionProcessCommentsController = TextEditingController();
  final _establishmentFunctionController = TextEditingController();
  final _occupiedAreaController = TextEditingController();
  final _floorCountController = TextEditingController();
  final _riskController = TextEditingController();
  final _formalSituationController = TextEditingController();
  final _specialObservationsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _dataFuture =
        context.read<MetadataService>().getProjectData(widget.project);
    _dataFuture.then((data) {
      if (data != null) {
        _projectData = data;
        _establishmentNameController.text = data.establishmentName;
        _ownerController.text = data.owner;
        _addressController.text = data.address;
        _specialtyController.text = data.specialty;
        _designatedProfessionalsController.text = data.designatedProfessionals;
        _accompanyingPersonnelController.text = data.accompanyingPersonnel;
        _inspectionProcessCommentsController.text = data.inspectionProcessComments;
        _establishmentFunctionController.text = data.establishmentFunction;
        _occupiedAreaController.text = data.occupiedArea;
        _floorCountController.text = data.floorCount;
        _riskController.text = data.risk;
        _formalSituationController.text = data.formalSituation;
        _specialObservationsController.text = data.specialObservations;
        setState(() {});
      } else {
        _projectData = ProjectData(inspectionDate: DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _establishmentNameController.dispose();
    _ownerController.dispose();
    _addressController.dispose();
    _specialtyController.dispose();
    _designatedProfessionalsController.dispose();
    _accompanyingPersonnelController.dispose();
    _inspectionProcessCommentsController.dispose();
    _establishmentFunctionController.dispose();
    _occupiedAreaController.dispose();
    _floorCountController.dispose();
    _riskController.dispose();
    _formalSituationController.dispose();
    _specialObservationsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Datos del Proyecto: ${widget.project}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: FutureBuilder<ProjectData?>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTextField(_establishmentNameController, 'Nombre del establecimiento'),
                _buildTextField(_ownerController, 'Propietario'),
                _buildTextField(_addressController, 'Dirección'),
                _buildDateField(),
                _buildTextField(_specialtyController, 'Especialidad'),
                _buildTextField(_designatedProfessionalsController, 'Profesionales Designados', maxLines: 3),
                _buildTextField(_accompanyingPersonnelController, 'Personal de acompañamiento', maxLines: 3),
                _buildTextField(_inspectionProcessCommentsController, 'Comentarios del proceso de inspección', maxLines: 5),
                _buildTextField(_establishmentFunctionController, 'Función del establecimiento'),
                _buildTextField(_occupiedAreaController, 'Área ocupada'),
                _buildTextField(_floorCountController, 'Cantidad de pisos'),
                _buildTextField(_riskController, 'Riesgo'),
                _buildTextField(_formalSituationController, 'Situación formal'),
                _buildTextField(_specialObservationsController, 'Observaciones especiales', maxLines: 5),
                const SizedBox(height: 24),
                Text('Marcar según corresponda:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                _buildTriStateQuestion(
                  '1. No se encuentra en proceso de construcción según lo establecido en el artículo único de la Norma G.040 Definiciones del Reglamento Nacional de Edificaciones',
                  _projectData?.q1 ?? TriState.noCorresponde,
                  (value) => setState(() => _projectData?.q1 = value),
                ),
                _buildTriStateQuestion(
                  '2. Cuenta con servicios de agua, electricidad, y los que resulten esenciales para el desarrollo de sus actividades, debidamente instalados e implementados.',
                  _projectData?.q2 ?? TriState.noCorresponde,
                  (value) => setState(() => _projectData?.q2 = value),
                ),
                _buildTriStateQuestion(
                  '3. Cuenta con mobiliario básico e instalado para el desarrollo de la actividad.',
                  _projectData?.q3 ?? TriState.noCorresponde,
                  (value) => setState(() => _projectData?.q3 = value),
                ),
                _buildTriStateQuestion(
                  '4. Tiene los equipos o artefactos debidamente instalados o ubicados, respectivamente, en los lugares de uso habitual o permanente.',
                  _projectData?.q4 ?? TriState.noCorresponde,
                  (value) => setState(() => _projectData?.q4 = value),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        maxLines: maxLines,
      ),
    );
  }

  Widget _buildDateField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Día de la inspección',
          border: OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat('dd/MM/yyyy').format(_projectData!.inspectionDate)),
            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: () async {
                final newDate = await showDatePicker(
                  context: context,
                  initialDate: _projectData!.inspectionDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (newDate != null) {
                  setState(() {
                    _projectData!.inspectionDate = newDate;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTriStateQuestion(
      String question, TriState groupValue, ValueChanged<TriState> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question),
          const SizedBox(height: 8),
          SegmentedButton<TriState>(
            segments: const [
              ButtonSegment(value: TriState.si, label: Text('Sí')),
              ButtonSegment(value: TriState.no, label: Text('No')),
              ButtonSegment(value: TriState.noCorresponde, label: Text('No Corresponde')),
            ],
            selected: {groupValue},
            onSelectionChanged: (newSelection) {
              onChanged(newSelection.first);
            },
          ),
        ],
      ),
    );
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      _projectData!.establishmentName = _establishmentNameController.text;
      _projectData!.owner = _ownerController.text;
      _projectData!.address = _addressController.text;
      _projectData!.specialty = _specialtyController.text;
      _projectData!.designatedProfessionals = _designatedProfessionalsController.text;
      _projectData!.accompanyingPersonnel = _accompanyingPersonnelController.text;
      _projectData!.inspectionProcessComments = _inspectionProcessCommentsController.text;
      _projectData!.establishmentFunction = _establishmentFunctionController.text;
      _projectData!.occupiedArea = _occupiedAreaController.text;
      _projectData!.floorCount = _floorCountController.text;
      _projectData!.risk = _riskController.text;
      _projectData!.formalSituation = _formalSituationController.text;
      _projectData!.specialObservations = _specialObservationsController.text;

      await context
          .read<MetadataService>()
          .saveProjectData(widget.project, _projectData!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos guardados')),
        );
        Navigator.pop(context);
      }
    }
  }
}
