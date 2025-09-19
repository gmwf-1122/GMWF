// lib/models/inventory_item.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryItem {
  final String id;
  final String name;
  final int stock;
  final num price;
  final Timestamp? updatedAt;

  InventoryItem({
    required this.id,
    required this.name,
    required this.stock,
    required this.price,
    this.updatedAt,
  });

  factory InventoryItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InventoryItem(
      id: doc.id,
      name: d['name'] ?? '',
      stock: (d['stock'] ?? 0) as int,
      price: d['price'] ?? 0,
      updatedAt: d['updatedAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'stock': stock,
      'price': price,
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
    };
  }
}
