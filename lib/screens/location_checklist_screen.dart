import 'package:flutter/material.dart';
import '../models.dart';
import '../services/metadata_service.dart';

class LocationChecklistScreen extends StatefulWidget {
  final String project;

  const LocationChecklistScreen({super.key, required this.project});

  @override
  State<LocationChecklistScreen> createState() => _LocationChecklistScreenState();
}

class _LocationChecklistScreenState extends State<LocationChecklistScreen> {
  final _metadata = MetadataService();
  List<LocationStatus> _locations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() { _loading = true; });
    final locations = await _metadata.getLocationStatuses(widget.project);
    setState(() {
      _locations = locations;
      _loading = false;
    });
  }

  Future<void> _onChanged(LocationStatus status, bool? value) async {
    if (value == null) return;
    await _metadata.updateLocationStatus(widget.project, status.locationName, value);
    setState(() {
      status.isCompleted = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklist de Ubicaciones'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLocations,
              child: ListView.builder(
                itemCount: _locations.length,
                itemBuilder: (context, index) {
                  final location = _locations[index];
                  return CheckboxListTile(
                    title: Text(location.locationName),
                    value: location.isCompleted,
                    onChanged: (bool? value) => _onChanged(location, value),
                  );
                },
              ),
            ),
    );
  }
}
