import 'package:cloud_firestore/cloud_firestore.dart';

class Patient {
  final String id; // Firestore doc ID (usually CNIC)
  final String cnic;
  final String name;
  final String branchId;
  final String createdBy;
  final String status; // waiting → PrescriptionReady → Dispensed → Completed
  final String? visitType; // ✅ NEW: Zakat / Non-Zakat
  final String? assignedDoctorId;
  final String? branchName;
  final Timestamp? createdAt;
  final String? phone;
  final String? gender;
  final String? bloodGroup;
  final Map<String, dynamic>? visitDetails;
  final List<Map<String, dynamic>> prescriptions;

  Patient({
    required this.id,
    required this.cnic,
    required this.name,
    required this.branchId,
    required this.createdBy,
    required this.status,
    this.visitType,
    this.assignedDoctorId,
    this.branchName,
    this.createdAt,
    this.phone,
    this.gender,
    this.bloodGroup,
    this.visitDetails,
    this.prescriptions = const [],
  });

  /// ✅ Create Patient instance from Firestore
  factory Patient.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};

    return Patient(
      id: doc.id,
      cnic: d['cnic'] ?? doc.id,
      name: d['name'] ?? '',
      branchId: d['branchId'] ?? '',
      createdBy: d['createdBy'] ?? '',
      status: d['status'] ?? 'waiting',
      visitType: d['visitType'], // ✅ Zakat / Non-Zakat
      assignedDoctorId: d['assignedDoctorId'],
      branchName: d['branchName'],
      createdAt: d['createdAt'],
      phone: d['phone'],
      gender: d['gender'],
      bloodGroup: d['bloodGroup'],
      visitDetails: d['visitDetails'] != null
          ? Map<String, dynamic>.from(d['visitDetails'])
          : {},
      prescriptions: d['prescriptions'] != null
          ? List<Map<String, dynamic>>.from(d['prescriptions'])
          : [],
    );
  }

  /// ✅ Convert Patient to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cnic': cnic,
      'name': name,
      'branchId': branchId,
      'createdBy': createdBy,
      'status': status,
      'visitType': visitType, // ✅ Included
      'assignedDoctorId': assignedDoctorId,
      'branchName': branchName,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'phone': phone,
      'gender': gender,
      'bloodGroup': bloodGroup,
      'visitDetails': visitDetails ?? {},
      'prescriptions': prescriptions,
    };
  }

  /// ✅ Add new visit to the patient record
  Map<String, dynamic> addVisit({
    required String serial,
    required String status, // waiting → PrescriptionReady → Completed
    required String visitType, // Zakat / Non-Zakat
    required String bp,
    required String temp,
    required String tempUnit,
    required String bsr,
    required String weight,
    required String createdBy,
  }) {
    final updatedVisits = Map<String, dynamic>.from(visitDetails ?? {});
    updatedVisits[serial] = {
      "status": status,
      "visitType": visitType,
      "bp": bp,
      "temp": temp,
      "tempUnit": tempUnit,
      "bsr": bsr,
      "weight": weight,
      "createdAt": FieldValue.serverTimestamp(),
      "createdBy": createdBy,
    };

    return {
      ...toMap(),
      "visitDetails": updatedVisits,
      "lastVisit": {
        "serial": serial,
        "status": status,
        "visitType": visitType,
        "createdAt": FieldValue.serverTimestamp(),
      },
      "status": status,
      "visitType": visitType,
    };
  }
}
