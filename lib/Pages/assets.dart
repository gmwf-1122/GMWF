// lib/pages/assets.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DispensaryAsset {
  final String id;
  final String name;
  final String category;
  final double purchasePrice;
  final DateTime purchaseDate;
  final String notes;
  final DateTime? repairDate;
  final double? repairCost;
  final String? damageDescription;

  DispensaryAsset({
    required this.id,
    required this.name,
    required this.category,
    required this.purchasePrice,
    required this.purchaseDate,
    required this.notes,
    this.repairDate,
    this.repairCost,
    this.damageDescription,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'purchasePrice': purchasePrice,
        'purchaseDate': purchaseDate,
        'notes': notes,
        'repairDate': repairDate,
        'repairCost': repairCost,
        'damageDescription': damageDescription,
      };

  factory DispensaryAsset.fromMap(String id, Map<String, dynamic> map) =>
      DispensaryAsset(
        id: id,
        name: map['name'] ?? '',
        category: map['category'] ?? '',
        purchasePrice: (map['purchasePrice'] as num?)?.toDouble() ?? 0.0,
        purchaseDate:
            (map['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        notes: map['notes'] ?? '',
        repairDate: (map['repairDate'] as Timestamp?)?.toDate(),
        repairCost: (map['repairCost'] as num?)?.toDouble(),
        damageDescription: map['damageDescription'] as String?,
      );
}

class AssetsPage extends StatefulWidget {
  final String branchId;
  final bool isAdmin; // NEW: Admin permission

  const AssetsPage({super.key, required this.branchId, required this.isAdmin});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  // ── COLORS (high‑contrast, readable on any background) ───────
  static const Color green = Color(0xFF27AE60); // darker green
  static const Color orange = Color(0xFFE67E22); // darker orange
  static const Color grey = Color(0xFF7F8C8D); // darker grey
  static const Color red = Color(0xFFE74C3C); // good contrast
  static const Color navy = Color(0xFF1A2B3C); // deeper navy

  // Card background (light solid) – text is dark
  static const Color cardBg = Color(0xFFF5F7FA);

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _repairCostCtrl = TextEditingController();
  final _damageCtrl = TextEditingController();
  final _billNameCtrl = TextEditingController();
  final _billAmountCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  DateTime? _repairDate;

  // ── ADD / EDIT ASSET DIALOG ─────────────────────────────────────
  void _showAssetDialog({DispensaryAsset? asset}) {
    final isEdit = asset != null;
    if (isEdit) {
      _nameCtrl.text = asset.name;
      _categoryCtrl.text = asset.category;
      _priceCtrl.text = asset.purchasePrice.toStringAsFixed(0);
      _notesCtrl.text = asset.notes;
      _selectedDate = asset.purchaseDate;
      _repairDate = asset.repairDate;
      _repairCostCtrl.text = asset.repairCost?.toStringAsFixed(0) ?? '';
      _damageCtrl.text = asset.damageDescription ?? '';
    } else {
      _clearForm();
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                Icon(isEdit ? Icons.edit : Icons.add_circle_outline,
                    color: isEdit ? orange : green),
                const SizedBox(width: 8),
                Text(isEdit ? "Edit Asset" : "Add New Asset",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: navy)),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _textField(_nameCtrl, "Asset Name", required: true),
                      const SizedBox(height: 12),
                      _textField(_categoryCtrl, "Category", required: true),
                      const SizedBox(height: 12),
                      _textField(_priceCtrl, "Purchase Price (Rs.)",
                          required: true, number: true),
                      const SizedBox(height: 12),
                      _dateField("Purchase Date", _selectedDate, (d) {
                        _selectedDate = d!;
                        setLocal(() {});
                      }),
                      const SizedBox(height: 12),
                      _textField(_notesCtrl, "Notes (optional)", maxLines: 2),
                      const Divider(height: 32),
                      const Text("Damage & Repair (optional)",
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: navy)),
                      const SizedBox(height: 8),
                      _textField(_damageCtrl, "What was damaged?", maxLines: 2),
                      const SizedBox(height: 12),
                      _dateField("Repair Date", _repairDate,
                          (d) => setLocal(() => _repairDate = d)),
                      const SizedBox(height: 12),
                      _textField(_repairCostCtrl, "Repair Cost (Rs.)",
                          number: true),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel", style: TextStyle(color: navy))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: isEdit ? orange : green),
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;

                  final data = {
                    'name': _nameCtrl.text,
                    'category': _categoryCtrl.text,
                    'purchasePrice': double.parse(_priceCtrl.text),
                    'purchaseDate': _selectedDate,
                    'notes': _notesCtrl.text,
                    'damageDescription':
                        _damageCtrl.text.isEmpty ? null : _damageCtrl.text,
                    'repairDate': _repairDate,
                    'repairCost': _repairCostCtrl.text.isEmpty
                        ? null
                        : double.parse(_repairCostCtrl.text),
                  };

                  if (isEdit) {
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(widget.branchId)
                        .collection('dispensary_assets')
                        .doc(asset!.id)
                        .update(data);
                  } else {
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(widget.branchId)
                        .collection('dispensary_assets')
                        .add(data);
                  }

                  if (mounted) Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? "Asset updated!" : "Asset added!"),
                      backgroundColor: isEdit ? orange : green,
                    ),
                  );
                },
                child: Text(isEdit ? "Update" : "Save",
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── ADD OPERATING COST DIALOG ─────────────────────────────────────────────
  void _showAddOperatingCostDialog() {
    _billNameCtrl.clear();
    _billAmountCtrl.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: navy),
            SizedBox(width: 8),
            Text("Add Operating Cost",
                style: TextStyle(fontWeight: FontWeight.bold, color: navy)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _textField(_billNameCtrl, "Cost Name (e.g. Electricity)",
                  required: true),
              const SizedBox(height: 12),
              _textField(_billAmountCtrl, "Amount (Rs.)",
                  required: true, number: true),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: navy))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: navy),
            onPressed: () async {
              if (_billNameCtrl.text.isEmpty || _billAmountCtrl.text.isEmpty)
                return;

              await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('monthly_bills')
                  .add({
                'name': _billNameCtrl.text,
                'amount': double.parse(_billAmountCtrl.text),
                'addedAt': FieldValue.serverTimestamp(),
              });

              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: const Text("Cost added!"), backgroundColor: navy),
              );
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── DELETE ASSET (ADMIN ONLY) ───────────────────────────────────
  void _deleteAsset(String id, String name) {
    if (!widget.isAdmin) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Delete",
            style: TextStyle(color: navy, fontWeight: FontWeight.bold)),
        content: Text("Delete asset: $name?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: navy))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: red),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('dispensary_assets')
                  .doc(id)
                  .delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$name deleted"), backgroundColor: red),
              );
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── DELETE COST (ADMIN ONLY) ───────────────────────────────────
  void _deleteCost(String id, String name) {
    if (!widget.isAdmin) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Delete",
            style: TextStyle(color: navy, fontWeight: FontWeight.bold)),
        content: Text("Delete cost: $name?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: navy))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: red),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('monthly_bills')
                  .doc(id)
                  .delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$name removed"), backgroundColor: red),
              );
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    _nameCtrl.clear();
    _categoryCtrl.clear();
    _priceCtrl.clear();
    _notesCtrl.clear();
    _repairCostCtrl.clear();
    _damageCtrl.clear();
    _selectedDate = DateTime.now();
    _repairDate = null;
  }

  // ── BUILD ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER + BUTTONS ─────────────────────────────────
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, size: 28, color: navy),
              const SizedBox(width: 12),
              const Text("Dispensary Assets",
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: navy)),
              const Spacer(),
              if (widget.isAdmin)
                ElevatedButton.icon(
                  onPressed: _showAssetDialog,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text("Add Asset",
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: green),
                ),
              if (widget.isAdmin) const SizedBox(width: 12),
              if (widget.isAdmin)
                ElevatedButton.icon(
                  onPressed: _showAddOperatingCostDialog,
                  icon: const Icon(Icons.receipt, color: Colors.white),
                  label: const Text("Add Cost",
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: navy),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── SUMMARY CHIPS ─────────────────────────────────────
          _buildSummaryCard(),
          const SizedBox(height: 16),

          // ── OPERATING COSTS ────────────────────────────────────────
          _buildOperatingCosts(),
          const SizedBox(height: 16),

          // ── ASSET TABLE ────────────────────────────────────────
          Expanded(child: _buildAssetTable()),
        ],
      ),
    );
  }

  // ── SUMMARY CARD ──────────────────────────────────────────────
  Widget _buildSummaryCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('dispensary_assets')
          .snapshots(),
      builder: (context, assetSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('monthly_bills')
              .snapshots(),
          builder: (context, billSnap) {
            if (!assetSnap.hasData && !billSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final assets = assetSnap.data?.docs
                    .map((d) => DispensaryAsset.fromMap(
                        d.id, d.data() as Map<String, dynamic>))
                    .toList() ??
                [];
            final totalPurchase =
                assets.fold(0.0, (s, a) => s + a.purchasePrice);

            final bills = billSnap.data?.docs ?? [];
            final totalBills = bills.fold<double>(0.0, (sum, doc) {
              final amount = doc['amount'];
              if (amount is num) return sum + amount.toDouble();
              return sum;
            });

            return Card(
              color: cardBg,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryChip(
                        "Total Assets", "${assets.length}", Icons.inventory,
                        color: navy),
                    _summaryChip(
                        "Total Invested",
                        "Rs. ${totalPurchase.toStringAsFixed(0)}",
                        Icons.account_balance_wallet,
                        color: green),
                    _summaryChip("Monthly Operating Cost",
                        "Rs. ${totalBills.toStringAsFixed(0)}", Icons.payments,
                        color: orange),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── OPERATING COSTS ────────────────────────────────────────────────
  Widget _buildOperatingCosts() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('monthly_bills')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          color: cardBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text("Operating Costs",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: navy)),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      MaterialStateProperty.all(Colors.grey.shade200),
                  columns: [
                    const DataColumn(
                        label: Text('Name',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: navy))),
                    const DataColumn(
                        label: Text('Amount',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: navy))),
                    if (widget.isAdmin)
                      const DataColumn(
                          label: Text('Actions',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, color: navy))),
                  ],
                  rows: snapshot.data!.docs.map((doc) {
                    final name = doc['name'] ?? 'Unknown';
                    final amount = (doc['amount'] as num?)?.toDouble() ?? 0.0;
                    return DataRow(cells: [
                      DataCell(Text(name, style: const TextStyle(color: navy))),
                      DataCell(Text("Rs. ${amount.toStringAsFixed(0)}",
                          style: const TextStyle(color: orange))),
                      if (widget.isAdmin)
                        DataCell(IconButton(
                          icon: const Icon(Icons.delete, color: red),
                          onPressed: () => _deleteCost(doc.id, name),
                        )),
                    ]);
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── ASSET TABLE ────────────────────────────────────────────────
  Widget _buildAssetTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('dispensary_assets')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child:
                  Text("No assets added yet.", style: TextStyle(color: grey)));
        }

        final assets = snapshot.data!.docs
            .map((doc) => DispensaryAsset.fromMap(
                doc.id, doc.data() as Map<String, dynamic>))
            .toList();

        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
              columns: [
                const DataColumn(
                    label: Text('Name',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                const DataColumn(
                    label: Text('Category',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                const DataColumn(
                    label: Text('Purchase Price',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                const DataColumn(
                    label: Text('Purchase Date',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                const DataColumn(
                    label: Text('Notes',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                const DataColumn(
                    label: Text('Damage Description',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                const DataColumn(
                    label: Text('Repair Date',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                const DataColumn(
                    label: Text('Repair Cost',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: navy))),
                if (widget.isAdmin)
                  const DataColumn(
                      label: Text('Actions',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: navy))),
              ],
              rows: assets.map((asset) {
                final hasRepair = asset.repairDate != null;
                return DataRow(cells: [
                  DataCell(Text(asset.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: navy))),
                  DataCell(Text(asset.category,
                      style: const TextStyle(color: grey))),
                  DataCell(Text("Rs. ${asset.purchasePrice.toStringAsFixed(0)}",
                      style: const TextStyle(color: orange))),
                  DataCell(Text(
                      DateFormat('dd MMM yyyy').format(asset.purchaseDate),
                      style: const TextStyle(color: grey))),
                  DataCell(
                      Text(asset.notes, style: const TextStyle(color: grey))),
                  DataCell(Text(asset.damageDescription ?? 'N/A',
                      style: const TextStyle(color: red))),
                  DataCell(Text(
                      hasRepair
                          ? DateFormat('dd MMM yyyy').format(asset.repairDate!)
                          : 'N/A',
                      style: const TextStyle(color: red))),
                  DataCell(Text(
                      asset.repairCost != null
                          ? "Rs. ${asset.repairCost!.toStringAsFixed(0)}"
                          : 'N/A',
                      style: const TextStyle(color: red))),
                  if (widget.isAdmin)
                    DataCell(Row(
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit, color: orange),
                            onPressed: () => _showAssetDialog(asset: asset)),
                        IconButton(
                            icon: const Icon(Icons.delete, color: red),
                            onPressed: () =>
                                _deleteAsset(asset.id, asset.name)),
                      ],
                    )),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────
  Widget _textField(TextEditingController ctrl, String label,
      {bool required = false, bool number = false, int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: number ? TextInputType.number : null,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: green)),
        labelStyle: const TextStyle(color: navy),
      ),
      style: const TextStyle(color: navy),
      validator: required ? (v) => v!.isEmpty ? "Required" : null : null,
    );
  }

  Widget _dateField(
      String label, DateTime? date, Function(DateTime?) onSelect) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) onSelect(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, color: navy),
          labelStyle: const TextStyle(color: navy),
        ),
        child: Text(
          date == null ? "Not set" : DateFormat('dd MMM yyyy').format(date),
          style: TextStyle(color: date == null ? grey : navy),
        ),
      ),
    );
  }

  Widget _summaryChip(String label, String value, IconData icon,
      {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? navy, size: 28),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(fontSize: 13, color: grey),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15, color: navy)),
      ],
    );
  }
}
