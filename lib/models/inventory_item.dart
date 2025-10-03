// lib/models/inventory_item.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryItem {
  final String id; // Firestore document ID
  final String serial; // Permanent unique serial / barcode
  final String name; // Medicine name
  final String type; // Tablet, Capsule, Syrup, Injection, Drip
  final int quantity; // Quantity available
  final num price; // Price per unit
  final String expiryDate; // dd-mm-yyyy
  final String createdBy; // receptionistId
  final Timestamp createdAt; // When medicine was first added
  final Timestamp? updatedAt; // When medicine was last updated

  InventoryItem({
    required this.id,
    required this.serial,
    required this.name,
    required this.type,
    required this.quantity,
    required this.price,
    required this.expiryDate,
    required this.createdBy,
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
      type: d['type'] ?? '',
      quantity: (d['quantity'] ?? 0) as int,
      price: (d['price'] ?? 0) as num,
      expiryDate: d['expiryDate'] ?? '',
      createdBy: d['createdBy'] ?? '',
      createdAt: d['createdAt'] is Timestamp ? d['createdAt'] : Timestamp.now(),
      updatedAt: d['updatedAt'] is Timestamp ? d['updatedAt'] : null,
    );
  }

  /// Convert InventoryItem → Firestore map
  Map<String, dynamic> toMap({bool forUpdate = false}) {
    return {
      'serial': serial,
      'name': name,
      'type': type,
      'quantity': quantity,
      'price': price,
      'expiryDate': expiryDate,
      'createdBy': createdBy,
      'createdAt': forUpdate ? createdAt : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
