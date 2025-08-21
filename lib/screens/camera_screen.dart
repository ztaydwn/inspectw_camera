// lib/screens/camera_screen.dart — v9 (with focal length support)
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';

import '../services/isolate_helpers.dart';
import '../services/metadata_service.dart';
import '../widgets/description_input.dart';
import '../constants.dart';

enum AspectOpt { sensor, a16x9, a4x3, a1x1 }

// Clase para mapear distancias focales
class FocalLength {
  final double value; // Equivalente en 35mm
  final String label;
  final CameraDescription? camera; // null si es zoom digital
  final double? digitalZoom; // Factor de zoom digital si aplica

  const FocalLength({
    required this.value,
    required this.label,
    this.camera,
    this.digitalZoom,
  });

  bool get isDigitalZoom => camera == null;
}

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
  List<FocalLength> availableFocalLengths = [];
  FocalLength? selectedFocalLength;

  ResolutionPreset preset = ResolutionPreset.max;
  FlashMode _flashMode = FlashMode.off;
  double zoom = 1.0, minZoom = 1.0, maxZoom = 4.0;
  int selectedBackIndex = 0;
  AspectOpt aspect = AspectOpt.sensor;
  bool _isTakingPhoto = false;

  // Distancias focales objetivo (equivalente 35mm)
  static const List<double> targetFocalLengths = [0.6, 1.0, 2.0];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    await _mapFocalLengths();
    await _startController();
  }

  @override
  void dispose() {
    controller?.dispose();
    SystemChrome.setPreferredOrientations(
        DeviceOrientation.values); // restaurar
    super.dispose();
  }

  Future<void> _mapFocalLengths() async {
    availableFocalLengths.clear();

    // Obtener solo cámaras traseras
    final backCameras = cameras
        .where((cam) => cam.lensDirection == CameraLensDirection.back)
        .toList();

    if (backCameras.isEmpty) return;

    // Mapear cámaras físicas disponibles
    final mappedCameras = <double, CameraDescription>{};

    for (final camera in backCameras) {
      // Intentar obtener la distancia focal real
      double? focalLength = await _getCameraFocalLength(camera);

      if (focalLength != null) {
        // Buscar la distancia focal objetivo más cercana
        double closestTarget = targetFocalLengths.reduce((a, b) =>
            (a - focalLength).abs() < (b - focalLength).abs() ? a : b);

        // Si no hay una cámara más cercana para este objetivo, usarla
        if (!mappedCameras.containsKey(closestTarget) ||
            (mappedCameras[closestTarget] != camera &&
                (closestTarget - focalLength).abs() <
                    (closestTarget -
                            (await _getCameraFocalLength(
                                    mappedCameras[closestTarget]!) ??
                                0))
                        .abs())) {
          mappedCameras[closestTarget] = camera;
        }
      }
    }

    // Crear FocalLength objects para cámaras físicas
    for (final target in targetFocalLengths) {
      if (mappedCameras.containsKey(target)) {
        availableFocalLengths.add(FocalLength(
          value: target,
          label: '${target}x',
          camera: mappedCameras[target],
        ));
      }
    }

    // Si no tenemos todas las distancias focales, crear fallbacks con zoom digital
    final mainCamera = backCameras.first;
    final mainFocalLength = await _getCameraFocalLength(mainCamera) ?? 1.0;

    for (final target in targetFocalLengths) {
      bool hasPhysicalCamera = availableFocalLengths
          .any((fl) => fl.value == target && !fl.isDigitalZoom);

      if (!hasPhysicalCamera) {
        // Calcular el zoom digital necesario
        double digitalZoomFactor = target / mainFocalLength;

        availableFocalLengths.add(FocalLength(
          value: target,
          label: '${target}x (Digital)',
          camera: null, // Indica zoom digital
          digitalZoom: digitalZoomFactor,
        ));
      }
    }

    // Ordenar por valor
    availableFocalLengths.sort((a, b) => a.value.compareTo(b.value));

    // Seleccionar la primera disponible
    if (availableFocalLengths.isNotEmpty) {
      selectedFocalLength = availableFocalLengths.first;
    }

    debugPrint(
        '[Camera] Available focal lengths: ${availableFocalLengths.map((fl) => '${fl.value}x (${fl.isDigitalZoom ? "Digital" : "Physical"})').join(", ")}');
  }

  Future<double?> _getCameraFocalLength(CameraDescription camera) async {
    try {
      // En Android, intentar obtener características de la cámara
      if (Platform.isAndroid) {
        // Estimaciones basadas en nombres comunes de cámara
        final name = camera.name.toLowerCase();

        if (name.contains('ultra') || name.contains('wide')) {
          return 0.6; // Ultra wide típicamente
        } else if (name.contains('telephoto') || name.contains('tele')) {
          return 2.0; // Telephoto típicamente
        } else {
          return 1.0; // Cámara principal
        }
      }

      // En iOS, similar lógica
      if (Platform.isIOS) {
        final name = camera.name.toLowerCase();

        if (name.contains('0.5') || name.contains('ultra')) {
          return 0.6;
        } else if (name.contains('2') || name.contains('telephoto')) {
          return 2.0;
        } else {
          return 1.0;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[Camera] Error getting focal length for ${camera.name}: $e');
      return null;
    }
  }

  Future<void> _switchToFocalLength(FocalLength focalLength) async {
    if (selectedFocalLength == focalLength) return;

    setState(() => selectedFocalLength = focalLength);

    if (focalLength.isDigitalZoom) {
      // Usar zoom digital en la cámara actual
      if (focalLength.digitalZoom != null) {
        final zoomLevel =
            (focalLength.digitalZoom! * minZoom).clamp(minZoom, maxZoom);
        await controller?.setZoomLevel(zoomLevel);
        setState(() => zoom = zoomLevel);
      }
    } else {
      // Cambiar a cámara física diferente
      if (focalLength.camera != null) {
        await controller?.dispose();

        // Encontrar el índice de la nueva cámara
        selectedBackIndex = cameras.indexOf(focalLength.camera!);

        await _startController();

        // Resetear zoom al cambiar de cámara
        setState(() => zoom = minZoom);
      }
    }
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

      // Si estamos usando una cámara para distancia focal específica,
      // ajustar el zoom inicial si es necesario
      if (selectedFocalLength?.isDigitalZoom == true &&
          selectedFocalLength?.digitalZoom != null) {
        final zoomLevel = (selectedFocalLength!.digitalZoom! * minZoom)
            .clamp(minZoom, maxZoom);
        await cam.setZoomLevel(zoomLevel);
        zoom = zoomLevel;
      } else {
        zoom = minZoom;
      }
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error de cámara: ${e.description}')));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _takePhoto() async {
    if (_isTakingPhoto) return;
    final cam = controller;
    if (cam == null || !cam.value.isInitialized) return;

    setState(() => _isTakingPhoto = true);

    try {
      await cam.setFlashMode(_flashMode);
      final xFile = await cam.takePicture();
      debugPrint('[Camera] temp: ${xFile.path}');

      final desc = await _askForDescription();
      if (desc == null) return; // User cancelled

      final result = await _savePhoto(xFile, desc);
      if (result == null) return; // Save failed

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Foto guardada: ${result.fileName}')));
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
    } finally {
      if (mounted) setState(() => _isTakingPhoto = false);
    }
  }

  Future<String?> _askForDescription({String? initialHint}) async {
    // ignore: prefer_const_declarations
    final presets = kDefaultDescriptions;

    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DescriptionInput(
          project: widget.project,
          initial: initialHint,
          presets: presets,
        ),
      ),
    );
  }

  Future<SavePhotoResult?> _savePhoto(XFile xFile, String description) async {
    try {
      final token = RootIsolateToken.instance!;
      final params = SavePhotoParams(
        xFile: xFile,
        description: description,
        project: widget.project,
        location: widget.location,
        aspect: _aspectToDouble(aspect),
        token: token,
      );

      // Process image data off the main isolate
      final processed = await compute(processPhotoIsolate, params);

      if (processed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Error: No se pudo procesar la foto.')));
        }
        return null;
      }

      await MediaStore.ensureInitialized();
      MediaStore.appFolder = kAppFolder;
      final mediaStore = MediaStore();
      final saveInfo = await mediaStore.saveFile(
        tempFilePath: processed.filePath,
        dirType: DirType.photo,
        dirName: DirName.dcim,
        relativePath: '${widget.project}/${widget.location}',
      );

      if (saveInfo == null || !saveInfo.isSuccessful) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Error: No se pudo guardar la foto en la galería.')));
        }
        if (processed.isTempFile) {
          try {
            await File(processed.filePath).delete();
          } catch (_) {}
        }
        return null;
      }

      final result = SavePhotoResult(
          fileName: saveInfo.name, relativePath: saveInfo.uri.path);

      if (!mounted) return null;
      await context.read<MetadataService>().addPhoto(
            project: widget.project,
            location: widget.location,
            fileName: result.fileName,
            relativePath: result.relativePath,
            description: description,
            takenAt: DateTime.now(),
          );

      if (processed.isTempFile) {
        try {
          if (processed.filePath.isNotEmpty) {
            final src = File(processed.filePath);
            if (await src.exists()) {
              await src.delete();
            }
          }
        } catch (_) {}
      }

      return result;
    } catch (e) {
      debugPrint('[Camera] Error saving photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar la foto: $e')));
      }
      return null;
    }
  }

  Widget _buildFocalLengthSelector() {
    if (availableFocalLengths.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: availableFocalLengths.map((fl) {
          final isSelected = selectedFocalLength == fl;
          return GestureDetector(
            onTap: () => _switchToFocalLength(fl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                fl.label,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cam = controller;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.project} / ${widget.location}'),
        actions: [
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
                // Camera preview
                Builder(builder: (_) {
                  final ps = cam.value.previewSize;
                  final ar = ps != null ? ps.height / ps.width : (4 / 3);
                  return Center(
                      child: AspectRatio(
                          aspectRatio: ar, child: CameraPreview(cam)));
                }),
                // Focal length selector
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildFocalLengthSelector()),
                ),
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
                    // Zoom slider (solo cuando no es la distancia focal base)
                    if (selectedFocalLength?.isDigitalZoom != true ||
                        zoom != minZoom) ...[
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
                      onPressed: _isTakingPhoto ? null : _takePhoto,
                      child: _isTakingPhoto
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.camera_alt),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
