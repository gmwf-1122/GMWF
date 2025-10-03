import 'package:cloud_firestore/cloud_firestore.dart';

class Patient {
  final String id; // docId (CNIC in your case)
  final String cnic; // ✅ Explicit CNIC field
  final String name;
  final String branchId;
  final String createdBy;
  final String status; // New → PrescriptionReady → Dispensed → Completed
  final String? assignedDoctorId;
  final String? branchName;
  final Timestamp? createdAt;
  final Map<String, dynamic>? visitDetails;
  final List<Map<String, dynamic>> prescriptions;

  Patient({
    required this.id,
    required this.cnic,
    required this.name,
    required this.branchId,
    required this.createdBy,
    required this.status,
    this.assignedDoctorId,
    this.branchName,
    this.createdAt,
    this.visitDetails,
    this.prescriptions = const [],
  });

  factory Patient.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Patient(
      id: doc.id,
      cnic: d['cnic'] ?? doc.id, // ✅ fallback for old docs
      name: d['name'] ?? '',
      branchId: d['branchId'] ?? '',
      createdBy: d['createdBy'] ?? '',
      status: d['status'] ?? 'New',
      assignedDoctorId: d['assignedDoctorId'],
      branchName: d['branchName'],
      createdAt: d['createdAt'],
      visitDetails: d['visitDetails'] as Map<String, dynamic>?,
      prescriptions: List<Map<String, dynamic>>.from(d['prescriptions'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cnic': cnic, // ✅ Save CNIC at root
      'name': name,
      'branchId': branchId,
      'createdBy': createdBy,
      'status': status,
      'assignedDoctorId': assignedDoctorId,
      'branchName': branchName,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'visitDetails': visitDetails ?? {},
      'prescriptions': prescriptions,
    };
  }
}
