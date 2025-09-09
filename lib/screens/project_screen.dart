// lib/screens/project_screen.dart — v7 (performance refactor)
import 'dart:io';
import 'dart:isolate';
import 'dart:async';
// import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

import '../services/isolate_helpers.dart';
import '../services/storage_service.dart';
import '../services/metadata_service.dart';
import '../services/upload_service.dart';
import '../models.dart';
import 'gallery_screen.dart';
import 'camera_screen.dart';
import '../constants.dart';
import 'location_checklist_screen.dart';
import 'search_explorer_screen.dart';
import 'project_data_screen.dart';
import '../checklist_templates.dart';
import 'checklist_screen.dart';
import 'import_review_screen.dart';

/// Isolate function to find all existing photo files for a project.
Future<List<String>> _resolveFilePathsIsolate(Map<String, dynamic> args) async {
  final token = args['token'] as RootIsolateToken;
  final photos = args['photos'] as List<PhotoEntry>;

  // Initialize platform channel communication for this isolate.
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final storage = StorageService();
  // StorageService uses a singleton pattern, init() is safe to call.
  await storage.init();
  final paths = <String>[];
  for (final photo in photos) {
    final f = await storage.resolvePhotoFile(photo);
    if (f != null && await f.exists()) {
      paths.add(f.path);
    }
  }
  return paths;
}

class _LocationInfo {
  final String name;
  final bool isChecklist;
  final bool isCompleted;

  _LocationInfo({
    required this.name,
    required this.isChecklist,
    required this.isCompleted,
  });
}

