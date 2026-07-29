// lib/pages/inventory_doc.dart
import 'package:flutter/material.dart';
import 'dispensary/dispensar/inventory.dart';

class InventoryDocPage extends StatelessWidget {
  final String branchId;
  final bool isStandalone;
  final String role; // e.g. 'doctor' or 'supervisor'

  const InventoryDocPage({
    super.key,
    required this.branchId,
    this.isStandalone = true,
    this.role = 'doctor',
  });

  @override
  Widget build(BuildContext context) {
    final isSupervisor = role.toLowerCase().contains('sup') || role.toLowerCase().contains('manager');
    return InventoryPage(
      branchId: branchId,
      isDoctor: !isSupervisor,
      isSupervisor: isSupervisor,
      isReadOnly: isSupervisor,
      isEmbedded: !isStandalone,
    );
  }
}
