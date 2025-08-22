// lib/screens/camera_screen.dart — v10 (physical camera support)
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';

import '../constants.dart';
import '../services/isolate_helpers.dart';
import '../services/metadata_service.dart';
import '../widgets/description_input.dart';

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
  CameraDescription? _logicalCamera;

  ResolutionPreset preset = ResolutionPreset.max;
  FlashMode _flashMode = FlashMode.off;
  double zoom = 1.0, minZoom = 1.0, maxZoom = 1.0;
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

  @override
  void dispose() {
    controller?.dispose();
    SystemChrome.setPreferredOrientations(
        DeviceOrientation.values); // restaurar
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();
      _logicalCamera = cameras
          .firstWhere((cam) => cam.lensDirection == CameraLensDirection.back);

      await _startControllerForCamera(_logicalCamera!);
      await _mapFocalLengths();
    } catch (e) {
      debugPrint('[Camera] Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al iniciar la cámara: $e')));
      }
    }
  }

  Future<void> _startControllerForCamera(CameraDescription camera) async {
    if (controller?.description == camera) return;

    await controller?.dispose();

    final cam = CameraController(camera, preset,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    controller = cam;

    try {
      await cam.initialize();
      await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
      minZoom = await cam.getMinZoomLevel();
      maxZoom = await cam.getMaxZoomLevel();
      zoom = minZoom;
    } on CameraException catch (e) {
      debugPrint('[Camera] Error creating controller: ${e.description}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error de cámara: ${e.description}')));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _mapFocalLengths() async {
    availableFocalLengths.clear();
    List<CameraDescription> physicalCameras = [];

    // En Android, intenta obtener las cámaras físicas
    if (Platform.isAndroid && controller != null) {
      try {
        physicalCameras = await controller!.getPhysicalCameras();
      } on CameraException catch (e) {
        debugPrint('[Camera] Could not get physical cameras: ${e.description}');
      }
    }

    // Si no hay cámaras físicas (o no es Android), usa la lógica
    if (physicalCameras.isEmpty) {
      physicalCameras.add(_logicalCamera!);
    }

    debugPrint('[Camera] Found ${physicalCameras.length} physical cameras.');

    final mappedCameras = <double, CameraDescription>{};

    // Asumir un orden: la primera es ultra-wide, la segunda wide, etc.
    // Esto es una heurística y puede no ser perfecto en todos los dispositivos.
    if (physicalCameras.length >= 3) {
      mappedCameras[0.6] = physicalCameras[0]; // Ultra-wide
      mappedCameras[1.0] = physicalCameras[1]; // Wide (Main)
      mappedCameras[2.0] = physicalCameras[2]; // Telephoto
    } else if (physicalCameras.length == 2) {
      mappedCameras[0.6] = physicalCameras[0];
      mappedCameras[1.0] = physicalCameras[1];
    } else if (physicalCameras.length == 1) {
      mappedCameras[1.0] = physicalCameras[0];
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

    // Fallback con zoom digital si faltan lentes
    final mainCamera = mappedCameras[1.0] ?? _logicalCamera!;
    for (final target in targetFocalLengths) {
      if (!availableFocalLengths.any((fl) => fl.value == target)) {
        double digitalZoomFactor = target; // Asumimos que 1.0 es la base
        availableFocalLengths.add(FocalLength(
          value: target,
          label: '${target}x (Digital)',
          camera: null,
          digitalZoom: digitalZoomFactor,
        ));
      }
    }

    availableFocalLengths.sort((a, b) => a.value.compareTo(b.value));

    // Seleccionar 1.0x por defecto
    selectedFocalLength = availableFocalLengths.firstWhere(
        (fl) => fl.value == 1.0,
        orElse: () => availableFocalLengths.first);

    debugPrint(
        '[Camera] Available focal lengths: ${availableFocalLengths.map((fl) => '${fl.label} (${fl.isDigitalZoom ? "Digital" : fl.camera?.name})').join(", ")}');

    setState(() {});
  }

  Future<void> _switchToFocalLength(FocalLength focalLength) async {
    if (selectedFocalLength?.value == focalLength.value) return;

    setState(() => selectedFocalLength = focalLength);

    if (focalLength.isDigitalZoom) {
      // Cambiar a la cámara principal si no estamos en ella
      if (controller?.description != _logicalCamera) {
        await _startControllerForCamera(_logicalCamera!);
      }
      // Aplicar zoom digital
      if (focalLength.digitalZoom != null) {
        final zoomLevel = (focalLength.digitalZoom!).clamp(minZoom, maxZoom);
        await controller?.setZoomLevel(zoomLevel);
        setState(() => zoom = zoomLevel);
      }
    } else {
      // Cambiar a cámara física diferente
      if (focalLength.camera != null) {
        await _startControllerForCamera(focalLength.camera!);
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

  Future<void> _takePhoto() async {
    if (_isTakingPhoto) return;
    final cam = controller;
    if (cam == null || !cam.value.isInitialized) return;

    setState(() => _isTakingPhoto = true);

    try {
      // El flash debe ser off o auto para tomar foto, torch es para preview
      if (_flashMode == FlashMode.torch) {
        await cam.setFlashMode(FlashMode.off);
      }

      final xFile = await cam.takePicture();
      debugPrint('[Camera] temp: ${xFile.path}');

      // Restaurar el modo torch si estaba activado
      if (_flashMode == FlashMode.torch) {
        await cam.setFlashMode(FlashMode.torch);
      }

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
    if (availableFocalLengths.length <= 1) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: availableFocalLengths.map((fl) {
          final isSelected = selectedFocalLength?.value == fl.value;
          return GestureDetector(
            onTap: () => _switchToFocalLength(fl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.project} / ${widget.location}'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
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
              await _startControllerForCamera(controller!.description);
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
              alignment: Alignment.center,
              children: [
                // Camera preview
                AspectRatio(
                  aspectRatio: cam.value.aspectRatio,
                  child: CameraPreview(cam),
                ),
                // UI Overlay
                Positioned.fill(
                  child: Column(
                    children: [
                      const Spacer(),
                      _buildFocalLengthSelector(),
                      const SizedBox(height: 16),
                    ],
                  ),
                )
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
                    if (selectedFocalLength?.isDigitalZoom == true) ...[
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
