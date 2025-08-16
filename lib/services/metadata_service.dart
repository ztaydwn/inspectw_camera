import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models.dart';
import 'storage_service.dart';

class MetadataService {
  final _uuid = const Uuid();
  final _storage = StorageService();
  bool _inited = false;

  // project -> list of PhotoEntry
  final Map<String, List<PhotoEntry>> _cache = {};
  // project -> set of suggestions
  final Map<String, Map<String, int>> _suggestions = {};

  Future<void> init() async {
    if (_inited) return;
    await _storage.init();
    _inited = true;
  }

  Future<List<String>> listProjects() async {
    final root = Directory('${_storage.rootPath}/projects');
    if (!await root.exists()) return [];
    return root
        .listSync()
        .whereType<Directory>()
        .map((e) => p.basename(e.path))
        .toList()
      ..sort();
  }

  Future<void> createProject(String project) async {
    await _storage.ensureProject(project);
    await _load(project);
  }

  Future<void> deleteProject(String project) async {
    final dir = Directory('${_storage.rootPath}/projects/$project');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _cache.remove(project);
    _suggestions.remove(project);
  }

  Future<List<String>> listLocations(String project) async {
    final dir = await _storage.ensureProject(project);
    return dir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.split('/').last != '') // all
        .map((e) => p.basename(e.path))
        .where((name) => name != '')
        .where((name) => name != 'projects') // sanity
        .where((name) => name != '')
        .toList()
      ..sort();
  }

  Future<void> createLocation(String project, String location) async {
    await _storage.ensureLocation(project, location);
  }

  Future<void> _load(String project) async {
    if (_cache.containsKey(project)) return;
    final f = _storage.metadataFile(project);
    if (await f.exists()) {
      final data = jsonDecode(await f.readAsString()) as List;
      _cache[project] = data.map((e) => PhotoEntry.fromJson(e)).toList();
    } else {
      _cache[project] = [];
    }
    final s = _storage.descriptionsFile(project);
    if (await s.exists()) {
      final data = jsonDecode(await s.readAsString()) as Map<String, dynamic>;
      _suggestions[project] = data.map((k, v) => MapEntry(k, v as int));
    } else {
      _suggestions[project] = {};
    }
  }

  Future<List<PhotoEntry>> listPhotos(String project,
      {String? location}) async {
    await _load(project);
    final all = _cache[project]!;
    if (location == null) return all;
    return all.where((e) => e.location == location).toList();
  }

  Future<void> addPhoto({
    required String project,
    required String location,
    required String fileName,
    required String relativePath,
    required String description,
    required DateTime takenAt,
  }) async {
    await _load(project);
    final entry = PhotoEntry(
      id: _uuid.v4(),
      project: project,
      location: location,
      fileName: fileName,
      relativePath: relativePath,
      description: description,
      takenAt: takenAt,
    );
    _cache[project]!.add(entry);
    _suggestions[project]![description] =
        (_suggestions[project]![description] ?? 0) + 1;
    await _persist(project);
  }

  Future<void> updateDescription(
      String project, String photoId, String desc) async {
    await _load(project);
    final list = _cache[project]!;
    final idx = list.indexWhere((e) => e.id == photoId);
    if (idx >= 0) {
      list[idx].description = desc;
      _suggestions[project]![desc] = (_suggestions[project]![desc] ?? 0) + 1;
      await _persist(project);
    }
  }

  Future<void> deletePhoto(String project, String photoId) async {
    await _load(project);
    final list = _cache[project]!;
    final idx = list.indexWhere((e) => e.id == photoId);
    if (idx < 0) return;
    final entry = list[idx];
    // The photo is in DCIM, not in the app's private storage
    final file =
        await _storage.dcimFile(entry.project, entry.location, entry.fileName);
    try {
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    list.removeAt(idx);
    await _persist(project);
  }

  Future<void> _persist(String project) async {
    final f = _storage.metadataFile(project);
    final content = jsonEncode(_cache[project]!);
    debugPrint('Persisting metadata to ${f.path}: $content');
    await f.writeAsString(content, flush: true);
    final s = _storage.descriptionsFile(project);
    await s.writeAsString(jsonEncode(_suggestions[project]), flush: true);
  }

  Future<List<String>> suggestions(String project, String query) async {
    await _load(project);
    final map = _suggestions[project]!;
    final q = query.toLowerCase();
    final filtered = map.keys.where((k) => k.toLowerCase().contains(q)).toList()
      ..sort((a, b) => (map[b]!).compareTo(map[a]!));
    return filtered.take(20).toList();
  }
}