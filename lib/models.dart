class PhotoEntry {
  final String id;
  final String project;
  final String location;
  final String fileName;
  final String relativePath; // e.g. projects/{project}/{location}/IMG_*.jpg
  String description;
  final DateTime takenAt;

  PhotoEntry({
    required this.id,
    required this.project,
    required this.location,
    required this.fileName,
    required this.relativePath,
    required this.description,
    required this.takenAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'project': project,
        'location': location,
        'fileName': fileName,
        'relativePath': relativePath,
        'description': description,
        'takenAt': takenAt.toIso8601String(),
      };

  factory PhotoEntry.fromJson(Map<String, dynamic> json) => PhotoEntry(
        id: json['id'],
        project: json['project'],
        location: json['location'],
        fileName: json['fileName'],
        relativePath: json['relativePath'],
        description: json['description'] ?? '',
        takenAt: DateTime.parse(json['takenAt']),
      );
}

class LocationStatus {
  final String locationName;
  bool isCompleted;

  LocationStatus({required this.locationName, this.isCompleted = false});

  Map<String, dynamic> toJson() => {
        'locationName': locationName,
        'isCompleted': isCompleted,
      };

  factory LocationStatus.fromJson(Map<String, dynamic> json) => LocationStatus(
        locationName: json['locationName'],
        isCompleted: json['isCompleted'] ?? false,
      );
}