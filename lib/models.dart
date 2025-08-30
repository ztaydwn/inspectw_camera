class PhotoEntry {
  final String id;
  final String project;
  String location;
  final String fileName;
  String relativePath; // e.g. projects/{project}/{location}/IMG_*.jpg
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
  String locationName;
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

enum TriState { si, no, noCorresponde }

class ProjectData {
  String establishmentName;
  String owner;
  String address;
  DateTime inspectionDate;
  String specialty;
  String designatedProfessionals;
  String accompanyingPersonnel;
  String inspectionProcessComments;
  String establishmentFunction;
  String occupiedArea;
  String floorCount;
  String risk;
  String formalSituation;
  String specialObservations;
  TriState q1;
  TriState q2;
  TriState q3;
  TriState q4;

  ProjectData({
    this.establishmentName = '',
    this.owner = '',
    this.address = '',
    required this.inspectionDate,
    this.specialty = '',
    this.designatedProfessionals = '',
    this.accompanyingPersonnel = '',
    this.inspectionProcessComments = '',
    this.establishmentFunction = '',
    this.occupiedArea = '',
    this.floorCount = '',
    this.risk = '',
    this.formalSituation = '',
    this.specialObservations = '',
    this.q1 = TriState.noCorresponde,
    this.q2 = TriState.noCorresponde,
    this.q3 = TriState.noCorresponde,
    this.q4 = TriState.noCorresponde,
  });

  Map<String, dynamic> toJson() => {
        'establishmentName': establishmentName,
        'owner': owner,
        'address': address,
        'inspectionDate': inspectionDate.toIso8601String(),
        'specialty': specialty,
        'designatedProfessionals': designatedProfessionals,
        'accompanyingPersonnel': accompanyingPersonnel,
        'inspectionProcessComments': inspectionProcessComments,
        'establishmentFunction': establishmentFunction,
        'occupiedArea': occupiedArea,
        'floorCount': floorCount,
        'risk': risk,
        'formalSituation': formalSituation,
        'specialObservations': specialObservations,
        'q1': q1.index,
        'q2': q2.index,
        'q3': q3.index,
        'q4': q4.index,
      };

  factory ProjectData.fromJson(Map<String, dynamic> json) => ProjectData(
        establishmentName: json['establishmentName'] ?? '',
        owner: json['owner'] ?? '',
        address: json['address'] ?? '',
        inspectionDate: DateTime.parse(json['inspectionDate']),
        specialty: json['specialty'] ?? '',
        designatedProfessionals: json['designatedProfessionals'] ?? '',
        accompanyingPersonnel: json['accompanyingPersonnel'] ?? '',
        inspectionProcessComments: json['inspectionProcessComments'] ?? '',
        establishmentFunction: json['establishmentFunction'] ?? '',
        occupiedArea: json['occupiedArea'] ?? '',
        floorCount: json['floorCount'] ?? '',
        risk: json['risk'] ?? '',
        formalSituation: json['formalSituation'] ?? '',
        specialObservations: json['specialObservations'] ?? '',
        q1: TriState.values[json['q1'] ?? 2],
        q2: TriState.values[json['q2'] ?? 2],
        q3: TriState.values[json['q3'] ?? 2],
        q4: TriState.values[json['q4'] ?? 2],
      );
}