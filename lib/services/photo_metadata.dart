import 'dart:io';
import 'dart:convert';

class PhotoMetadata {
  final String path;
  final String description;

  PhotoMetadata({required this.path, required this.description});

  /// Intenta construir el objeto desde una ruta de imagen
  static Future<PhotoMetadata> fromImageFile(String imagePath) async {
    final jsonPath = imagePath.replaceAll(RegExp(r'\.jpe?g$'), '.json');
    String desc = '';
    if (await File(jsonPath).exists()) {
      try {
        final jsonString = await File(jsonPath).readAsString();
        final jsonMap = json.decode(jsonString);
        desc = jsonMap['description'] ?? '';
      } catch (_) {
        desc = '';
      }
    }
    return PhotoMetadata(path: imagePath, description: desc);
  }
}