class ProjectScreen extends StatefulWidget {
  final String project;
  const ProjectScreen({super.key, required this.project});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late final StorageService storage;
  late final MetadataService meta;
  bool _isExporting = false;
  bool _isUploading = false;
  bool _isCopyingFiles = false;
  double _zipProgress = 0.0; // 0..1
  int _zipCurrent = 0;
  int _zipTotal = 0;
  Isolate? _zipIsolate;
  ReceivePort? _zipReceivePort;
  Future<List<_LocationInfo>>? _locationsFuture;
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    storage = StorageService();
    // meta is initialized in didChangeDependencies, which is called after initState
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    meta = context.read<MetadataService>();
    // Initialize the future here where meta is available
    _locationsFuture ??= _getLocationData();
  }

  void _refreshLocations() {
    setState(() {
      _locationsFuture = _getLocationData();
    });
  }

  Future<List<_LocationInfo>> _getLocationData() async {
    final statuses = await meta.getLocationStatuses(widget.project);
    final List<_LocationInfo> locationInfoList = [];
    for (final status in statuses) {
      final isChecklist = await storage
          .checklistFile(widget.project, status.locationName)
          .exists();
      locationInfoList.add(_LocationInfo(
        name: status.locationName,
        isChecklist: isChecklist,
        isCompleted: status.isCompleted,
      ));
    }
    return locationInfoList;
  }

  /// FUNCION PARA COPIAR ARCHIVOS DE DATOS

  Future<void> _copyDataFiles() async {
    if (_isCopyingFiles) return;
    setState(() => _isCopyingFiles = true);

    try {
      // 1. Generar el contenido del reporte de texto.
      final report = await meta.generateProjectReport(widget.project);

      // 2. Llamar al método de exportación simplificado.
      final savedFile = await storage.exportReportToDownloads(
        project: widget.project,
        reportContent: report,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archivo $savedFile copiado a Descargas')),
        );
      }
    } catch (e) {
      debugPrint('Error al copiar archivos de datos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al copiar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCopyingFiles = false);
      }
    }
  }

  Future<void> _addLocation() async {
    final template = await showDialog<ChecklistTemplate?>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Seleccionar tipo de ubicación'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Ubicación Vacía (sin checklist)'),
            ),
            ...kChecklistTemplates.map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, t),
                  child: Text(t.name),
                )),
          ],
        );
      },
    );
    if (!mounted) return;

    final c = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template == null
            ? 'Nueva Ubicación'
            : 'Nombre para checklist: ${template.name}'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Crear'))
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await meta.createLocation(widget.project, name);

      if (template != null) {
        // This is a checklist-based location.
        await meta.createChecklistFromTemplate(widget.project, name, template);
        if (mounted) {
          // Navigate to the new checklist screen
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChecklistScreen(
                project: widget.project,
                location: name,
              ),
            ),
          );
        }
      }
      _refreshLocations();
    }
  }

  Future<void> _renameLocation(String oldName) async {
    final c = TextEditingController(text: oldName);
    final newName = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar ubicación'),
        content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Nuevo nombre')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Renombrar'))
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != oldName) {
      try {
        await meta.renameLocation(widget.project, oldName, newName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al renombrar: $e')),
          );
        }
      }
      _refreshLocations();
    }
  }

  Future<void> _showLocationOptions(String location) async {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renombrar'),
              onTap: () {
                Navigator.pop(context);
                _renameLocation(location);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('Eliminar', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirmar Eliminación'),
                    content: Text(
                        '¿Estás seguro de que quieres eliminar la ubicación "$location"?\n\nTodas las fotos y datos asociados se borrarán permanentemente. Esta acción no se puede deshacer.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  try {
                    await meta.deleteLocation(widget.project, location);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                            content: Text('Ubicación "$location" eliminada.')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error al eliminar: $e')),
                      );
                    }
                  }
                  _refreshLocations();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<String?> _buildZipForProject() async {
    setState(() {
      _isExporting = true;
      _zipProgress = 0.0;
      _zipCurrent = 0;
      _zipTotal = 0;
    });
    try {
      final allPhotos = await meta.listPhotos(widget.project);
      if (allPhotos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No photo metadata found for this project.')));
        }
        return null;
      }

      final photosWithPaths = <PhotoEntry>[];
      final resolvedPaths = <String>[];
      for (final photo in allPhotos) {
        final f = await storage.resolvePhotoFile(photo);
        if (f != null && await f.exists()) {
          photosWithPaths.add(photo);
          resolvedPaths.add(f.path);
        }
      }

      if (photosWithPaths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No photo files found for this project.')));
        }
        return null;
      }

      // Generate both reports
      final descriptions =
          await meta.generatePhotoDescriptionsReport(widget.project);
      final projectDataReport =
          await meta.generateProjectDataReport(widget.project);

      if (Platform.isAndroid) {
        PermissionStatus permStatus;
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          permStatus = await Permission.photos.request();
        } else {
          permStatus = await Permission.storage.request();
        }

        if (!permStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Storage permission denied.')));
          }
          return null;
        }
      }

      final params = CreateZipParams(
        photos: photosWithPaths,
        project: widget.project,
        descriptions: descriptions,
        projectDataReport: projectDataReport,
        resolvedPaths: resolvedPaths,
      );
      // Initialize progress
      setState(() {
        _zipTotal = photosWithPaths.length + 2;
        _zipCurrent = 0;
        _zipProgress = 0.0;
      });

      final recv = ReceivePort();
      final completer = Completer<String?>();
      _zipReceivePort = recv;

      recv.listen((msg) {
        if (msg is Map) {
          final type = msg['type'];
          if (type == 'progress') {
            final current = (msg['current'] as int?) ?? 0;
            final total = (msg['total'] as int?) ?? _zipTotal;
            if (mounted) {
              setState(() {
                _zipCurrent = current;
                _zipTotal = total;
                _zipProgress = total > 0 ? current / total : 0.0;
              });
            }
          } else if (type == 'done') {
            completer.complete(msg['zipPath'] as String?);
          } else if (type == 'error') {
            completer.complete(null);
          }
        }
      });

      _zipIsolate = await Isolate.spawn(
        createZipWithProgressIsolate,
        {
          'sendPort': recv.sendPort,
          'params': params,
        },
        errorsAreFatal: true,
      );

      final zipPath = await completer.future;

      // Cleanup
      try {
        _zipReceivePort?.close();
      } catch (_) {}
      _zipReceivePort = null;
      _zipIsolate?.kill(priority: Isolate.immediate);
      _zipIsolate = null;

      if (zipPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to create ZIP file.')));
        }
        return null;
      }

      debugPrint(
          '[ZIP] Created $zipPath with ${photosWithPaths.length} entries.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('ZIP created with ${photosWithPaths.length} photo(s).')));
      }
      return zipPath;
    } catch (e, s) {
      debugPrint('[ZIP] Error building ZIP: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error creating ZIP: $e')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportProject() async {
    final zipPath = await _buildZipForProject();
    if (zipPath == null) return;

    try {
      await MediaStore.ensureInitialized();
      MediaStore.appFolder = kAppFolder;
      await MediaStore().saveFile(
        tempFilePath: zipPath,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath: p.join(kAppFolder, widget.project),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ZIP saved to Download/$kAppFolder')));
      }
    } catch (e) {
      debugPrint('[ZIP] Error saving to MediaStore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save ZIP to Download: $e')));
      }
    } finally {
      try {
        final tmpZip = File(zipPath);
        if (await tmpZip.exists()) {
          await tmpZip.delete();
        } else {
          debugPrint('[ZIP] Temp not found (already moved/cleaned): $zipPath');
        }
      } catch (e) {
        debugPrint('[ZIP] Failed to delete temp file: $e');
      }
    }
  }

  Future<void> _uploadToDrive() async {
    setState(() => _isUploading = true);
    try {
      debugPrint('📤 Iniciando subida al Drive...');
      final project = widget.project;

      // 1. Get photo metadata
      final allPhotos = await meta.listPhotos(project);
      if (allPhotos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No hay fotos en este proyecto para subir.')));
        }
        return;
      }

      // 2. Resolve photo file paths in a separate isolate to avoid UI jank
      final token = RootIsolateToken.instance;
      if (token == null) {
        debugPrint('Could not get RootIsolateToken');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Error interno al iniciar subida.')));
        }
        return;
      }

      final imagePaths = await compute(
          _resolveFilePathsIsolate, {'token': token, 'photos': allPhotos});
      final imageFiles = imagePaths.map((path) => File(path)).toList();

      if (imageFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No se encontraron los archivos de las fotos.')));
        }
        return;
      }

      // 3. Get metadata.json file
      final jsonFile = storage.metadataFile(project);
      if (!await jsonFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontró metadata.json')),
          );
        }
        return;
      }

      if (!mounted) return;

      await uploadFilesToBackend(
        imageFiles: imageFiles,
        jsonFile: jsonFile,
        projectName: project,
        context: context,
      );
    } catch (e, s) {
      debugPrint('Error en _uploadToDrive: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _importPhotos() async {
    // 1. Get list of locations
    final locations = await meta.listLocations(widget.project);
    if (!mounted) return;
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No hay ubicaciones en este proyecto. Por favor, crea una primero.')),
      );
      return;
    }

    // 2. Ask user to select a location
    final selectedLocation = await showDialog<String>(
      context: context,
      builder: (context) => _LocationSelectionDialog(locations: locations),
    );

    if (selectedLocation == null) return; // User cancelled

    // 3. Pick images
    final imagePicker = ImagePicker();
    final List<XFile> pickedFiles = await imagePicker.pickMultiImage();

    if (pickedFiles.isEmpty) return;
    if (!mounted) return;

    // 4. Navigate to the review screen
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImportReviewScreen(
          files: pickedFiles,
          project: widget.project,
          location: selectedLocation,
        ),
      ),
    );
    _refreshLocations(); // Refresh in case new photos affect completion status
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Proyecto: ${widget.project}',
            style: const TextStyle(fontSize: 18.0)),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.view_module),
            tooltip: 'Cambiar vista',
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_check),
            tooltip: 'Checklist de Ubicaciones',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      LocationChecklistScreen(project: widget.project),
                ),
              ).then((_) => _refreshLocations());
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar en el proyecto',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SearchExplorerScreen(project: widget.project),
                ),
              );
            },
          ),
          // Agrupamos acciones en un PopupMenuButton para limpiar la AppBar
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'import':
                  _importPhotos();
                  break;
                case 'export':
                  _exportProject();
                  break;
                case 'upload':
                  _uploadToDrive();
                  break;
                case 'copy':
                  _copyDataFiles();
                  break;
                case 'project_data':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProjectDataScreen(project: widget.project),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Importar Fotos'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Exportar ZIP'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'upload',
                child: ListTile(
                  leading: Icon(Icons.cloud_upload_outlined),
                  title: Text('Subir a Drive'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('Copiar datos'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'project_data',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Datos del Proyecto'),
                ),
              ),
            ],
            // Mostramos un indicador de progreso si alguna acción está en curso
            icon: (_isExporting || _isUploading || _isCopyingFiles)
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: FutureBuilder<List<_LocationInfo>>(
        future: _locationsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Error al cargar ubicaciones: ${snap.error}'),
              ),
            );
          }
          final locations = snap.data ?? [];

          if (locations.isEmpty) {
            // UI mejorada para cuando no hay ubicaciones
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 80,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay ubicaciones',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Crea una nueva ubicación para empezar a añadir fotos.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          Widget buildGridView() {
            return GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // 2 tarjetas por fila
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
                childAspectRatio: 1.2, // Ajusta la proporción de las tarjetas
              ),
              itemCount: locations.length,
              itemBuilder: (_, i) {
                final locInfo = locations[i];
                final loc = locInfo.name;
                final isChecklist = locInfo.isChecklist;
                final isCompleted = locInfo.isCompleted;

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      if (isChecklist) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChecklistScreen(
                              project: widget.project,
                              location: loc,
                            ),
                          ),
                        );
                      } else {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GalleryScreen(
                                project: widget.project, location: loc),
                          ),
                        );
                      }
                      _refreshLocations();
                    },
                    onLongPress: () => _showLocationOptions(loc),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: Icon(isChecklist
                              ? Icons.checklist_rtl
                              : Icons.place_outlined),
                          title: Text(
                            loc,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: isCompleted
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green)
                              : null,
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: FilledButton.tonal(
                            onPressed: () {
                              if (isChecklist) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChecklistScreen(
                                      project: widget.project,
                                      location: loc,
                                    ),
                                  ),
                                ).then((_) => _refreshLocations());
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CameraScreen(
                                        project: widget.project,
                                        location: loc,
                                        stayAfterCapture: true),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(isChecklist
                                    ? Icons.playlist_add_check_circle_outlined
                                    : Icons.camera_alt_outlined),
                                const SizedBox(width: 8),
                                Text(isChecklist
                                    ? 'Ver Checklist'
                                    : 'Añadir Foto'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            );
          }

          Widget buildListView() {
            return ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: locations.length,
              itemBuilder: (_, i) {
                final locInfo = locations[i];
                final loc = locInfo.name;
                final isChecklist = locInfo.isChecklist;
                final isCompleted = locInfo.isCompleted;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ListTile(
                    leading: Icon(isChecklist
                        ? Icons.checklist_rtl
                        : Icons.place_outlined),
                    title: Text(loc),
                    subtitle:
                        Text(isChecklist ? 'Checklist' : 'Galería de fotos'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCompleted)
                          const Icon(Icons.check_circle, color: Colors.green),
                        IconButton(
                          icon: Icon(isChecklist
                              ? Icons.playlist_add_check_circle_outlined
                              : Icons.camera_alt_outlined),
                          tooltip:
                              isChecklist ? 'Ver Checklist' : 'Añadir Foto',
                          onPressed: () {
                            if (isChecklist) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChecklistScreen(
                                    project: widget.project,
                                    location: loc,
                                  ),
                                ),
                              ).then((_) => _refreshLocations());
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CameraScreen(
                                      project: widget.project,
                                      location: loc,
                                      stayAfterCapture: true),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () async {
                      if (isChecklist) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChecklistScreen(
                              project: widget.project,
                              location: loc,
                            ),
                          ),
                        );
                      } else {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GalleryScreen(
                                project: widget.project, location: loc),
                          ),
                        );
                      }
                      _refreshLocations();
                    },
                    onLongPress: () => _showLocationOptions(loc),
                  ),
                );
              },
            );
          }

          return _isGridView ? buildGridView() : buildListView();
        },
      ),
      bottomNavigationBar: _isExporting
          ? Material(
              elevation: 8,
              color: Colors.white,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Generando ZIP...',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _zipTotal > 0 ? _zipProgress : null,
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(_zipTotal > 0
                        ? '${(_zipProgress * 100).clamp(0, 100).toStringAsFixed(0)}%  •  $_zipCurrent/$_zipTotal'
                        : '...'),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: _addLocation,
        tooltip: 'Nueva ubicación',
        child: const Icon(Icons.add_location_alt_outlined),
      ),
    );
  }
}

// A dedicated stateful widget for the location selection dialog.
class _LocationSelectionDialog extends StatefulWidget {
  final List<String> locations;
  const _LocationSelectionDialog({required this.locations});

  @override
  State<_LocationSelectionDialog> createState() =>
      _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  String? _selectedLocation;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar Ubicación'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          itemCount: widget.locations.length,
          shrinkWrap: true,
          itemBuilder: (context, index) {
            final loc = widget.locations[index];
            return RadioListTile<String>(
              title: Text(loc),
              value: loc,
              // ignore: deprecated_member_use
              groupValue: _selectedLocation,
              // ignore: deprecated_member_use
              onChanged: (String? value) {
                setState(() {
                  _selectedLocation = value;
                });
              },
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancelar'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        FilledButton(
          onPressed: _selectedLocation == null
              ? null // Disable button if nothing is selected
              : () {
                  Navigator.of(context).pop(_selectedLocation);
                },
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
