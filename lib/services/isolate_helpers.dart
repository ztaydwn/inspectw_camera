import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:archive/archive_io.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models.dart';

// Helper class to pass arguments to the photo saving isolate
class SavePhotoParams {
  final XFile xFile;
  final String description;
  final String project;
  final String location;
  final double? aspect;
  final RootIsolateToken token;

  SavePhotoParams({
    required this.xFile,
    required this.description,
    required this.project,
    required this.location,
    required this.token,
    this.aspect,
  });
}

// Result returned after saving a photo to MediaStore
class SavePhotoResult {
  final String fileName;
  final String relativePath;
  final String description;

  SavePhotoResult(
      {required this.fileName,
      required this.relativePath,
      required this.description});
}

// Result from processing a photo in an isolate
class ProcessPhotoResult {
  final String filePath;
  final bool isTempFile;

  ProcessPhotoResult({required this.filePath, required this.isTempFile});
}

/// ISOLATE: Processes a photo (crop/aspect) and returns a path to a file to save.
Future<ProcessPhotoResult?> processPhotoIsolate(SavePhotoParams params) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(params.token);

  final bytes = await params.xFile.readAsBytes();
  final image = img.decodeImage(bytes);

  if (image == null) {
    // Could not decode image, return original file path if possible
    return ProcessPhotoResult(filePath: params.xFile.path, isTempFile: false);
  }

  img.Image processedImage = image;

  // 1. Apply cropping if an aspect ratio is provided
  if (params.aspect != null) {
    final w = image.width;
    final h = image.height;
    final currentAspect = w / h;
    int cropWidth = w, cropHeight = h, x = 0, y = 0;

    if (currentAspect > params.aspect!) {
      // Wider than target: crop width
      cropWidth = (h * params.aspect!).round();
      x = ((w - cropWidth) / 2).round();
    } else if (currentAspect < params.aspect!) {
      // Taller than target: crop height
      cropHeight = (w / params.aspect!).round();
      y = ((h - cropHeight) / 2).round();
    }
    processedImage =
        img.copyCrop(image, x: x, y: y, width: cropWidth, height: cropHeight);
  }

  // 2. Re-encode as JPEG with high quality, but do NOT downscale.
  final processedBytes = img.encodeJpg(processedImage, quality: 95);

  // 3. Save to a new temporary file to avoid overwriting the original.
  final tempDir = await getTemporaryDirectory();
  final tempFile = File(p.join(tempDir.path, p.basename(params.xFile.path)));
  await tempFile.writeAsBytes(processedBytes, flush: true);

  return ProcessPhotoResult(filePath: tempFile.path, isTempFile: true);
}

