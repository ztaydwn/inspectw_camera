// upload_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

Future<void> uploadFilesToBackend({
  required List<File> imageFiles,
  required File jsonFile,
  required String projectName,
  required BuildContext context,
}) async {
  try {
    final uri = Uri.parse(
        'http://10.0.2.2:8000/upload'); // Cambiar a IP real si usas dispositivo físico

    final request = http.MultipartRequest('POST', uri)
      ..fields['project'] = projectName;

    final stopwatch = Stopwatch()..start();

    // Mostrar progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Subiendo archivos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Esto puede tardar unos segundos...'),
          ],
        ),
      ),
    );

    // Adjuntar imágenes
    for (final image in imageFiles) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          image.path,
          filename: p.basename(image.path),
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    // Adjuntar metadata.json
    request.files.add(
      await http.MultipartFile.fromPath(
        'files',
        jsonFile.path,
        filename: p.basename(jsonFile.path),
        contentType: MediaType('application', 'json'),
      ),
    );

    final totalFiles = imageFiles.length + 1;
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    stopwatch.stop();
    if (context.mounted) {
      Navigator.of(context).pop(); // Cerrar diálogo de carga

      if (response.statusCode == 200) {
        final seconds = stopwatch.elapsed.inSeconds;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '✅ Subida completada: $totalFiles archivos en ${seconds}s')),
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error al subir: ${response.statusCode}')),
          );
        }
      }
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop(); // Cerrar diálogo si hay error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }
}
