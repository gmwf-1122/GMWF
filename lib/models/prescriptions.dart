// lib/models/prescription.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Prescription {
  final String id;
  final String patientId;
  final String branchId;
  final String doctorId;
  final List<Map<String, dynamic>> items; // {medId, name, qty, price}
  final num total;
  final String status; // pending, ready, dispensed, completed
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  Prescription({
    required this.id,
    required this.patientId,
    required this.branchId,
    required this.doctorId,
    required this.items,
    required this.total,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory Prescription.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Prescription(
      id: doc.id,
      patientId: d['patientId'] ?? '',
      branchId: d['branchId'] ?? '',
      doctorId: d['doctorId'] ?? '',
      items: List<Map<String, dynamic>>.from(d['items'] ?? []),
      total: d['total'] ?? 0,
      status: d['status'] ?? 'pending',
      createdAt: d['createdAt'],
      updatedAt: d['updatedAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'patientId': patientId,
      'branchId': branchId,
      'doctorId': doctorId,
      'items': items,
      'total': total,
      'status': status,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
    };
  }
}
