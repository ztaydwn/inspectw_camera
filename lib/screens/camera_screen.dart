// lib/screens/camera_screen.dart — v10 (with focal length support)
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:image/image.dart' as img;

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

  // ASEGÚRATE DE QUE ESTA FUNCIÓN ESTÉ AQUÍ
  Future<void> _mapFocalLengths() async {
    availableFocalLengths.clear();

    // 1. Obtener solo las cámaras traseras
    final backCameras = cameras
        .where((cam) => cam.lensDirection == CameraLensDirection.back)
        .toList();
    if (backCameras.isEmpty) return;

    CameraDescription? mainCamera = backCameras.first;
    CameraDescription? ultraWideCamera;
    CameraDescription? telephotoCamera;

    // 2. Asignar la cámara principal y buscar lentes especializadas en el resto
    final otherCameras = backCameras.where((c) => c != mainCamera).toList();
    for (final camera in otherCameras) {
      final name = camera.name.toLowerCase();
      if (name.contains('ultra') && ultraWideCamera == null) {
        ultraWideCamera = camera;
      } else if (name.contains('tele') && telephotoCamera == null) {
        telephotoCamera = camera;
      }
    }

    if (backCameras.length == 2 &&
        ultraWideCamera == null &&
        telephotoCamera == null) {
      ultraWideCamera = otherCameras.first;
    }

    // 4. Construir la lista de distancias focales físicas disponibles
    if (ultraWideCamera != null) {
      availableFocalLengths.add(FocalLength(
        value: 0.6,
        label: '0.6x',
        camera: ultraWideCamera,
      ));
    }

    availableFocalLengths.add(FocalLength(
      value: 1.0,
      label: '1x',
      camera: mainCamera,
    ));

    if (telephotoCamera != null) {
      availableFocalLengths.add(FocalLength(
        value: 2.0,
        label: '2x',
        camera: telephotoCamera,
      ));
    }

    // 5. Para cualquier objetivo faltante, crear un fallback con zoom digital
    for (final target in targetFocalLengths) {
      // <-- Aquí se usa la variable
      bool hasPhysicalCamera = availableFocalLengths
          .any((fl) => fl.value == target && !fl.isDigitalZoom);
      if (!hasPhysicalCamera) {
        double digitalZoomFactor = target / 1.0;
        availableFocalLengths.add(FocalLength(
          value: target,
          label: '${target}x (Digital)',
          camera: null,
          digitalZoom: digitalZoomFactor,
        ));
      }
    }

    // 6. Ordenar y seleccionar la distancia focal inicial
    availableFocalLengths.sort((a, b) => a.value.compareTo(b.value));
    if (availableFocalLengths.isNotEmpty) {
      selectedFocalLength = availableFocalLengths.firstWhere(
          (fl) => fl.value == 1.0,
          orElse: () => availableFocalLengths.first);
    }

    debugPrint(
        '[Camera] Mapped focal lengths: ${availableFocalLengths.map((fl) => '${fl.label} (${fl.camera?.name ?? "Digital"})').join(", ")}');
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

      // --- START OF ADDED DEBUG CODE ---
      final imageBytes = await xFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage != null) {
        debugPrint(
            '[CAMERA DEBUG] Captured photo resolution: ${decodedImage.width}x${decodedImage.height}');
      }
      // --- END OF ADDED DEBUG CODE ---

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

  Future<String?> _askForDescription() async {
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