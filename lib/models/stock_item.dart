import 'package:cloud_firestore/cloud_firestore.dart';

class StockItem {
  final String id;
  final String name;
  double quantity;
  final String unit;
  Timestamp lastUpdated;

  StockItem({
    required this.id,
    required this.name,
    this.quantity = 0.0,
    required this.unit,
    required this.lastUpdated,
  });

  factory StockItem.fromMap(Map<String, dynamic> map, String id) {
    return StockItem(
      id: id,
      name: map['name'] ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] ?? 'kg',
      lastUpdated: map['lastUpdated'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'lastUpdated': lastUpdated,
    };
  }
}