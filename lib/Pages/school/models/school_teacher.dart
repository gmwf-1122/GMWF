// lib/pages/school/models/school_teacher.dart

class SchoolTeacher {
  final String id;
  final String employeeId;
  final String name;
  final String email;
  final String phone;
  final String cnic;
  final String degree; // e.g. "M.Sc Mathematics", "B.Ed", "M.A English", "Ph.D"
  final String qualification;
  final String designation; // e.g. "Senior Teacher", "Head of Department", "Class Incharge"
  final String department; // e.g. "Science & IT", "Mathematics", "Languages", "Social Studies", "Primary"
  final List<String> assignedGrades; // e.g. ["Grade 1", "Grade 2"]
  final List<String> subjects; // e.g. ["Mathematics", "Computer Science", "Biology"]
  final String homeroomGrade; // e.g. "9th"
  final String homeroomSection; // e.g. "A"
  final String salaryGrade; // e.g. "BPS-16", "Grade A"
  final String status; // 'active', 'on leave', 'inactive', 'revoked'
  final String branchId;
  final String photoUrl;
  final String cnicUrl;
  final List<Map<String, String>> additionalDocuments;
  final String joiningDate;
  final String syncStatus; // 'synced', 'pending', 'failed'
  final String lastModified;

  SchoolTeacher({
    required this.id,
    required this.employeeId,
    required this.name,
    this.email = '',
    required this.phone,
    this.cnic = '',
    this.degree = '',
    this.qualification = '',
    this.designation = 'Teacher',
    this.department = 'Science & IT',
    this.assignedGrades = const [],
    this.subjects = const [],
    this.homeroomGrade = '',
    this.homeroomSection = '',
    this.salaryGrade = '',
    this.status = 'active',
    required this.branchId,
    this.photoUrl = '',
    this.cnicUrl = '',
    this.additionalDocuments = const [],
    this.joiningDate = '',
    this.syncStatus = 'synced',
    this.lastModified = '',
  });

  bool get isHomeroom => homeroomGrade.trim().isNotEmpty;
  String get homeroomClass => isHomeroom ? '$homeroomGrade - ${homeroomSection.isNotEmpty ? homeroomSection : "A"}' : 'Unassigned';

  factory SchoolTeacher.fromMap(String id, Map<String, dynamic> map) {
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

    return SchoolTeacher(
      id: id,
      employeeId: map['employeeId']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      email: map['email']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      cnic: map['cnic']?.toString() ?? '',
      degree: map['degree']?.toString() ?? '',
      qualification: map['qualification']?.toString() ?? '',
      designation: map['designation']?.toString() ?? 'Teacher',
      department: map['department']?.toString() ?? 'Science & IT',
      assignedGrades: (map['assignedGrades'] as List?)?.map((e) => e.toString()).toList() ?? [],
      subjects: (map['subjects'] as List?)?.map((e) => e.toString()).toList() ?? [],
      homeroomGrade: map['homeroomGrade']?.toString() ?? '',
      homeroomSection: map['homeroomSection']?.toString() ?? '',
      salaryGrade: map['salaryGrade']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      branchId: map['branchId']?.toString() ?? '',
      photoUrl: map['photoUrl']?.toString() ?? '',
      cnicUrl: map['cnicUrl']?.toString() ?? '',
      additionalDocuments: docs,
      joiningDate: map['joiningDate']?.toString() ?? '',
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      lastModified: map['lastModified']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'name': name,
      'email': email,
      'phone': phone,
      'cnic': cnic,
      'degree': degree,
      'qualification': qualification,
      'designation': designation,
      'department': department,
      'assignedGrades': assignedGrades,
      'subjects': subjects,
      'homeroomGrade': homeroomGrade,
      'homeroomSection': homeroomSection,
      'salaryGrade': salaryGrade,
      'status': status,
      'branchId': branchId,
      'photoUrl': photoUrl,
      'cnicUrl': cnicUrl,
      'additionalDocuments': additionalDocuments,
      'joiningDate': joiningDate,
      'syncStatus': syncStatus,
      'lastModified': lastModified,
    };
  }

  SchoolTeacher copyWith({
    String? employeeId,
    String? name,
    String? email,
    String? phone,
    String? cnic,
    String? degree,
    String? qualification,
    String? designation,
    String? department,
    List<String>? assignedGrades,
    List<String>? subjects,
    String? homeroomGrade,
    String? homeroomSection,
    String? salaryGrade,
    String? status,
    String? branchId,
    String? photoUrl,
    String? cnicUrl,
    List<Map<String, String>>? additionalDocuments,
    String? joiningDate,
  }) {
    return SchoolTeacher(
      id: id,
      employeeId: employeeId ?? this.employeeId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      cnic: cnic ?? this.cnic,
      degree: degree ?? this.degree,
      qualification: qualification ?? this.qualification,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      assignedGrades: assignedGrades ?? this.assignedGrades,
      subjects: subjects ?? this.subjects,
      homeroomGrade: homeroomGrade ?? this.homeroomGrade,
      homeroomSection: homeroomSection ?? this.homeroomSection,
      salaryGrade: salaryGrade ?? this.salaryGrade,
      status: status ?? this.status,
      branchId: branchId ?? this.branchId,
      photoUrl: photoUrl ?? this.photoUrl,
      cnicUrl: cnicUrl ?? this.cnicUrl,
      additionalDocuments: additionalDocuments ?? this.additionalDocuments,
      joiningDate: joiningDate ?? this.joiningDate,
    );
  }
}
