// lib/screens/camera_screen.dart — v7 (refactor single save)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:image/image.dart' as img;

import '../services/metadata_service.dart';
import '../widgets/description_input.dart';

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
      MediaStore.appFolder = 'InspectW';
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
    final status = await Permission.camera.request();
    if (!status.isGranted) {
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

      final fileName = await _savePhotoToDcim(xFile, desc);
      if (fileName == null) return; // Save failed

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Foto guardada: $fileName')));
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

  Future<String?> _savePhotoToDcim(XFile xFile, String description) async {
    File? tempFile; // To hold the temporary file, if created
    try {
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'IMG_$ts.jpg';
      final relativePath = p.join(widget.project, widget.location);

      Uint8List bytes = await xFile.readAsBytes();

      // Crop if needed
      final a = _aspectToDouble(aspect);
      if (a != null) {
        bytes = await _cropToAspect(bytes, a);
      }

      // MediaStore.saveFile needs a path, so if we cropped, we must
      // write the modified bytes to a new temporary file.
      String filePathToSave = xFile.path;
      if (a != null) {
        final tempDir = await getTemporaryDirectory();
        tempFile = File(p.join(tempDir.path, fileName));
        await tempFile.writeAsBytes(bytes, flush: true);
        filePathToSave = tempFile.path;
      }

      SaveInfo? saveInfo;
      // Save to Gallery
      if (Platform.isAndroid) {
        final mediaStore = MediaStore();
        saveInfo = await mediaStore.saveFile(
          tempFilePath: filePathToSave,
          dirType: DirType.photo,
          dirName: DirName.dcim,
          relativePath: relativePath,
        );
        debugPrint(
            '[Camera] Saved to DCIM in path: $relativePath. Uri: ${saveInfo?.uri}, name: ${saveInfo?.name}, duplicated: ${saveInfo?.isDuplicated}');
      } else {
        // Handle non-Android platforms if necessary
        debugPrint('[Camera] Skipping DCIM save on non-Android platform.');
        return null;
      }

      // If the file was not saved successfully, show an error and exit.
      if (saveInfo == null) {
        debugPrint('[Camera] MediaStore.saveFile failed.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Error: No se pudo guardar la foto en la galería.')));
        }
        return null;
      }

      // Save metadata
      if (!mounted) return null;

      // IMPORTANT: The relativePath for metadata MUST match how the file was
      // saved by media_store. It creates a structure like:
      // /storage/emulated/0/DCIM/InspectW/PROJECT/LOCATION/file.jpg
      // The part we need to store is from "InspectW" onwards.
      final metadataRelativePath =
          p.join(MediaStore.appFolder, relativePath, fileName);

      await context.read<MetadataService>().addPhoto(
            project: widget.project,
            location: widget.location,
            fileName: fileName,
            relativePath: metadataRelativePath,
            description: description,
            takenAt: DateTime.now(),
          );

      return fileName;
    } catch (e) {
      debugPrint('[Camera] Error saving photo to DCIM: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar la foto: $e')));
      }
      return null;
    } finally {
      // Clean up the temporary file if it was created
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } catch (e) {
          debugPrint('[Camera] Error deleting temp file: $e');
        }
      }
    }
  }

  Future<Uint8List> _cropToAspect(Uint8List bytes, double aspect) async {
    try {
      final i = img.decodeImage(bytes);
      if (i == null) return bytes;
      final w = i.width, h = i.height;
      final cur = w / h;
      int cw = w, ch = h, x = 0, y = 0;
      if (cur > aspect) {
        cw = (h * aspect).round();
        x = ((w - cw) / 2).round();
      } else if (cur < aspect) {
        ch = (w / aspect).round();
        y = ((h - ch) / 2).round();
      }
      return Uint8List.fromList(img.encodeJpg(
          img.copyCrop(i, x: x, y: y, width: cw, height: ch),
          quality: 92));
    } catch (e) {
      debugPrint('[Camera] crop error: $e');
      return bytes; // Return original bytes on error
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