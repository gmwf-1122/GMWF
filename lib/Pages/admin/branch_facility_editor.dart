// lib/pages/admin/branch_facility_editor.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart';
import '../../services/local_storage_service.dart';

class BranchFacilityEditorDialog extends StatefulWidget {
  final String branchId;
  final String currentBranchName;
  final List<Map<String, dynamic>> initialDispensaries;
  final List<Map<String, dynamic>> initialDasterkhwaans;
  final List<Map<String, dynamic>> initialMadrassas;
  final List<Map<String, dynamic>> initialSchools;

  const BranchFacilityEditorDialog({
    super.key,
    required this.branchId,
    required this.currentBranchName,
    this.initialDispensaries = const [],
    this.initialDasterkhwaans = const [],
    this.initialMadrassas = const [],
    this.initialSchools = const [],
  });

  static Future<bool?> show(
    BuildContext context, {
    required String branchId,
    required String currentBranchName,
    List<Map<String, dynamic>> initialDispensaries = const [],
    List<Map<String, dynamic>> initialDasterkhwaans = const [],
    List<Map<String, dynamic>> initialMadrassas = const [],
    List<Map<String, dynamic>> initialSchools = const [],
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BranchFacilityEditorDialog(
        branchId: branchId,
        currentBranchName: currentBranchName,
        initialDispensaries: initialDispensaries,
        initialDasterkhwaans: initialDasterkhwaans,
        initialMadrassas: initialMadrassas,
        initialSchools: initialSchools,
      ),
    );
  }

  @override
  State<BranchFacilityEditorDialog> createState() =>
      _BranchFacilityEditorDialogState();
}

