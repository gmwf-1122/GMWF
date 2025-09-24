// lib/models/inventory_item.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryItem {
  final String id; // Firestore document ID
  final String serial; // Permanent unique serial / barcode
  final String name; // Medicine name
  final int stock; // Quantity available
  final num price; // Price per unit
  final String? description; // Optional description (dosage, brand, etc.)
  final Timestamp createdAt; // When medicine was first added
  final Timestamp? updatedAt; // When medicine was last updated

  InventoryItem({
    required this.id,
    required this.serial,
    required this.name,
    required this.stock,
    required this.price,
    this.description,
    required this.createdAt,
    this.updatedAt,
  });

  /// Convert Firestore document → InventoryItem
  factory InventoryItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};

    return InventoryItem(
      id: doc.id,
      serial: d['serial'] ?? '',
      name: d['name'] ?? '',
      stock: (d['stock'] ?? 0) as int,
      price: (d['price'] ?? 0) as num,
      description: d['description'],
      createdAt: d['createdAt'] is Timestamp ? d['createdAt'] : Timestamp.now(),
      updatedAt: d['updatedAt'] is Timestamp ? d['updatedAt'] : null,
    );
  }

  /// Convert InventoryItem → Firestore map
  Map<String, dynamic> toMap({bool forUpdate = false}) {
    return {
      'serial': serial,
      'name': name,
      'stock': stock,
      'price': price,
      'description': description,
      'createdAt': forUpdate ? createdAt : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
