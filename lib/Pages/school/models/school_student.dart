// lib/pages/school/models/school_student.dart

class SchoolStudent {
  final String id;
  final String rollNo;
  final String name;
  final String guardianName;
  final String guardianPhone;
  final String guardianCnic;
  final String bformNo;
  final String fatherProfession;
  final String previousSchool;
  final String grade; // e.g. "Grade 1", "Nursery", "KG"
  final String section; // e.g. "A", "B"
  final String academicGroup; // e.g. "General", "Science (Computer)", "Science (Biology)", "Arts"
  final String dob;
  final String gender;
  final String status; // 'active', 'graduated', 'dropped', 'suspended'
  final String photoUrl;
  final String guardianCnicUrl;
  final String bformUrl;
  final List<Map<String, String>> additionalDocuments;
  final String branchId;
  final String admissionDate;
  final String address;
  final String biometricPin;
  final String syncStatus; // 'synced', 'pending', 'failed'
  final String lastModified;

  SchoolStudent({
    required this.id,
    required this.rollNo,
    required this.name,
    required this.guardianName,
    required this.guardianPhone,
    this.guardianCnic = '',
    this.bformNo = '',
    this.fatherProfession = '',
    this.previousSchool = '',
    required this.grade,
    this.section = 'A',
    this.academicGroup = 'General',
    this.dob = '',
    this.gender = 'Male',
    this.status = 'active',
    this.photoUrl = '',
    this.guardianCnicUrl = '',
    this.bformUrl = '',
    this.additionalDocuments = const [],
    required this.branchId,
    required this.admissionDate,
    this.address = '',
    this.biometricPin = '',
    this.syncStatus = 'synced',
    this.lastModified = '',
  });

  factory SchoolStudent.fromMap(String id, Map<String, dynamic> map) {
    List<Map<String, String>> docs = [];
    if (map['additionalDocuments'] is List) {
      for (final item in map['additionalDocuments']) {
        if (item is Map) {
          docs.add({
            'name': item['name']?.toString() ?? 'Document',
            'url': item['url']?.toString() ?? '',
          });
        }
      }
    }

    return SchoolStudent(
      id: id,
      rollNo: map['rollNo']?.toString() ?? map['admissionNo']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      guardianName: map['guardianName']?.toString() ?? map['fatherName']?.toString() ?? '',
      guardianPhone: map['guardianPhone']?.toString() ?? map['phone']?.toString() ?? '',
      guardianCnic: map['guardianCnic']?.toString() ?? map['fatherCnic']?.toString() ?? '',
      bformNo: map['bformNo']?.toString() ?? map['bForm']?.toString() ?? '',
      fatherProfession: map['fatherProfession']?.toString() ?? map['profession']?.toString() ?? '',
      previousSchool: map['previousSchool']?.toString() ?? map['prevSchool']?.toString() ?? '',
      grade: map['grade']?.toString() ?? '1',
      section: map['section']?.toString() ?? 'A',
      academicGroup: map['academicGroup']?.toString() ?? map['stream']?.toString() ?? 'General',
      dob: map['dob']?.toString() ?? '',
      gender: map['gender']?.toString() ?? 'Male',
      status: map['status']?.toString() ?? 'active',
      photoUrl: map['photoUrl']?.toString() ?? '',
      guardianCnicUrl: map['guardianCnicUrl']?.toString() ?? '',
      bformUrl: map['bformUrl']?.toString() ?? '',
      additionalDocuments: docs,
      branchId: map['branchId']?.toString() ?? '',
      admissionDate: map['admissionDate']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      biometricPin: map['biometricPin']?.toString() ?? '',
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      lastModified: map['lastModified']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rollNo': rollNo,
      'admissionNo': rollNo,
      'name': name,
      'guardianName': guardianName,
      'fatherName': guardianName,
      'guardianPhone': guardianPhone,
      'phone': guardianPhone,
      'guardianCnic': guardianCnic,
      'fatherCnic': guardianCnic,
      'bformNo': bformNo,
      'bForm': bformNo,
      'fatherProfession': fatherProfession,
      'profession': fatherProfession,
      'previousSchool': previousSchool,
      'prevSchool': previousSchool,
      'grade': grade,
      'section': section,
      'academicGroup': academicGroup,
      'dob': dob,
      'gender': gender,
      'status': status,
      'photoUrl': photoUrl,
      'guardianCnicUrl': guardianCnicUrl,
      'bformUrl': bformUrl,
      'additionalDocuments': additionalDocuments,
      'branchId': branchId,
      'admissionDate': admissionDate,
      'address': address,
      'biometricPin': biometricPin,
      'syncStatus': syncStatus,
      'lastModified': lastModified,
    };
  }

  SchoolStudent copyWith({
    String? rollNo,
    String? name,
    String? guardianName,
    String? guardianPhone,
    String? guardianCnic,
    String? bformNo,
    String? fatherProfession,
    String? previousSchool,
    String? grade,
    String? section,
    String? academicGroup,
    String? dob,
    String? gender,
    String? status,
    String? photoUrl,
    String? guardianCnicUrl,
    String? bformUrl,
    List<Map<String, String>>? additionalDocuments,
    String? branchId,
    String? admissionDate,
    String? address,
    String? biometricPin,
  }) {
    return SchoolStudent(
      id: id,
      rollNo: rollNo ?? this.rollNo,
      name: name ?? this.name,
      guardianName: guardianName ?? this.guardianName,
      guardianPhone: guardianPhone ?? this.guardianPhone,
      guardianCnic: guardianCnic ?? this.guardianCnic,
      bformNo: bformNo ?? this.bformNo,
      fatherProfession: fatherProfession ?? this.fatherProfession,
      previousSchool: previousSchool ?? this.previousSchool,
      grade: grade ?? this.grade,
      section: section ?? this.section,
      academicGroup: academicGroup ?? this.academicGroup,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      status: status ?? this.status,
      photoUrl: photoUrl ?? this.photoUrl,
      guardianCnicUrl: guardianCnicUrl ?? this.guardianCnicUrl,
      bformUrl: bformUrl ?? this.bformUrl,
      additionalDocuments: additionalDocuments ?? this.additionalDocuments,
      branchId: branchId ?? this.branchId,
      admissionDate: admissionDate ?? this.admissionDate,
      address: address ?? this.address,
      biometricPin: biometricPin ?? this.biometricPin,
    );
  }
}
