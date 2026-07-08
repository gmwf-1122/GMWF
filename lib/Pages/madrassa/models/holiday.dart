import 'package:cloud_firestore/cloud_firestore.dart';

class Holiday {
  final String id; // Firestore doc id
  final DateTime date;
  final String name;

  Holiday({required this.id, required this.date, required this.name});

  factory Holiday.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Holiday(
      id: doc.id,
      date: (data['date'] as Timestamp).toDate(),
      name: data['name'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'name': name,
    };
  }
}
