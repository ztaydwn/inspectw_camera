import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/metadata_service.dart';
import '../widgets/description_input.dart';
import '../constants.dart';

enum AspectOpt { sensor, a16x9, a4x3, a1x1 }

class CameraScreen extends StatefulWidget {
  final String project;
  final String location;
  const CameraScreen(
      {super.key, required this.project, required this.location});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  ResolutionPreset preset = ResolutionPreset.max;
  FlashMode _flashMode = FlashMode.off;
  double zoom = 1.0, minZoom = 1.0, maxZoom = 4.0;
  int selectedBackIndex = 0;
  AspectOpt aspect = AspectOpt.sensor;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    await _startController();
  }

  @override
  void dispose() {
    controller?.dispose();
    SystemChrome.setPreferredOrientations(
        DeviceOrientation.values); // restaurar
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    if (controller == null) return;
    final newMode =
        _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await controller!.setFlashMode(newMode);
      setState(() {
        _flashMode = newMode;
      });
    } on CameraException catch (e) {
      debugPrint('Error setting flash mode: $e');
    }
  }

  double? _aspectToDouble(AspectOpt a) {
    switch (a) {
      case AspectOpt.a16x9:
        return 16 / 9;
      case AspectOpt.a4x3:
        return 4 / 3;
      case AspectOpt.a1x1:
        return 1 / 1;
      case AspectOpt.sensor:
        return null;
    }
  }

  Future<void> _startController() async {
    if (cameras.isEmpty) return;
    final cam = CameraController(cameras[selectedBackIndex], preset,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    controller = cam;
    try {
      await cam.initialize();
      await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
      minZoom = await cam.getMinZoomLevel();
      maxZoom = await cam.getMaxZoomLevel();

      zoom = zoom.clamp(minZoom, maxZoom);
      await cam.setZoomLevel(zoom);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error de cámara: ${e.description}')));
      }
    }
    if (mounted) setState(() {});
  }

  void _takePhoto() async {
    final cam = controller;
    // Use context.read here because we are in a button handler and not rebuilding
    final metadataService = context.read<MetadataService>();

    if (cam == null ||
        !cam.value.isInitialized ||
        metadataService.savingCount > 5) {
      if (metadataService.savingCount > 5) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Espere a que se guarden las fotos pendientes.')));
        }
      }
      return;
    }

    try {
      final xFile = await cam.takePicture();
      debugPrint('[Camera] temp: ${xFile.path}');

      final desc = await _askForDescription();
      if (desc == null) return; // User cancelled

      // --- Delegate saving to the service ---
      metadataService.saveNewPhoto(
        xFile: xFile,
        description: desc,
        project: widget.project,
        location: widget.location,
        aspect: _aspectToDouble(aspect),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto capturada. Guardando en segundo plano...'),
          duration: Duration(seconds: 2),
        ));
      }
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al tomar la foto: ${e.description}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error inesperado: $e')));
      }
    }
  }

  Future<String?> _askForDescription() async {
    // (This function remains the same as before)
    // 1. Mostrar lista de grupos principales
    final selectedGroup = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona un grupo:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: kDescriptionGroups.keys.map((group) {
                  return ListTile(
                    title: Text(group),
                    onTap: () => Navigator.pop(ctx, group),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedGroup == null || !mounted) return null;

    // 2. Obtener los subgrupos del grupo seleccionado
    final subgroups = kDescriptionGroups[selectedGroup] ?? [];
    if (subgroups.isEmpty) return null;

    // 3. Mostrar lista de subgrupos
    final selectedSubgroup = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(ctx),
                ),
                Expanded(
                  child: Text(
                    selectedGroup,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: subgroups.length,
                itemBuilder: (context, index) {
                  final subgroup = subgroups[index];
                  return ListTile(
                    title: Text(
                      subgroup,
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () => Navigator.pop(ctx, subgroup),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedSubgroup == null || !mounted) return null;

    // 4. Usar DescriptionInput para agregar información adicional
    final additionalText = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header con el subgrupo seleccionado
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    const Expanded(
                      child: Text(
                        'Agregar información adicional',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'Subgrupo: $selectedSubgroup',
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // DescriptionInput con padding adicional
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: DescriptionInput(
              project: widget.project,
              initial: '', // Empezar vacío para que agreguen texto adicional
              presets: const [
                'oxidado',
                'roto',
                'faltante',
                'corrosión',
                'grieta',
                'fisura',
                'humedad',
                'desgastado',
                'suelto',
                'mal estado',
                'presenta daños',
                'no funciona',
                'en buen estado',
                'requiere mantenimiento',
              ],
            ),
          ),
        ],
      ),
    );

    // 5. Construir la descripción final
    if (additionalText == null) return null;

    if (additionalText.isEmpty) {
      return selectedSubgroup; // Solo el subgrupo
    } else {
      return '$selectedSubgroup + $additionalText'; // Subgrupo + texto adicional
    }
  }

  @override
  Widget build(BuildContext context) {
    final cam = controller;
    // Listen to the saving count from the service
    final savingCount = context.watch<MetadataService>().savingCount;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.project} / ${widget.location}'),
        actions: [
          // --- Saving Indicator ---
          if (savingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text('$savingCount'),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Cambiar cámara',
            onPressed: () async {
              if (cameras.isEmpty) return;
              selectedBackIndex = (selectedBackIndex + 1) % cameras.length;
              await _startController();
              setState(() {});
            },
          ),
          IconButton(
            icon: Icon(_flashMode == FlashMode.torch
                ? Icons.flash_on
                : Icons.flash_off),
            onPressed: _toggleFlash,
          ),
          PopupMenuButton<ResolutionPreset>(
            icon: const Icon(Icons.hd),
            onSelected: (p) async {
              preset = p;
              await _startController();
            },
            itemBuilder: (ctx) => ResolutionPreset.values
                .map((p) => PopupMenuItem(value: p, child: Text(p.name)))
                .toList(),
          ),
          PopupMenuButton<AspectOpt>(
            icon: const Icon(Icons.aspect_ratio),
            onSelected: (v) => setState(() => aspect = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: AspectOpt.sensor,
                  child: Text('Sensor (vista completa)')),
              PopupMenuItem(
                  value: AspectOpt.a16x9,
                  child: Text('16:9 recorte al guardar')),
              PopupMenuItem(
                  value: AspectOpt.a4x3, child: Text('4:3 recorte al guardar')),
              PopupMenuItem(
                  value: AspectOpt.a1x1, child: Text('1:1 recorte al guardar')),
            ],
          ),
        ],
      ),
      body: cam == null || !cam.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Builder(builder: (_) {
                  final ps = cam.value.previewSize;
                  final ar = ps != null ? ps.height / ps.width : (4 / 3);
                  return Center(
                      child: AspectRatio(
                          aspectRatio: ar, child: CameraPreview(cam)));
                }),
              ],
            ),
      bottomNavigationBar: cam == null || !cam.value.isInitialized
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (maxZoom != minZoom) ...[
                      Row(
                        children: [
                          const Icon(Icons.zoom_out, color: Colors.white70),
                          Expanded(
                            child: Slider(
                              min: minZoom,
                              max: maxZoom,
                              value: zoom.clamp(minZoom, maxZoom),
                              onChanged: (v) async {
                                setState(() => zoom = v);
                                await controller?.setZoomLevel(v);
                              },
                            ),
                          ),
                          const Icon(Icons.zoom_in, color: Colors.white70),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    FloatingActionButton.large(
                      onPressed: _takePhoto,
                      child: const Icon(Icons.camera_alt),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