/// ISOLATE: Top-level function to process and save a photo.
Future<SavePhotoResult?> savePhotoIsolate(SavePhotoParams params) async {
  // This now includes file processing AND saving to media store
  final processed = await processPhotoIsolate(params);
  if (processed == null) return null;

  await MediaStore.ensureInitialized();
  // Guardar fotos en DCIM/<proyecto>/<ubicacion>.
  // Usamos relativePath con "proyecto/ubicacion"; el appFolder no se usa por DCIM.
  MediaStore.appFolder = kAppFolder; // mantener consistente con inicialización
  final mediaStore = MediaStore();
  final saveInfo = await mediaStore.saveFile(
    tempFilePath: processed.filePath,
    dirType: DirType.photo,
    dirName: DirName.dcim,
    // Usar la ruta relativa completa para crear DCIM/<proyecto>/<ubicacion>.
    relativePath: '${params.project}/${params.location}',
  );

  // Clean up temp file
  if (processed.isTempFile) {
    try {
      final tempFile = File(processed.filePath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      debugPrint('[Isolate] Failed to delete temp file: $e');
    }
  }

  if (saveInfo == null || !saveInfo.isSuccessful) {
    return null;
  }

  return SavePhotoResult(
    fileName: saveInfo.name,
    relativePath: saveInfo.uri.path,
    description: params.description, // Pass description through
  );
}

// Helper class to pass arguments to the zip creation isolate
class CreateZipParams {
  final List<PhotoEntry> photos;
  final String project;
  final String descriptions;
  final String projectDataReport; // Added
  final List<String> resolvedPaths;

  CreateZipParams(
      {required this.photos,
      required this.project,
      required this.descriptions,
      required this.projectDataReport, // Added
      required this.resolvedPaths});
}

/// ISOLATE: Creates a zip file from photos.
Future<String?> createZipIsolate(CreateZipParams params) async {
  final zipName =
      '${params.project}_${DateTime.now().millisecondsSinceEpoch}.zip';
  final zipPath = p.join(Directory.systemTemp.path, zipName);
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  for (var i = 0; i < params.photos.length; i++) {
    final photo = params.photos[i];
    final path = params.resolvedPaths[i];
    final fileInDcim = File(path);
    if (fileInDcim.existsSync()) {
      final bytes = await fileInDcim.readAsBytes();
      final archivePath = p.join(photo.location, photo.fileName);
      encoder.addArchiveFile(ArchiveFile(archivePath, bytes.length, bytes));
    }
  }

  final descBytes = utf8.encode(params.descriptions);
  encoder.addArchiveFile(
      ArchiveFile('descriptions.txt', descBytes.length, descBytes));

  final projectDataBytes = utf8.encode(params.projectDataReport);
  encoder.addArchiveFile(
      ArchiveFile('infoproyect.txt', projectDataBytes.length, projectDataBytes));

  encoder.close();
  return zipPath;
}

/// ISOLATE ENTRY: Creates a zip file and reports progress via SendPort.
/// Expects a Map with keys:
///  - 'sendPort': SendPort to post progress/done/error messages
///  - 'params': CreateZipParams with photos/resolvedPaths/etc.
void createZipWithProgressIsolate(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'] as SendPort;
  final CreateZipParams params = args['params'] as CreateZipParams;

  try {
    final total = params.photos.length + 2; // photos + descriptions + infoproyect
    final zipName =
        '${params.project}_${DateTime.now().millisecondsSinceEpoch}.zip';
    final zipPath = p.join(Directory.systemTemp.path, zipName);

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    for (var i = 0; i < params.photos.length; i++) {
      final photo = params.photos[i];
      final path = params.resolvedPaths[i];
      final fileInDcim = File(path);
      if (fileInDcim.existsSync()) {
        // Stream file contents instead of loading entire bytes in memory
        final archivePath = p.join(photo.location, photo.fileName);
        final size = await fileInDcim.length();
        final input = InputFileStream(path);
        encoder.addArchiveFile(ArchiveFile.stream(archivePath, size, input));
      }
      sendPort.send({'type': 'progress', 'current': i + 1, 'total': total});
    }

    // Add descriptions.txt
    final descBytes = utf8.encode(params.descriptions);
    encoder.addArchiveFile(
        ArchiveFile('descriptions.txt', descBytes.length, descBytes));
    sendPort.send(
        {'type': 'progress', 'current': params.photos.length + 1, 'total': total});

    // Add infoproyect.txt
    final projectDataBytes = utf8.encode(params.projectDataReport);
    encoder.addArchiveFile(
        ArchiveFile('infoproyect.txt', projectDataBytes.length, projectDataBytes));
    sendPort.send(
        {'type': 'progress', 'current': params.photos.length + 2, 'total': total});

    encoder.close();
    sendPort.send({'type': 'done', 'zipPath': zipPath});
  } catch (e, s) {
    debugPrint('[ZIP] isolate error: $e\n$s');
    sendPort.send({'type': 'error', 'error': e.toString()});
  }
}

/// ISOLATE: Persists metadata to a file.
Future<void> persistMetadataIsolate(Map<String, dynamic> params) async {
  final File file = params['file'];
  final dynamic content = params['content'];
  await file.writeAsString(jsonEncode(content), flush: true);
}
