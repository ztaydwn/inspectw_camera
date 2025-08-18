// lib/screens/camera_screen.dart — v8 (performance refactor)
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../services/isolate_helpers.dart';
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
  FlashMode flash = FlashMode.auto;
  double zoom = 1.0, minZoom = 1.0, maxZoom = 4.0;
  int selectedBackIndex = 0;
  AspectOpt aspect = AspectOpt.sensor;
  bool _isTakingPhoto = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (Platform.isAndroid) {
      await MediaStore.ensureInitialized();
      MediaStore.appFolder = kAppFolder;
    }
    await _initCam();
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

  Future<void> _initCam() async {
    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permiso de cámara denegado.'),
          action: SnackBarAction(
            label: 'Abrir ajustes',
            onPressed: openAppSettings,
          ),
        ));
      }
      return;
    }

    // Request storage permission
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      PermissionStatus storageStatus;
      if (androidInfo.version.sdkInt >= 33) {
        storageStatus = await Permission.photos.request();
      } else {
        storageStatus = await Permission.storage.request();
      }

      if (!storageStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permiso de almacenamiento denegado.'),
            action: SnackBarAction(
              label: 'Abrir ajustes',
              onPressed: openAppSettings,
            ),
          ));
        }
        return;
      }
    }

    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se encontraron cámaras.')));
        }
        return;
      }
      final backs = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();
      selectedBackIndex = backs.isNotEmpty ? cameras.indexOf(backs.first) : 0;
      await _startController();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al iniciar la cámara: $e')));
      }
    }
  }

  Future<void> _startController() async {
    if (cameras.isEmpty) return;
    final cam = CameraController(cameras[selectedBackIndex], preset,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    controller = cam;
    try {
      await cam.initialize();
      await cam.unlockCaptureOrientation();
      minZoom = await cam.getMinZoomLevel();
      maxZoom = await cam.getMaxZoomLevel();
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
      await cam.setFlashMode(flash);
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

  Future<String?> _askForDescription() {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DescriptionInput(project: widget.project),
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
              content: Text('Error: No se pudo guardar la foto en la galería.')));
        }
        if (processed.isTempFile) {
          try {
            await File(processed.filePath).delete();
          } catch (_) {}
        }
        return null;
      }

      final result =
          SavePhotoResult(fileName: saveInfo.name, relativePath: saveInfo.uri.path);

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
          await File(processed.filePath).delete();
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

  @override
  Widget build(BuildContext context) {
    final cam = controller;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.project} / ${widget.location}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () async {
                if (cameras.isEmpty) return;
                selectedBackIndex = (selectedBackIndex + 1) % cameras.length;
                await _startController();
              }),
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
          : Builder(builder: (_) {
              final ps = cam.value.previewSize;
              final ar = ps != null ? ps.height / ps.width : (4 / 3);
              return Center(
                  child:
                      AspectRatio(aspectRatio: ar, child: CameraPreview(cam)));
            }),
      bottomNavigationBar: cam == null || !cam.value.isInitialized
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      min: minZoom,
                      max: maxZoom,
                      value: zoom.clamp(minZoom, maxZoom),
                      onChanged: (v) async {
                        setState(() => zoom = v);
                        await controller?.setZoomLevel(v);
                      },
                    ),
                    const SizedBox(height: 8),
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
