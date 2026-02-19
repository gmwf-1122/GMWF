// lib/models/users_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String username;
  final String role;
  final String branchId;
  final String branchName;

  UserModel({
    required this.uid,
    required this.email,
    required this.username,
    required this.role,
    required this.branchId,
    required this.branchName,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      username: map['username'] ?? '',
      role: map['role'] ?? '',
      branchId: map['branchId'] ?? '',
      branchName: map['branchName'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'username': username,
      'role': role,
      'branchId': branchId,
      'branchName': branchName,
    };
  }
}
