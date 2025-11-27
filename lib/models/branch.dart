// lib/models/branch.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Branch {
  final String id;
  final String name;
  final String? address;
  final Timestamp? createdAt;

  Branch({
    required this.id,
    required this.name,
    this.address,
    this.createdAt,
  });

  factory Branch.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Branch(
      id: doc.id,
      name: d['name'] ?? '',
      address: d['address'],
      createdAt: d['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