class _BranchFacilityEditorDialogState
    extends State<BranchFacilityEditorDialog> {
  late TextEditingController _nameController;
  late TextEditingController _dispensaryInputCtrl;
  late TextEditingController _dasterkhwaanInputCtrl;
  late TextEditingController _madrassaInputCtrl;
  late TextEditingController _schoolInputCtrl;

  late List<Map<String, String>> _dispensaries;
  late List<Map<String, String>> _dasterkhwaans;
  late List<Map<String, String>> _madrassas;
  late List<Map<String, String>> _schools;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentBranchName);
    _dispensaryInputCtrl = TextEditingController();
    _dasterkhwaanInputCtrl = TextEditingController();
    _madrassaInputCtrl = TextEditingController();
    _schoolInputCtrl = TextEditingController();

    final defaults = LocalStorageService.getDefaultBranchFacilities(widget.branchId);

    _dispensaries = widget.initialDispensaries.isNotEmpty
        ? widget.initialDispensaries.map((d) => {'id': (d['id'] ?? '').toString(), 'name': (d['name'] ?? '').toString()}).toList()
        : (defaults['dispensaries'] ?? []);

    _dasterkhwaans = widget.initialDasterkhwaans.isNotEmpty
        ? widget.initialDasterkhwaans.map((d) => {'id': (d['id'] ?? '').toString(), 'name': (d['name'] ?? '').toString()}).toList()
        : (defaults['dasterkhwaans'] ?? []);

    _madrassas = widget.initialMadrassas.isNotEmpty
        ? widget.initialMadrassas.map((d) => {'id': (d['id'] ?? '').toString(), 'name': (d['name'] ?? '').toString()}).toList()
        : (defaults['madrassas'] ?? []);

    _schools = widget.initialSchools.isNotEmpty
        ? widget.initialSchools.map((d) => {'id': (d['id'] ?? '').toString(), 'name': (d['name'] ?? '').toString()}).toList()
        : (defaults['schools'] ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dispensaryInputCtrl.dispose();
    _dasterkhwaanInputCtrl.dispose();
    _madrassaInputCtrl.dispose();
    _schoolInputCtrl.dispose();
    super.dispose();
  }

  void _addDispensary() {
    final text = _dispensaryInputCtrl.text.trim();
    if (text.isEmpty) return;
    final id = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (_dispensaries.any((d) => d['id'] == id)) return;
    setState(() {
      _dispensaries.add({'id': id, 'name': text});
      _dispensaryInputCtrl.clear();
    });
  }

  void _addDasterkhwaan() {
    final text = _dasterkhwaanInputCtrl.text.trim();
    if (text.isEmpty) return;
    final id = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (_dasterkhwaans.any((d) => d['id'] == id)) return;
    setState(() {
      _dasterkhwaans.add({'id': id, 'name': text});
      _dasterkhwaanInputCtrl.clear();
    });
  }

  void _addMadrassa() {
    final text = _madrassaInputCtrl.text.trim();
    if (text.isEmpty) return;
    final id = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (_madrassas.any((d) => d['id'] == id)) return;
    setState(() {
      _madrassas.add({'id': id, 'name': text});
      _madrassaInputCtrl.clear();
    });
  }

  void _addSchool() {
    final text = _schoolInputCtrl.text.trim();
    if (text.isEmpty) return;
    final id = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (_schools.any((d) => d['id'] == id)) return;
    setState(() {
      _schools.add({'id': id, 'name': text});
      _schoolInputCtrl.clear();
    });
  }

  Future<void> _saveBranchData() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch Name cannot be empty')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final docData = <String, dynamic>{
        'name': newName,
        'dispensaries': _dispensaries,
        'dasterkhwaans': _dasterkhwaans,
        'madrassas': _madrassas,
        'schools': _schools,
        'dispensariesCount': _dispensaries.length,
        'dasterkhwaansCount': _dasterkhwaans.length,
        'madrassasCount': _madrassas.length,
        'schoolsCount': _schools.length,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 1. Firestore Update
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .set(docData, SetOptions(merge: true));

      // 2. Local Hive Box Update
      if (Hive.isBoxOpen('local_branches')) {
        final box = Hive.box('local_branches');
        await box.put('branch:${widget.branchId}', {
          'id': widget.branchId,
          'name': newName,
          'dispensaries': _dispensaries,
          'dasterkhwaans': _dasterkhwaans,
          'madrassas': _madrassas,
          'schools': _schools,
          'dispensariesCount': _dispensaries.length,
          'dasterkhwaansCount': _dasterkhwaans.length,
          'madrassasCount': _madrassas.length,
          'schoolsCount': _schools.length,
        });
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update branch: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: t.bgCard,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.settings_rounded, color: t.accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configure Branch Facilities',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: t.textPrimary,
                          ),
                        ),
                        Text(
                          'ID: ${widget.branchId} • Dispensaries: ${_dispensaries.length} | Dasterkhwaans: ${_dasterkhwaans.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: t.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: t.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: t.bgRule, height: 1),
              const SizedBox(height: 16),

              // Branch Name Field
              Text('Branch Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: TextStyle(color: t.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.store_rounded, color: t.textTertiary, size: 20),
                  filled: true,
                  fillColor: t.bgCardAlt,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.bgRule)),
                ),
              ),
              const SizedBox(height: 18),

              // ── Section 1: Sub-Dispensaries ──────────────────────────────
              _buildSectionHeader('Dispensary Facilities (${_dispensaries.length})', Icons.local_hospital_outlined, t.accent),
              const SizedBox(height: 8),
              _buildInputRow(_dispensaryInputCtrl, 'e.g. Kapayya Dispensary', _addDispensary, t.accent, t),
              const SizedBox(height: 8),
              _buildChips(_dispensaries, t.accent, (id) => setState(() => _dispensaries.removeWhere((i) => i['id'] == id)), t),

              const SizedBox(height: 18),

              // ── Section 2: Sub-Dasterkhwaans ─────────────────────────────
              _buildSectionHeader('Dasterkhwaan Facilities (${_dasterkhwaans.length})', Icons.restaurant_outlined, Colors.orange),
              const SizedBox(height: 8),
              _buildInputRow(_dasterkhwaanInputCtrl, 'e.g. Unit 1 - Main Dasterkhwaan', _addDasterkhwaan, Colors.orange.shade700, t),
              const SizedBox(height: 8),
              _buildChips(_dasterkhwaans, Colors.orange, (id) => setState(() => _dasterkhwaans.removeWhere((i) => i['id'] == id)), t),

              const SizedBox(height: 18),

              // ── Section 3: Sub-Madrassas ────────────────────────────────
              _buildSectionHeader('Madrassa Facilities (${_madrassas.length})', Icons.menu_book_rounded, Colors.teal),
              const SizedBox(height: 8),
              _buildInputRow(_madrassaInputCtrl, 'e.g. Main Madrassa', _addMadrassa, Colors.teal, t),
              const SizedBox(height: 8),
              _buildChips(_madrassas, Colors.teal, (id) => setState(() => _madrassas.removeWhere((i) => i['id'] == id)), t),

              const SizedBox(height: 18),

              // ── Section 4: Sub-Schools ─────────────────────────────────
              _buildSectionHeader('School Facilities (${_schools.length})', Icons.school_rounded, Colors.indigo),
              const SizedBox(height: 8),
              _buildInputRow(_schoolInputCtrl, 'e.g. Model Primary School', _addSchool, Colors.indigo, t),
              const SizedBox(height: 8),
              _buildChips(_schools, Colors.indigo, (id) => setState(() => _schools.removeWhere((i) => i['id'] == id)), t),

              const SizedBox(height: 24),
              Divider(color: t.bgRule, height: 1),
              const SizedBox(height: 18),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveBranchData,
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_isSaving ? 'Saving...' : 'Save Facility Configuration'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInputRow(TextEditingController ctrl, String hint, VoidCallback onAdd, Color btnColor, RoleThemeData t) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
              filled: true,
              fillColor: t.bgCardAlt,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.bgRule)),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add'),
          style: ElevatedButton.styleFrom(
            backgroundColor: btnColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildChips(List<Map<String, String>> items, Color color, Function(String id) onDelete, RoleThemeData t) {
    if (items.isEmpty) {
      return Text('No sub-facilities added', style: TextStyle(fontSize: 11, color: t.textTertiary, fontStyle: FontStyle.italic));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return Chip(
          backgroundColor: color.withValues(alpha: 0.12),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          label: Text(item['name']!, style: TextStyle(fontSize: 12, color: t.textPrimary, fontWeight: FontWeight.w600)),
          deleteIcon: const Icon(Icons.cancel_rounded, size: 16),
          deleteIconColor: Colors.redAccent,
          onDeleted: () => onDelete(item['id']!),
        );
      }).toList(),
    );
  }
}
