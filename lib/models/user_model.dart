import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String role; // admin, receptionist, doctor, dispenser
  final String? name;
  final String? branchId;
  final String? branchName;
  final String? doctorId; // ✅ for doctors
  final Timestamp? createdAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.role,
    this.name,
    this.branchId,
    this.branchName,
    this.doctorId,
    this.createdAt,
  });

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      uid: doc.id,
      email: d['email'] ?? '',
      role: d['role'] ?? 'user',
      name: d['name'],
      branchId: d['branchId'],
      branchName: d['branchName'],
      doctorId: d['doctorId'],
      createdAt: d['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'name': name,
      'branchId': branchId,
      'branchName': branchName,
      'doctorId': doctorId,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
