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
  final bool isAdmin;

  const AssetsPage({
    super.key,
    required this.branchId,
    required this.isAdmin,
  });

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  // Colors for Admin
  static const Color adminPrimary = Color(0xFF37474F);
  static const Color adminAccent = Color(0xFF26A69A);
  static const Color adminDanger = Color(0xFFE57373);
  static const Color adminBackground = Color(0xFFF5F5F5);
  static const Color adminCardBg = Colors.white;
  static const Color adminTextPrimary = Color(0xFF212121);
  static const Color adminTextSecondary = Color(0xFF757575);

  // Colors for Supervisor
  static const Color superPrimary = Color(0xFF2E7D32);
  static const Color superAccent = Color(0xFF4CAF50); // Changed to a better matching green
  static const Color superDanger = Color(0xFFE53935);
  static const Color superBackground = Color(0xFFFAFAFA);
  static const Color superCardBg = Color(0xFFF0F4F8);
  static const Color superTextPrimary = Color(0xFF263238);
  static const Color superTextSecondary = Color(0xFF546E7A);

  final _formKey = GlobalKey<FormState>();
  final _costFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _repairCostCtrl = TextEditingController();
  final _damageCtrl = TextEditingController();
  final _billNameCtrl = TextEditingController();
  final _billAmountCtrl = TextEditingController();
  final _employeeNameCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  DateTime? _repairDate;

  bool _allowEditing = false;

  @override
  void initState() {
    super.initState();
    _listenToEditPermission();
  }

  void _listenToEditPermission() {
    FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('settings')
        .doc('assets')
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _allowEditing = snap.data()?['allowSupervisorEdit'] ?? false;
        });
      }
    });
  }

  Future<void> _toggleEditPermission(bool value) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('settings')
        .doc('assets')
        .set({'allowSupervisorEdit': value}, SetOptions(merge: true));
  }

  void _clearAssetForm() {
    _nameCtrl.clear();
    _categoryCtrl.clear();
    _priceCtrl.clear();
    _notesCtrl.clear();
    _repairCostCtrl.clear();
    _damageCtrl.clear();
    _selectedDate = DateTime.now();
    _repairDate = null;
  }

  void _clearCostForm() {
    _billNameCtrl.clear();
    _billAmountCtrl.clear();
    _employeeNameCtrl.clear();
  }

  void _showAssetDialog({
    DispensaryAsset? asset,
    required Color primary,
    required Color accent,
    required Color danger,
    required Color textPrimary,
  }) {
    final isEdit = asset != null;
    if (isEdit) {
      _nameCtrl.text = asset!.name;
      _categoryCtrl.text = asset.category;
      _priceCtrl.text = asset.purchasePrice.toStringAsFixed(0);
      _notesCtrl.text = asset.notes;
      _selectedDate = asset.purchaseDate;
      _repairDate = asset.repairDate;
      _repairCostCtrl.text = asset.repairCost?.toStringAsFixed(0) ?? '';
      _damageCtrl.text = asset.damageDescription ?? '';
    } else {
      _clearAssetForm();
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isWide = MediaQuery.of(context).size.width > 800;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(
                  isEdit ? Icons.edit : Icons.add_circle_outline,
                  color: isEdit ? accent : primary,
                  size: isWide ? 32 : 28,
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? "Edit Asset" : "Add New Asset",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    fontSize: isWide ? 22 : 20,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isWide ? 700 : double.maxFinite,
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _textField(_nameCtrl, "Asset Name", required: true, primary: primary),
                      const SizedBox(height: 16),
                      _textField(_categoryCtrl, "Category", required: true, primary: primary),
                      const SizedBox(height: 16),
                      _textField(_priceCtrl, "Purchase Price (Rs.)", required: true, number: true, primary: primary),
                      const SizedBox(height: 16),
                      _dateField("Purchase Date", _selectedDate, (d) {
                        _selectedDate = d!;
                        setLocal(() {});
                      }, primary: primary),
                      const SizedBox(height: 16),
                      _textField(_notesCtrl, "Notes (optional)", maxLines: 3, primary: primary),
                      const Divider(height: 40, thickness: 1),
                      Text("Damage & Repair (optional)", style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary, fontSize: 16)),
                      const SizedBox(height: 12),
                      _textField(_damageCtrl, "Damage Description", maxLines: 3, primary: primary),
                      const SizedBox(height: 16),
                      _dateField("Repair Date", _repairDate, (d) => setLocal(() => _repairDate = d), primary: primary),
                      const SizedBox(height: 16),
                      _textField(_repairCostCtrl, "Repair Cost (Rs.)", number: true, primary: primary),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEdit ? accent : primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;

                  final data = {
                    'name': _nameCtrl.text.trim(),
                    'category': _categoryCtrl.text.trim(),
                    'purchasePrice': double.parse(_priceCtrl.text),
                    'purchaseDate': _selectedDate,
                    'notes': _notesCtrl.text.trim(),
                    'damageDescription': _damageCtrl.text.isEmpty ? null : _damageCtrl.text.trim(),
                    'repairDate': _repairDate,
                    'repairCost': _repairCostCtrl.text.isEmpty ? null : double.parse(_repairCostCtrl.text),
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

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? "Asset updated!" : "Asset added!"),
                      backgroundColor: isEdit ? accent : primary,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Text(isEdit ? "Update" : "Save", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddOperatingCostDialog({required Color primary, required Color textPrimary}) {
    _clearCostForm();

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          String selectedType = 'Bill/Payment';
          final isWide = MediaQuery.of(context).size.width > 800;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(Icons.receipt_long, color: primary, size: isWide ? 32 : 28),
                const SizedBox(width: 12),
                Text("Add Operating Cost", style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: isWide ? 22 : 20)),
              ],
            ),
            content: SizedBox(
              width: isWide ? 500 : double.maxFinite,
              child: Form(
                key: _costFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: "Cost Type",
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primary, width: 2)),
                      ),
                      items: ['Bill/Payment', 'Salary'].map((String type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setLocal(() {
                          selectedType = value!;
                        });
                      },
                      validator: (value) => value == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _textField(_billNameCtrl, "Description (e.g. Electricity or Monthly Salary)", required: true, primary: primary),
                    const SizedBox(height: 16),
                    if (selectedType == 'Salary')
                      _textField(_employeeNameCtrl, "Employee Name", required: true, primary: primary),
                    const SizedBox(height: 16),
                    _textField(_billAmountCtrl, "Amount (Rs.)", required: true, number: true, primary: primary),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  if (!_costFormKey.currentState!.validate()) return;
                  if (selectedType == 'Salary' && _employeeNameCtrl.text.trim().isEmpty) return;

                  await FirebaseFirestore.instance
                      .collection('branches')
                      .doc(widget.branchId)
                      .collection('monthly_bills')
                      .add({
                    'type': selectedType,
                    'name': _billNameCtrl.text.trim(),
                    'employeeName': selectedType == 'Salary' ? _employeeNameCtrl.text.trim() : null,
                    'amount': double.parse(_billAmountCtrl.text),
                    'addedAt': FieldValue.serverTimestamp(),
                  });

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text("Operating cost added!"), backgroundColor: primary, behavior: SnackBarBehavior.floating),
                  );
                },
                child: const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteAsset(String id, String name, Color danger) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirm Delete", style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text("Delete asset \"$name\"? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('dispensary_assets')
                  .doc(id)
                  .delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$name deleted"), backgroundColor: danger, behavior: SnackBarBehavior.floating),
              );
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _deleteCost(String id, String name, Color danger) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirm Delete", style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text("Delete cost \"$name\"?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('monthly_bills')
                  .doc(id)
                  .delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$name removed"), backgroundColor: danger, behavior: SnackBarBehavior.floating),
              );
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showAssetDetailsDialog(DispensaryAsset asset, Color primary, Color accent, Color danger, Color textPrimary, Color textSecondary, bool canEdit) {
    final hasRepair = asset.repairDate != null;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(asset.name, style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Category', asset.category, textSecondary),
              _detailRow('Price', "Rs. ${asset.purchasePrice.toStringAsFixed(0)}", accent),
              _detailRow('Date', DateFormat('dd MMM yyyy').format(asset.purchaseDate), textSecondary),
              _detailRow('Notes', asset.notes.isEmpty ? '-' : asset.notes, textSecondary),
              if (asset.damageDescription != null)
                _detailRow('Damage', asset.damageDescription!, danger),
              if (hasRepair)
                _detailRow('Repair Date', DateFormat('dd MMM yyyy').format(asset.repairDate!), danger),
              if (asset.repairCost != null)
                _detailRow('Repair Cost', "Rs. ${asset.repairCost!.toStringAsFixed(0)}", danger),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Close", style: TextStyle(color: textPrimary))),
          if (canEdit) ...[
            ElevatedButton.icon(
              icon: Icon(Icons.edit, color: Colors.white),
              label: Text("Edit"),
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              onPressed: () {
                Navigator.pop(ctx);
                _showAssetDialog(asset: asset, primary: primary, accent: accent, danger: danger, textPrimary: textPrimary);
              },
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.delete, color: Colors.white),
              label: Text("Delete"),
              style: ElevatedButton.styleFrom(backgroundColor: danger),
              onPressed: () {
                Navigator.pop(ctx);
                _deleteAsset(asset.id, asset.name, danger);
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 900;
    final bool isMobile = screenWidth < 600;

    final bool canEdit = widget.isAdmin || _allowEditing;

    final Color primary = widget.isAdmin ? adminPrimary : superPrimary;
    final Color accent = widget.isAdmin ? adminAccent : superAccent;
    final Color danger = widget.isAdmin ? adminDanger : superDanger;
    final Color background = widget.isAdmin ? adminBackground : superBackground;
    final Color cardBackground = widget.isAdmin ? adminCardBg : superCardBg;
    final Color textPrimary = widget.isAdmin ? adminTextPrimary : superTextPrimary;
    final Color textSecondary = widget.isAdmin ? adminTextSecondary : superTextSecondary;

    Widget? flexibleSpace;
    Color appBarColor = primary;
    if (!widget.isAdmin) {
      appBarColor = Colors.transparent;
      flexibleSpace = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1B5E20), superPrimary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        leading: widget.isAdmin ? const BackButton(color: Colors.white) : null,
        title: const Text("Dispensary Assets & Costs"),
        backgroundColor: appBarColor,
        flexibleSpace: flexibleSpace,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: widget.isAdmin
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Row(
                    children: [
                      const Text("Allow Supervisor Edit", style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 8),
                      Switch(
                        value: _allowEditing,
                        onChanged: _toggleEditPermission,
                        activeColor: accent,
                        activeTrackColor: accent.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),
              ]
            : [
                if (!_allowEditing)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Chip(
                      label: const Text("Read-only mode"),
                      backgroundColor: accent.withOpacity(0.2),
                      labelStyle: TextStyle(color: accent),
                    ),
                  ),
              ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isWide ? 48 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (canEdit)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: cardBackground,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showAssetDialog(
                            primary: primary,
                            accent: accent,
                            danger: danger,
                            textPrimary: textPrimary,
                          ),
                          icon: Icon(Icons.add, color: Colors.white),
                          label: const Text("Add Asset"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showAddOperatingCostDialog(primary: primary, textPrimary: textPrimary),
                          icon: Icon(Icons.receipt_long, color: Colors.white),
                          label: const Text("Add Cost"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            _buildSummaryCard(isWide: isWide, textPrimary: textPrimary, accent: accent, cardBackground: cardBackground, primary: primary),

            const SizedBox(height: 32),

            _buildOperatingCosts(
              isWide: isWide,
              isMobile: isMobile,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              accent: accent,
              danger: danger,
              cardBackground: cardBackground,
              canEdit: canEdit,
            ),

            const SizedBox(height: 32),

            Text("Assets List", style: TextStyle(fontSize: isWide ? 26 : 22, fontWeight: FontWeight.w700, color: textPrimary)),

            const SizedBox(height: 16),

            _buildAssetsView(
              isWide: isWide,
              isMobile: isMobile,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              accent: accent,
              danger: danger,
              primary: primary,
              canEdit: canEdit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required bool isWide,
    required Color textPrimary,
    required Color accent,
    required Color cardBackground,
    required Color primary,
  }) {
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
            if (assetSnap.connectionState == ConnectionState.waiting ||
                billSnap.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: primary));
            }

            final assets = assetSnap.data?.docs
                    .map((d) => DispensaryAsset.fromMap(d.id, d.data() as Map<String, dynamic>))
                    .toList() ??
                [];

            final totalPurchase = assets.fold<double>(0.0, (sum, a) => sum + a.purchasePrice);

            final totalBills = billSnap.data?.docs.fold<double>(0.0, (sum, doc) {
                  return sum + (((doc.data() as Map<String, dynamic>)['amount'] as num?)?.toDouble() ?? 0.0);
                }) ??
                0.0;

            return Card(
              elevation: 4,
              color: cardBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: isWide
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _summaryChip("Total Assets", "${assets.length}", Icons.inventory_2, textPrimary, isWide),
                          _summaryChip("Total Invested", "Rs. ${totalPurchase.toStringAsFixed(0)}", Icons.account_balance_wallet, accent, isWide),
                          _summaryChip("Monthly Costs", "Rs. ${totalBills.toStringAsFixed(0)}", Icons.payments, accent, isWide),
                        ],
                      )
                    : Column(
                        children: [
                          _summaryChip("Total Assets", "${assets.length}", Icons.inventory_2, textPrimary, isWide),
                          const SizedBox(height: 24),
                          _summaryChip("Total Invested", "Rs. ${totalPurchase.toStringAsFixed(0)}", Icons.account_balance_wallet, accent, isWide),
                          const SizedBox(height: 24),
                          _summaryChip("Monthly Costs", "Rs. ${totalBills.toStringAsFixed(0)}", Icons.payments, accent, isWide),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _summaryChip(String label, String value, IconData icon, Color color, bool isWide) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: isWide ? 28 : 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: isWide ? 16 : 14, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isWide ? 22 : 18, color: color)),
          ],
        ),
      ],
    );
  }

  Widget _buildOperatingCosts({
    required bool isWide,
    required bool isMobile,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
    required Color danger,
    required Color cardBackground,
    required bool canEdit,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('monthly_bills')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: accent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final costs = snapshot.data!.docs;

        return Card(
          elevation: 4,
          color: cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Text(
                  "Monthly Operating Costs",
                  style: TextStyle(fontSize: isWide ? 22 : 18, fontWeight: FontWeight.w700, color: textPrimary),
                ),
              ),
              if (!isMobile)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                      DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                      DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                      if (canEdit) DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                    ],
                    rows: costs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final type = data['type'] ?? 'Bill/Payment';
                      final name = data['name'] ?? 'Unknown';
                      final employeeName = data['employeeName'] as String?;
                      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                      final category = type == 'Salary' ? 'Salary${employeeName != null ? ' for $employeeName' : ''}' : type;
                      return DataRow(cells: [
                        DataCell(Text(name, style: TextStyle(color: textSecondary))),
                        DataCell(Text(category, style: TextStyle(color: type == 'Salary' ? accent : textSecondary))),
                        DataCell(Text("Rs. ${amount.toStringAsFixed(0)}", style: TextStyle(color: accent))),
                        if (canEdit)
                          DataCell(IconButton(
                            icon: Icon(Icons.delete, color: danger),
                            onPressed: () => _deleteCost(doc.id, name, danger),
                          )),
                      ]);
                    }).toList(),
                  ),
                ),
              if (isMobile)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: costs.length,
                  itemBuilder: (context, index) {
                    final doc = costs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final type = data['type'] ?? 'Bill/Payment';
                    final name = data['name'] ?? 'Unknown';
                    final employeeName = data['employeeName'] as String?;
                    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                    final category = type == 'Salary' ? 'Salary${employeeName != null ? ' for $employeeName' : ''}' : type;
                    return SizedBox(
                      height: 80, // Fixed height for consistency
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
                          subtitle: Text(category, style: TextStyle(color: textSecondary)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Rs. ${amount.toStringAsFixed(0)}", style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                              if (canEdit) IconButton(
                                icon: Icon(Icons.delete, color: danger),
                                onPressed: () => _deleteCost(doc.id, name, danger),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAssetsView({
    required bool isWide,
    required bool isMobile,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
    required Color danger,
    required Color primary,
    required bool canEdit,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('dispensary_assets')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: primary));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text("No assets added yet.", style: TextStyle(color: textSecondary, fontSize: 16)));
        }

        final assets = snapshot.data!.docs
            .map((doc) => DispensaryAsset.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList();

        if (!isMobile) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 60,
              dataRowHeight: 72,
              border: TableBorder.all(color: Colors.grey.shade200, width: 1),
              columns: [
                DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                DataColumn(label: Text('Price', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                DataColumn(label: Text('Notes', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                DataColumn(label: Text('Damage', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                DataColumn(label: Text('Repair Date', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                DataColumn(label: Text('Repair Cost', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                if (canEdit) DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
              ],
              rows: assets.map((asset) {
                final hasRepair = asset.repairDate != null;
                return DataRow(cells: [
                  DataCell(Text(asset.name, style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                  DataCell(Text(asset.category, style: TextStyle(color: textSecondary))),
                  DataCell(Text("Rs. ${asset.purchasePrice.toStringAsFixed(0)}", style: TextStyle(color: accent))),
                  DataCell(Text(DateFormat('dd MMM yyyy').format(asset.purchaseDate), style: TextStyle(color: textSecondary))),
                  DataCell(Text(asset.notes.isEmpty ? '-' : asset.notes, style: TextStyle(color: textSecondary))),
                  DataCell(Text(asset.damageDescription ?? '-', style: TextStyle(color: asset.damageDescription != null ? danger : textSecondary))),
                  DataCell(Text(hasRepair ? DateFormat('dd MMM yyyy').format(asset.repairDate!) : '-', style: TextStyle(color: hasRepair ? danger : textSecondary))),
                  DataCell(Text(asset.repairCost != null ? "Rs. ${asset.repairCost!.toStringAsFixed(0)}" : '-', style: TextStyle(color: asset.repairCost != null ? danger : textSecondary))),
                  if (canEdit)
                    DataCell(Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: accent),
                          onPressed: () => _showAssetDialog(asset: asset, primary: primary, accent: accent, danger: danger, textPrimary: textPrimary),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: danger),
                          onPressed: () => _deleteAsset(asset.id, asset.name, danger),
                        ),
                      ],
                    )),
                ]);
              }).toList(),
            ),
          );
        } else {
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: assets.length,
            itemBuilder: (context, index) {
              final asset = assets[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: primary.withOpacity(0.1),
                    child: Icon(Icons.inventory, color: primary),
                  ),
                  title: Text(asset.name, style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
                  subtitle: Text(asset.category, style: TextStyle(color: textSecondary)),
                  trailing: canEdit
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showAssetDialog(asset: asset, primary: primary, accent: accent, danger: danger, textPrimary: textPrimary);
                            } else if (value == 'delete') {
                              _deleteAsset(asset.id, asset.name, danger);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        )
                      : null,
                  onTap: () => _showAssetDetailsDialog(asset, primary, accent, danger, textPrimary, textSecondary, canEdit),
                ),
              );
            },
          );
        }
      },
    );
  }

  Widget _detailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text("$label: ", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          Expanded(child: Text(value, style: TextStyle(color: color))),
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    bool number = false,
    int maxLines = 1,
    required Color primary,
  }) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return TextFormField(
      controller: ctrl,
      keyboardType: number ? TextInputType.number : null,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: TextStyle(fontSize: isWide ? 16 : 14, color: Colors.grey.shade700),
      ),
      validator: required
          ? (v) {
              if (v == null || v.trim().isEmpty) return "Required";
              if (number && double.tryParse(v) == null) return "Invalid number";
              return null;
            }
          : null,
    );
  }

  Widget _dateField(String label, DateTime? date, Function(DateTime?) onSelect, {required Color primary}) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (context, child) => Theme(
            data: ThemeData.light().copyWith(
              colorScheme: ColorScheme.light(primary: primary),
            ),
            child: child!,
          ),
        );
        if (d != null) onSelect(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: Icon(Icons.calendar_today, color: primary),
        ),
        child: Text(
          date == null ? "Not set" : DateFormat('dd MMM yyyy').format(date),
          style: TextStyle(fontSize: isWide ? 16 : 14),
        ),
      ),
    );
  }
}