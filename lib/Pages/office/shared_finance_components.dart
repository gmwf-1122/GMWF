// lib/pages/office/shared_finance_components.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/design_system.dart';
import 'package:intl/intl.dart';
import '../../services/finance_ledger_storage.dart';
import '../../widgets/bank_logo_widget.dart';

const _kAccent = SoftPalette.emerald350;
const _kBgCard = SoftPalette.gray50;
const _kBorder = SoftPalette.slate150;
const _kTextPrimary = SoftPalette.slate900;
const _kTextSecondary = SoftPalette.slate550;

// ── 1. AccountPicker Component ───────────────────────────────────────────────

class AccountPicker extends StatelessWidget {
  final String? selectedAccountCode;
  final ValueChanged<OrgBankAccount?> onChanged;
  final String? label;
  final bool isRequired;
  final String? hint;

  const AccountPicker({
    super.key,
    required this.selectedAccountCode,
    required this.onChanged,
    this.label,
    this.isRequired = false,
    this.hint = 'Select Org Bank / Cash Account',
  });

  @override
  Widget build(BuildContext context) {
    final accounts = FinanceLedgerStorage.getOrgBankAccounts();
    final balances = FinanceLedgerStorage.getAllAccountBalancesPaisa();
    OrgBankAccount? selectedAcc;
    if (selectedAccountCode != null) {
      selectedAcc = accounts.where((a) => a.accountCode == selectedAccountCode).firstOrNull;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Row(
            children: [
              Text(label!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.adapt(_kTextPrimary))),
              if (isRequired) const Text(' *', style: TextStyle(color: SoftPalette.red400, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.adapt(SoftPalette.gray50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.adapt(_kBorder), width: 1.2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<OrgBankAccount>(
              value: selectedAcc,
              hint: Text(hint!, style: TextStyle(fontSize: 13, color: context.adapt(_kTextSecondary))),
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.adapt(_kTextSecondary)),
              items: accounts.map((acc) {
                final balancePaisa = balances[acc.accountCode] ?? 0;
                final balancePkr = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0).format(balancePaisa / 100);

                return DropdownMenuItem<OrgBankAccount>(
                  value: acc,
                  child: Row(
                    children: [
                      BankLogoWidget(bankName: acc.bankName, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              acc.accountTitle,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.adapt(_kTextPrimary)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${acc.accountNumber} • Balance: $balancePkr',
                              style: TextStyle(fontSize: 11, color: context.adapt(_kTextSecondary)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 2. Unified Single FilterBar ───────────────────────────────────────────────

class GlobalFilterBar extends StatelessWidget {
  final String selectedBranchId;
  final String selectedDeptId;
  final String? selectedAccountCode;
  final List<Map<String, dynamic>> branches;
  final ValueChanged<String> onBranchChanged;
  final ValueChanged<String> onDeptChanged;
  final ValueChanged<String?>? onAccountChanged;
  final VoidCallback? onReset;

  const GlobalFilterBar({
    super.key,
    required this.selectedBranchId,
    required this.selectedDeptId,
    this.selectedAccountCode,
    required this.branches,
    required this.onBranchChanged,
    required this.onDeptChanged,
    this.onAccountChanged,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final depts = FinanceLedgerStorage.getDepartments();

    final uniqueBranches = <String, Map<String, dynamic>>{};
    for (final b in branches) {
      final id = b['id']?.toString().trim() ?? '';
      if (id.isNotEmpty && id.toLowerCase() != 'all') {
        uniqueBranches[id] = b;
      }
    }
    final branchItems = [
      const DropdownMenuItem(value: 'all', child: Text('All Branches', style: TextStyle(fontSize: 11))),
      ...uniqueBranches.values.map((b) => DropdownMenuItem(
        value: b['id']?.toString() ?? '',
        child: Text(b['name']?.toString() ?? b['id']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
      )),
    ];
    final safeBranchValue = branchItems.any((it) => it.value == selectedBranchId) ? selectedBranchId : 'all';

    final uniqueDepts = <String, Map<String, dynamic>>{};
    for (final d in depts) {
      final id = d['id']?.toString().toUpperCase().trim() ?? '';
      if (id.isNotEmpty && id != 'ALL') {
        uniqueDepts[id] = d;
      }
    }
    final deptItems = [
      const DropdownMenuItem(value: 'ALL', child: Text('All Departments', style: TextStyle(fontSize: 11))),
      ...uniqueDepts.values.map((d) => DropdownMenuItem(
        value: d['id']?.toString().toUpperCase() ?? '',
        child: Text(d['name']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
      )),
    ];
    final safeDeptValue = deptItems.any((it) => it.value == selectedDeptId.toUpperCase()) ? selectedDeptId.toUpperCase() : 'ALL';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: context.adapt(_kBgCard),
        border: Border(bottom: BorderSide(color: context.adapt(_kBorder))),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 18, color: _kAccent),
          const SizedBox(width: 8),
          Text('Filters:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: context.adapt(_kTextPrimary))),
          const SizedBox(width: 16),

          // Branch Filter
          if (branches.isNotEmpty) ...[
            _buildDropdown<String>(
              context: context,
              label: 'Branch',
              value: safeBranchValue,
              items: branchItems,
              onChanged: (v) { if (v != null) onBranchChanged(v); },
            ),
            const SizedBox(width: 12),
          ],

          // Department Filter
          _buildDropdown<String>(
            context: context,
            label: 'Department',
            value: safeDeptValue,
            items: deptItems,
            onChanged: (v) { if (v != null) onDeptChanged(v); },
          ),

          const Spacer(),

          if (selectedBranchId != 'all' || selectedDeptId.toUpperCase() != 'ALL')
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: SoftPalette.red400,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.clear_rounded, size: 14),
              label: const Text('Reset Filters', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: onReset,
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required BuildContext context,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final uniqueItems = <T, DropdownMenuItem<T>>{};
    for (final it in items) {
      if (it.value != null && !uniqueItems.containsKey(it.value)) {
        uniqueItems[it.value as T] = it;
      }
    }
    final dedupedItems = uniqueItems.values.toList();
    final safeValue = dedupedItems.any((it) => it.value == value) ? value : (dedupedItems.isNotEmpty ? dedupedItems.first.value : null);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: context.adapt(_kTextSecondary), fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: context.adapt(SoftPalette.gray50),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.adapt(_kBorder)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: safeValue,
              dropdownColor: context.adapt(SoftPalette.gray50),
              style: TextStyle(color: context.adapt(_kTextPrimary), fontSize: 11, fontWeight: FontWeight.bold),
              items: dedupedItems,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 3. VoidableRecordDialog Component ────────────────────────────────────────

class VoidableRecordDialog extends StatefulWidget {
  final String title;
  final String entityDescription;

  const VoidableRecordDialog({
    super.key,
    required this.title,
    required this.entityDescription,
  });

  static Future<Map<String, String>?> show(BuildContext context, {required String title, required String entityDescription}) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => VoidableRecordDialog(title: title, entityDescription: entityDescription),
    );
  }

  @override
  State<VoidableRecordDialog> createState() => _VoidableRecordDialogState();
}

class _VoidableRecordDialogState extends State<VoidableRecordDialog> {
  final _reasonCtrl = TextEditingController();
  final _approverCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _approverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: SoftPalette.red400, size: 24),
          const SizedBox(width: 10),
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to void/reverse "${widget.entityDescription}"? This action will generate a balancing reversal entry in the double-entry ledger.',
                style: TextStyle(fontSize: 12, color: context.adapt(_kTextSecondary))),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason for Voiding *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please provide a valid reason' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _approverCtrl,
              decoration: const InputDecoration(
                labelText: 'Approved By (Manager / Admin) *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Approver name is required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: SoftPalette.red400, foregroundColor: SoftPalette.gray50),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'reason': _reasonCtrl.text.trim(),
                'approvedBy': _approverCtrl.text.trim(),
              });
            }
          },
          child: const Text('Confirm Void'),
        ),
      ],
    );
  }
}

// ── 4. Department & Branch Chips ─────────────────────────────────────────────

class DepartmentChip extends StatelessWidget {
  final String department;

  const DepartmentChip({super.key, required this.department});

  static Color getDeptColor(String dept) {
    final d = dept.toLowerCase();
    if (d.contains('dispensary')) return SoftPalette.sky500;
    if (d.contains('madrassa')) return SoftPalette.emerald500;
    if (d.contains('school')) return SoftPalette.violet550;
    if (d.contains('dasterkhwaan')) return SoftPalette.orange400;
    if (d.contains('office') || d.contains('admin')) return SoftPalette.slate600;
    return SoftPalette.slate550;
  }

  @override
  Widget build(BuildContext context) {
    final col = context.adapt(getDeptColor(department));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        department.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: col),
      ),
    );
  }
}

class BranchChip extends StatelessWidget {
  final String branchId;

  const BranchChip({super.key, required this.branchId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.adapt(SoftPalette.slate100),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.adapt(SoftPalette.slate200), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_rounded, size: 11, color: context.adapt(SoftPalette.slate600)),
          const SizedBox(width: 4),
          Text(
            branchId.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.adapt(SoftPalette.slate700)),
          ),
        ],
      ),
    );
  }
}
