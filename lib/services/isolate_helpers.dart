import 'dart:convert';
import 'dart:io';
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

// Helper class to return results from the photo saving isolate
class SavePhotoResult {
  final String fileName;
  final String relativePath;

  SavePhotoResult({required this.fileName, required this.relativePath});
}

/// ISOLATE: Processes and saves a photo.
Future<SavePhotoResult?> savePhotoIsolate(SavePhotoParams params) async {
  // Ensure the platform channel is initialized.
  BackgroundIsolateBinaryMessenger.ensureInitialized(params.token);

  // Initialize MediaStore within the isolate.
  if (Platform.isAndroid) {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = kAppFolder;
  }
  File? tempFile;
  try {
    final relativePathForPlugin = p.join(params.project, params.location);
    Uint8List bytes = await params.xFile.readAsBytes();

    if (params.aspect != null) {
      final i = img.decodeImage(bytes);
      if (i != null) {
        final w = i.width;
        final h = i.height;
        final cur = w / h;
        int cw = w, ch = h, x = 0, y = 0;
        if (cur > params.aspect!) {
          cw = (h * params.aspect!).round();
          x = ((w - cw) / 2).round();
        } else if (cur < params.aspect!) {
          ch = (w / params.aspect!).round();
          y = ((h - ch) / 2).round();
        }
        bytes = Uint8List.fromList(img.encodeJpg(
            img.copyCrop(i, x: x, y: y, width: cw, height: ch),
            quality: 92));
      }
    }

    String filePathToSave = params.xFile.path;
    if (params.aspect != null) {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(p.join(tempDir.path, p.basename(params.xFile.path)));
      await tempFile.writeAsBytes(bytes, flush: true);
      filePathToSave = tempFile.path;
    }

    if (Platform.isAndroid) {
      final mediaStore = MediaStore();
      final saveInfo = await mediaStore.saveFile(
        tempFilePath: filePathToSave,
        dirType: DirType.photo,
        dirName: DirName.dcim,
        relativePath: relativePathForPlugin,
      );

      if (saveInfo != null && saveInfo.isSuccessful) {
        return SavePhotoResult(
            fileName: saveInfo.name, relativePath: saveInfo.uri.path);
      } else {
        debugPrint(
            '[Camera] Save failed. Status: ${saveInfo?.saveStatus}, Error: ${saveInfo?.errorMessage}');
        return null;
      }
    }
    return null;
  } finally {
    if (tempFile != null) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
}

// Helper class to pass arguments to the zip creation isolate
class CreateZipParams {
  final List<PhotoEntry> photos;
  final String project;
  final String descriptions;
  final String dcimPath;

  CreateZipParams(
      {required this.photos,
      required this.project,
      required this.descriptions,
      required this.dcimPath});
}

/// ISOLATE: Creates a zip file from photos.
Future<String?> createZipIsolate(CreateZipParams params) async {
  final zipName =
      '${params.project}_${DateTime.now().millisecondsSinceEpoch}.zip';
  final zipPath = p.join(Directory.systemTemp.path, zipName);
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  final dcimBase = Directory(params.dcimPath);

  for (final photo in params.photos) {
    // Construct the file path manually to avoid async calls in the loop
    final fileInDcim = File(p.join(dcimBase.path, photo.relativePath));
    if (fileInDcim.existsSync()) {
      final bytes = await fileInDcim.readAsBytes();
      final archivePath = p.join(photo.location, photo.fileName);
      encoder.addArchiveFile(ArchiveFile(archivePath, bytes.length, bytes));
    }
  }

  final descBytes = utf8.encode(params.descriptions);
  encoder.addArchiveFile(
      ArchiveFile('descriptions.txt', descBytes.length, descBytes));

  encoder.close();
  return zipPath;
}

/// ISOLATE: Persists metadata to a file.
Future<void> persistMetadataIsolate(Map<String, dynamic> params) async {
  final File file = params['file'];
  final dynamic content = params['content'];
  await file.writeAsString(jsonEncode(content), flush: true);
}
