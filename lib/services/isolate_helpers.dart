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
import '../utils/path_utils.dart';

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

  // Fallback para plataformas no-Android: guardar en almacenamiento interno de la app
  if (!Platform.isAndroid) {
    final appDir = await getApplicationDocumentsDirectory();
    final locationDir = Directory(
        p.join(appDir.path, 'projects', params.project, params.location));
    if (!locationDir.existsSync()) {
      locationDir.createSync(recursive: true);
    }
    final newName = p.basename(processed.filePath);
    final destPath = p.join(locationDir.path, newName);

    await File(processed.filePath).copy(destPath);

    // Limpiar temporal si aplica
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

    final relative = p.url.join(
        'projects', params.project, params.location, p.basename(destPath));
    return SavePhotoResult(
      fileName: p.basename(destPath),
      relativePath: 'internal/$relative',
      description: params.description,
    );
  }

  // Android: guardar en MediaStore (DCIM/<proyecto>/<ubicacion>)
  await MediaStore.ensureInitialized();
  MediaStore.appFolder = kAppFolder; // mantener consistente con inicialización
  final mediaStore = MediaStore();
  final saveInfo = await mediaStore.saveFile(
    tempFilePath: processed.filePath,
    dirType: DirType.photo,
    dirName: DirName.dcim,
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
    // Guardar el content URI COMPLETO para mayor estabilidad entre dispositivos
    relativePath: saveInfo.uri.toString(),
    description: params.description, // Pass description through
  );
}

// Helper class to pass arguments to the zip creation isolate
class CreateZipParams {
  final List<PhotoEntry> photos;
  final String project;
  final String? location; // Can be null for full project export
  final String descriptions;
  final String projectDataReport; // Added
  final List<String> resolvedPaths;
  // Raw JSONs to include in the ZIP
  final String rawMetadataJson;
  final String rawDescriptionsJson;
  final String rawLocationStatusJson;
  final String rawProjectDataJson;

  CreateZipParams(
      {required this.photos,
      required this.project,
      this.location,
      required this.descriptions,
      required this.projectDataReport, // Added
      required this.resolvedPaths,
      required this.rawMetadataJson,
      required this.rawDescriptionsJson,
      required this.rawLocationStatusJson,
      required this.rawProjectDataJson});
}

/// ISOLATE: Creates a zip file from photos.
Future<String?> createZipIsolate(CreateZipParams params) async {
  final proj = sanitizeFileName(params.project);
  final locPart = params.location != null ? '_${sanitizeFileName(params.location!)}' : '';
  final zipName = '$proj${locPart}_${DateTime.now().millisecondsSinceEpoch}.zip';
  final zipPath = p.join(Directory.systemTemp.path, zipName);
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  for (var i = 0; i < params.photos.length; i++) {
    final photo = params.photos[i];
    final path = params.resolvedPaths[i];
    final fileInDcim = File(path);
    if (fileInDcim.existsSync()) {
      final bytes = await fileInDcim.readAsBytes();
      // Use POSIX separators inside the ZIP for portability
      final archivePath = p.posix.join(photo.location, photo.fileName);
      encoder.addArchiveFile(ArchiveFile(archivePath, bytes.length, bytes));
    }
  }

  final descBytes = utf8.encode(params.descriptions);
  encoder.addArchiveFile(
      ArchiveFile('descriptions.txt', descBytes.length, descBytes));

  final projectDataBytes = utf8.encode(params.projectDataReport);
  encoder.addArchiveFile(ArchiveFile(
      'infoproyect.txt', projectDataBytes.length, projectDataBytes));

  // Add raw JSON data files under data/
  final metaJson = utf8.encode(params.rawMetadataJson);
  encoder.addArchiveFile(
      ArchiveFile('data/metadata.json', metaJson.length, metaJson));
  final descJson = utf8.encode(params.rawDescriptionsJson);
  encoder.addArchiveFile(
      ArchiveFile('data/descriptions.json', descJson.length, descJson));
  final statusJson = utf8.encode(params.rawLocationStatusJson);
  encoder.addArchiveFile(ArchiveFile(
      'data/location_status.json', statusJson.length, statusJson));
  final projectDataJson = utf8.encode(params.rawProjectDataJson);
  encoder.addArchiveFile(ArchiveFile(
      'data/project_data.json', projectDataJson.length, projectDataJson));

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
    final total = params.photos.length + 6; // photos + descriptions + infoproyect + 4 JSONs
    final proj = sanitizeFileName(params.project);
    final locPart = params.location != null ? '_${sanitizeFileName(params.location!)}' : '';
    final zipName = '$proj${locPart}_${DateTime.now().millisecondsSinceEpoch}.zip';
    final zipPath = p.join(Directory.systemTemp.path, zipName);

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    // Notify the main isolate of the temp ZIP path for potential cancellation cleanup
    sendPort.send({'type': 'started', 'zipPath': zipPath, 'total': total});

    for (var i = 0; i < params.photos.length; i++) {
      final photo = params.photos[i];
      final path = params.resolvedPaths[i];
      final fileInDcim = File(path);
      if (fileInDcim.existsSync()) {
        // Stream file contents instead of loading entire bytes in memory
        final archivePath = p.posix.join(photo.location, photo.fileName);
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
    sendPort.send({
      'type': 'progress',
      'current': params.photos.length + 1,
      'total': total
    });

    // Add infoproyect.txt
    final projectDataBytes = utf8.encode(params.projectDataReport);
    encoder.addArchiveFile(ArchiveFile(
        'infoproyect.txt', projectDataBytes.length, projectDataBytes));
    sendPort.send({
      'type': 'progress',
      'current': params.photos.length + 2,
      'total': total
    });

    // Add raw JSONs under data/
    final metaJson = utf8.encode(params.rawMetadataJson);
    encoder.addArchiveFile(
        ArchiveFile('data/metadata.json', metaJson.length, metaJson));
    sendPort.send({
      'type': 'progress',
      'current': params.photos.length + 3,
      'total': total
    });

    final descJson = utf8.encode(params.rawDescriptionsJson);
    encoder.addArchiveFile(
        ArchiveFile('data/descriptions.json', descJson.length, descJson));
    sendPort.send({
      'type': 'progress',
      'current': params.photos.length + 4,
      'total': total
    });

    final statusJson = utf8.encode(params.rawLocationStatusJson);
    encoder.addArchiveFile(ArchiveFile(
        'data/location_status.json', statusJson.length, statusJson));
    sendPort.send({
      'type': 'progress',
      'current': params.photos.length + 5,
      'total': total
    });

    final projectDataJson = utf8.encode(params.rawProjectDataJson);
    encoder.addArchiveFile(ArchiveFile(
        'data/project_data.json', projectDataJson.length, projectDataJson));
    sendPort.send({
      'type': 'progress',
      'current': params.photos.length + 6,
      'total': total
    });

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
