// lib/pages/request.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// ---------------------------------------------------------------
///  UTILS
/// ---------------------------------------------------------------
class RequestUtils {
  static String getTitle(String type, String patient) {
    return switch (type) {
      'dispense' => 'Patient: $patient',
      'add_stock' => 'Stock Request',
      'change_prescription' => 'Prescription Change',
      'token_reversal' => 'Token Reversal',
      'edit_medicine' => 'Edit Medicine Request',
      _ => 'Request',
    };
  }

  static Color getBadgeColor(String type) => switch (type) {
        'dispense' => Colors.blue[100]!,
        'add_stock' => Colors.green[100]!,
        'change_prescription' => Colors.orange[100]!,
        'token_reversal' => Colors.red[100]!,
        'edit_medicine' => Colors.purple[100]!,
        _ => Colors.grey[300]!,
      };

  static Color getTextColor(String type) => switch (type) {
        'dispense' => Colors.blue[800]!,
        'add_stock' => Colors.green[800]!,
        'change_prescription' => Colors.orange[800]!,
        'token_reversal' => Colors.red[800]!,
        'edit_medicine' => Colors.purple[800]!,
        _ => Colors.grey[800]!,
      };
}

/// ---------------------------------------------------------------
///  MAIN PAGE
/// ---------------------------------------------------------------
class RequestPage extends StatefulWidget {
  final String branchId;
  const RequestPage({super.key, required this.branchId});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[700],
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Text('Edit Requests', style: TextStyle(fontSize: 18)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Pending', icon: Icon(Icons.pending_actions)),
            Tab(text: 'Approved', icon: Icon(Icons.check_circle)),
            Tab(text: 'Rejected', icon: Icon(Icons.cancel)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _StableRequestTab(
            branchId: widget.branchId,
            status: 'pending',
            title: 'Pending',
            emptyText: 'No Pending Edit Requests',
            icon: Icons.pending_actions_outlined,
            showTable: true,
          ),
          _StableRequestTab(
            branchId: widget.branchId,
            status: 'approved',
            title: 'Approved',
            emptyText: 'No Approved Edit Requests',
            icon: Icons.check_circle_outline,
            color: Colors.green[700]!,
            showTable: false,
          ),
          _StableRequestTab(
            branchId: widget.branchId,
            status: 'rejected',
            title: 'Rejected',
            emptyText: 'No Rejected Edit Requests',
            icon: Icons.cancel_outlined,
            color: Colors.red[700]!,
            showTable: false,
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------
///  STABLE TAB – NO FLICKER, NO GHOSTS
/// ---------------------------------------------------------------
class _StableRequestTab extends StatefulWidget {
  final String branchId;
  final String status;
  final String title;
  final String emptyText;
  final IconData icon;
  final Color? color;
  final bool showTable;

  const _StableRequestTab({
    required this.branchId,
    required this.status,
    required this.title,
    required this.emptyText,
    required this.icon,
    this.color,
    required this.showTable,
  });

  @override
  State<_StableRequestTab> createState() => _StableRequestTabState();
}

class _StableRequestTabState extends State<_StableRequestTab>
    with AutomaticKeepAliveClientMixin {
  // Keep tab alive – prevents rebuild on tab switch
  @override
  bool get wantKeepAlive => true;

  late final Stream<QuerySnapshot> _stream;
  List<QueryDocumentSnapshot> _cached = [];

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .where('status', isEqualTo: widget.status)
        .orderBy('requestedAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Keep alive

    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        // ----- 1. Update cache only -----
        if (snapshot.hasData) {
          _cached = snapshot.data!.docs;
        }

        // ----- 2. Show UI based on cache -----
        if (_cached.isEmpty) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoading();
          } else {
            return _buildEmpty();
          }
        }

        return _buildList(_cached);
      },
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  color: Colors.blueGrey, strokeWidth: 2)),
          SizedBox(height: 12),
          Text('Syncing...',
              style: TextStyle(color: Colors.blueGrey, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 80, color: Colors.blueGrey[600]),
          const SizedBox(height: 16),
          Text(
            widget.emptyText,
            style: const TextStyle(
                color: Colors.blueGrey,
                fontSize: 20,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs) {
    final w = MediaQuery.of(context).size.width;
    final tableW = w - 32;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: ListView.separated(
        key: ValueKey(docs.length),
        padding: const EdgeInsets.all(16),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (c, i) {
          final req = docs[i];
          final data = req.data() as Map<String, dynamic>?;
          if (data == null) return const SizedBox();

          final requestType = data['requestType']?.toString() ?? 'unknown';
          final items =
              (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final patientName = data['patientName']?.toString() ?? '—';
          final createdBy = data['createdBy']?.toString() ?? '—';
          final ts = data['requestedAt'] as Timestamp?;

          return Card(
            color: Colors.grey[50],
            elevation: widget.status == 'pending' ? 2 : 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          RequestUtils.getTitle(requestType, patientName),
                          style: TextStyle(
                            color: widget.color ?? Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: RequestUtils.getBadgeColor(requestType),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          requestType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: RequestUtils.getTextColor(requestType),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(ts),
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Requested by: $createdBy',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),

                  // Items (Table or Compact)
                  if (widget.showTable && items.isNotEmpty)
                    _buildTable(items, tableW)
                  else if (items.isNotEmpty)
                    _buildCompactItems(items),

                  const SizedBox(height: 12),

                  // Actions or Status
                  if (widget.status == 'pending')
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red[700]),
                          onPressed: () => _updateStatus(
                              context, req.id, 'rejected', requestType),
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              foregroundColor: Colors.white),
                          onPressed: () => _updateStatus(
                              context, req.id, 'approved', requestType,
                              data: data),
                          child: const Text('Approve'),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            (widget.color ?? Colors.blueGrey).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.status.toUpperCase(),
                        style: TextStyle(
                            color: widget.color ?? Colors.blueGrey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> items, double tableW) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: tableW - 32),
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(Colors.blueGrey[50]),
            dataRowColor: MaterialStateProperty.all(Colors.white),
            columnSpacing: 12,
            columns: const [
              DataColumn(
                  label: Text('Name',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.bold))),
              DataColumn(
                  label: Text('Type',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.bold))),
              DataColumn(
                  label: Text('Dose',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.bold))),
              DataColumn(
                  label: Text('Qty',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.bold))),
            ],
            rows: items.map((m) {
              final name = m['name']?.toString() ?? '';
              final type = m['type']?.toString() ?? '';
              final dose = m['dose']?.toString() ?? '';
              final qty = (m['quantity'] ?? 0).toString();
              return DataRow(cells: [
                DataCell(
                    Text(name, style: const TextStyle(color: Colors.black87))),
                DataCell(Row(children: [
                  _typeIcon(type),
                  const SizedBox(width: 6),
                  Text(type, style: const TextStyle(color: Colors.black54)),
                ])),
                DataCell(
                    Text(dose, style: const TextStyle(color: Colors.black54))),
                DataCell(Text(qty,
                    style: const TextStyle(
                        color: Colors.blueGrey, fontWeight: FontWeight.bold))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactItems(List<Map<String, dynamic>> items) {
    return Column(
      children: [
        ...items.take(3).map((m) {
          final name = m['name']?.toString() ?? '';
          final type = m['type']?.toString() ?? '';
          final dose =
              m['dose']?.toString().isNotEmpty == true ? ' ${m['dose']}' : '';
          final qty = (m['quantity'] ?? 0).toString();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.medication, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('$name ($type$dose) × $qty',
                        style: const TextStyle(color: Colors.black87))),
              ],
            ),
          );
        }),
        if (items.length > 3)
          Text('+${items.length - 3} more',
              style: const TextStyle(
                  color: Colors.black54, fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _typeIcon(String? type) {
    final t = type ?? 'Others';
    return switch (t) {
      'Tablet' =>
        const Icon(FontAwesomeIcons.tablets, size: 16, color: Colors.blueGrey),
      'Capsule' =>
        const Icon(FontAwesomeIcons.capsules, size: 16, color: Colors.blueGrey),
      'Syrup' => const Icon(FontAwesomeIcons.bottleDroplet,
          size: 16, color: Colors.blueGrey),
      'Injection' =>
        const Icon(FontAwesomeIcons.syringe, size: 16, color: Colors.blueGrey),
      'Big Bottle' => const Icon(FontAwesomeIcons.prescriptionBottleAlt,
          size: 16, color: Colors.blueGrey),
      _ => const Icon(FontAwesomeIcons.pills, size: 16, color: Colors.blueGrey),
    };
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // -----------------------------------------------------------------
  // UPDATE STATUS – FORCE SYNC
  // -----------------------------------------------------------------
  Future<void> _updateStatus(
    BuildContext ctx,
    String requestId,
    String newStatus,
    String requestType, {
    Map<String, dynamic>? data,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .doc(requestId);

    try {
      await ref.update({
        'status': newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'syncTrigger':
            DateTime.now().millisecondsSinceEpoch, // INSTANT UI UPDATE
      });

      // Handle approval logic
      if (newStatus == 'approved' && data != null) {
        if (requestType == 'add_stock') {
          await _handleAddStock(data);
        } else if (requestType == 'edit_medicine') {
          await _handleEditMedicine(data);
        }
      }

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Request $newStatus'),
            backgroundColor:
                newStatus == 'approved' ? Colors.green[700] : Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'), backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  // -----------------------------------------------------------------
  // ADD STOCK (WITH BIG BOTTLE → 10 SMALL BOTTLES + WAREHOUSE SYNC)
  // -----------------------------------------------------------------
  Future<void> _handleAddStock(Map<String, dynamic> data) async {
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final branchRef =
        FirebaseFirestore.instance.collection('branches').doc(widget.branchId);

    final inventory = branchRef.collection('inventory');
    final warehouse = branchRef.collection('warehouse');

    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final name = item['name']?.toString();
      final type = item['type']?.toString();
      final dose = item['dose']?.toString();
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final expiry = item['expiryDate']?.toString();
      final isBigBottle = item['isBigBottle'] == true;

      if (name == null || type == null || qty <= 0) continue;

      final nameLower = name.toLowerCase();

      // -------------------------------
      // 1. Always add to WAREHOUSE (as-is)
      // -------------------------------
      final warehouseSnap = await warehouse
          .where('name_lower', isEqualTo: nameLower)
          .where('type', isEqualTo: type)
          .where('dose', isEqualTo: dose)
          .limit(1)
          .get();

      if (warehouseSnap.docs.isEmpty) {
        batch.set(warehouse.doc(), {
          'name': name,
          'name_lower': nameLower,
          'type': type,
          'dose': dose,
          'quantity': qty,
          'expiryDate': expiry,
          'addedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final doc = warehouseSnap.docs.first;
        final cur = (doc['quantity'] ?? 0).toInt();
        batch.update(doc.reference, {'quantity': cur + qty});
      }

      // -------------------------------
      // 2. Add to INVENTORY
      // -------------------------------
      if (isBigBottle) {
        // Convert to small bottles: "Paracetamol 500ml (Small)" → "50 ml"
        final smallName = "$name (Small)";
        final smallDoseNum =
            (int.tryParse(dose?.replaceAll(RegExp(r'\D'), '') ?? '') ?? 100) ~/
                10;
        final smallDose = "$smallDoseNum ml";

        final invSnap = await inventory
            .where('name_lower', isEqualTo: smallName.toLowerCase())
            .where('type', isEqualTo: 'Syrup')
            .where('dose', isEqualTo: smallDose)
            .limit(1)
            .get();

        final totalSmallQty = qty * 10;

        if (invSnap.docs.isEmpty) {
          batch.set(inventory.doc(), {
            'name': smallName,
            'name_lower': smallName.toLowerCase(),
            'type': 'Syrup',
            'dose': smallDose,
            'quantity': totalSmallQty,
            'expiryDate': expiry,
            'addedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final doc = invSnap.docs.first;
          final cur = (doc['quantity'] ?? 0).toInt();
          batch.update(doc.reference, {'quantity': cur + totalSmallQty});
        }
      } else {
        // Normal item → add as-is to inventory
        final invSnap = await inventory
            .where('name_lower', isEqualTo: nameLower)
            .where('type', isEqualTo: type)
            .where('dose', isEqualTo: dose)
            .limit(1)
            .get();

        if (invSnap.docs.isEmpty) {
          batch.set(inventory.doc(), {
            'name': name,
            'name_lower': nameLower,
            'type': type,
            'dose': dose,
            'quantity': qty,
            'expiryDate': expiry,
            'addedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final doc = invSnap.docs.first;
          final cur = (doc['quantity'] ?? 0).toInt();
          batch.update(doc.reference, {'quantity': cur + qty});
        }
      }
    }

    await batch.commit();
  }

  // -----------------------------------------------------------------
  // EDIT MEDICINE (QUANTITY ONLY)
  // -----------------------------------------------------------------
  Future<void> _handleEditMedicine(Map<String, dynamic> data) async {
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final inventory = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory');

    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final name = item['name']?.toString();
      final type = item['type']?.toString();
      final dose = item['dose']?.toString();
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;

      if (name == null || type == null || dose == null || qty <= 0) continue;

      final snap = await inventory
          .where('name', isEqualTo: name)
          .where('type', isEqualTo: type)
          .where('dose', isEqualTo: dose)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        batch.update(snap.docs.first.reference, {'quantity': qty});
      } else {
        batch.set(inventory.doc(), {
          'name': name,
          'type': type,
          'dose': dose,
          'quantity': qty,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }
}
