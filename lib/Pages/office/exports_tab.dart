// lib/pages/office/exports_tab.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../services/local_storage_service.dart';
import '../../services/finance_local_storage.dart';
import '../../services/permission_service.dart';
import 'finance_report_helper.dart';
import 'shared_widgets.dart';

const _kAccent = Color(0xFF10B981);
const _kBg = Color(0xFFF8FAFC);
const _kBgCard = Colors.white;
const _kBorder = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF111827);
const _kTextSecondary = Color(0xFF6B7280);
const _kTextTertiary = Color(0xFF9CA3AF);

class ExportsTab extends StatefulWidget {
  final String branchId;
  final String userRole;
  final List<Map<String, dynamic>> branches;

  const ExportsTab({
    super.key,
    required this.branchId,
    required this.userRole,
    required this.branches,
  });

  @override
  State<ExportsTab> createState() => _ExportsTabState();
}

class _ExportsTabState extends State<ExportsTab> with SingleTickerProviderStateMixin {
  late TabController _innerTabCtrl;
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  
  // Reconcile list items
  List<Map<String, dynamic>> _reconcileItems = [];
  bool _isReconcilingLoading = false;

  @override
  void initState() {
    super.initState();
    _innerTabCtrl = TabController(length: 2, vsync: this);
    _loadReconcileData();
  }

  @override
  void dispose() {
    _innerTabCtrl.dispose();
    super.dispose();
  }

  bool _isMonthLocked() {
    final settingsBox = Hive.box(LocalStorageService.financeSettingsBox);
    return settingsBox.get('month_lock_$_selectedMonth') == true;
  }

  String _formatPaisa(int paisa) {
    return NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0).format(paisa / 100);
  }

  Future<void> _loadReconcileData() async {
    setState(() => _isReconcilingLoading = true);
    try {
      final ledgerBox = Hive.box(LocalStorageService.salaryLedgerBox);
      final expensesBox = Hive.box(LocalStorageService.expensesBox);
      final settingsBox = Hive.box(LocalStorageService.financeSettingsBox);

      final reconciledIds = Set<String>.from(settingsBox.get('reconciled_ids_$_selectedMonth') as List? ?? []);

      final list = <Map<String, dynamic>>[];

      // 1. Fetch Ledger Entries for branch & month
      for (final val in ledgerBox.values) {
        if (val is Map) {
          final entry = Map<String, dynamic>.from(val);
          if (entry['branchId'] == widget.branchId && entry['isVoided'] != true) {
            final dateStr = entry['date']?.toString() ?? '';
            if (dateStr.length >= 7 && dateStr.substring(0, 7) == _selectedMonth) {
              final id = entry['id']?.toString() ?? '';
              list.add({
                'id': id,
                'type': 'Payroll: ${entry['type'] ?? 'payout'}',
                'description': '${entry['employeeName']} - ${entry['notes'] ?? ''}',
                'amountMinor': (entry['amountMinor'] as num?)?.toInt() ?? 0,
                'date': dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr,
                'isReconciled': reconciledIds.contains(id),
                'ref': entry,
              });
            }
          }
        }
      }

      // 2. Fetch Expenses for branch & month
      for (final val in expensesBox.values) {
        if (val is Map) {
          final exp = Map<String, dynamic>.from(val);
          if (exp['branchId'] == widget.branchId && exp['isVoided'] != true) {
            final dateStr = exp['date']?.toString() ?? '';
            if (dateStr.length >= 7 && dateStr.substring(0, 7) == _selectedMonth) {
              final id = exp['id']?.toString() ?? exp['expenseId']?.toString() ?? '';
              list.add({
                'id': id,
                'type': 'Expense: ${exp['category'] ?? 'General'}',
                'description': exp['description'] ?? '',
                'amountMinor': (exp['amountMinor'] as num?)?.toInt() ?? 0,
                'date': dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr,
                'isReconciled': reconciledIds.contains(id),
                'ref': exp,
              });
            }
          }
        }
      }

      setState(() {
        _reconcileItems = list;
        _isReconcilingLoading = false;
      });
    } catch (e) {
      setState(() => _isReconcilingLoading = false);
      debugPrint('[Reconcile] Load error: $e');
    }
  }

  Future<void> _toggleReconcile(String id, bool checked) async {
    final settingsBox = Hive.box(LocalStorageService.financeSettingsBox);
    final key = 'reconciled_ids_$_selectedMonth';
    final reconciledList = List<String>.from(settingsBox.get(key) as List? ?? []);

    if (checked) {
      reconciledList.add(id);
    } else {
      reconciledList.remove(id);
    }

    await settingsBox.put(key, reconciledList);
    await settingsBox.flush();

    setState(() {
      final idx = _reconcileItems.indexWhere((item) => item['id'] == id);
      if (idx != -1) {
        _reconcileItems[idx]['isReconciled'] = checked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final permissionService = PermissionService();
    final lockAccess = permissionService.getPeriodLockAccess(widget.userRole);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          decoration: const BoxDecoration(color: _kBgCard, border: Border(bottom: BorderSide(color: _kBorder))),
          child: Row(
            children: [
              TabBar(
                controller: _innerTabCtrl,
                isScrollable: true,
                indicatorColor: _kAccent,
                labelColor: _kAccent,
                unselectedLabelColor: _kTextSecondary,
                tabs: const [
                  Tab(text: 'Finalized Exports'),
                  Tab(text: 'Bank Reconciliation'),
                ],
              ),
              const Spacer(),
              // Month Switcher
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 14),
                onPressed: () {
                  final p = DateFormat('yyyy-MM').parse(_selectedMonth);
                  setState(() {
                    _selectedMonth = DateFormat('yyyy-MM').format(DateTime(p.year, p.month - 1));
                  });
                  _loadReconcileData();
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(DateFormat('yyyy-MM').parse(_selectedMonth)),
                style: const TextStyle(fontWeight: FontWeight.bold, color: _kTextPrimary),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 14),
                onPressed: _selectedMonth == DateFormat('yyyy-MM').format(DateTime.now())
                    ? null
                    : () {
                        final p = DateFormat('yyyy-MM').parse(_selectedMonth);
                        setState(() {
                          _selectedMonth = DateFormat('yyyy-MM').format(DateTime(p.year, p.month + 1));
                        });
                        _loadReconcileData();
                      },
              ),
              const SizedBox(width: 8),
              _buildLockBadge(lockAccess),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _innerTabCtrl,
        children: [
          _buildExportsTab(),
          _buildReconciliationTab(),
        ],
      ),
    );
  }

  Widget _buildLockBadge(FinanceAccess lockAccess) {
    final locked = _isMonthLocked();
    return GestureDetector(
      onTap: () {
        if (lockAccess == FinanceAccess.full) {
          _showLockToggleDialog(locked);
        } else if (lockAccess == FinanceAccess.requestOnly) {
          _requestLockToggle(locked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: locked ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: locked ? Colors.redAccent : _kAccent),
        ),
        child: Row(
          children: [
            Icon(locked ? Icons.lock : Icons.lock_open, size: 12, color: locked ? Colors.red : _kAccent),
            const SizedBox(width: 4),
            Text(
              locked ? 'Locked' : 'Open',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: locked ? Colors.red : _kAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportsTab() {
    final locked = _isMonthLocked();
    String selType = 'branch';
    String selDept = 'Dispensary';
    final depts = ['Administration', 'Office', 'Dasterkhawaan', 'Dispensary', 'Madrassa', 'School']
      ..addAll(FinanceLocalStorage.getCustomDepartments());

    return StatefulBuilder(builder: (ctx, setS) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _kBgCard,
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.download_rounded, color: _kAccent),
                  SizedBox(width: 8),
                  Text('Download Monthly Payroll & Sheets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              if (!locked)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Warning: This month period is not locked yet. Exporting reports from unlocked periods may contain data subject to revision.',
                          style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              const Text('Report Type:', style: TextStyle(color: _kTextSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selType,
                dropdownColor: _kBgCard,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                items: const [
                  DropdownMenuItem(value: 'branch', child: Text('Salary Sheet (Excel)')),
                  DropdownMenuItem(value: 'department', child: Text('Departmental Salary Sheet (Excel)')),
                  DropdownMenuItem(value: 'consolidated', child: Text('Consolidated All Branches (Excel)')),
                  DropdownMenuItem(value: 'branch_pdf', child: Text('Bank Transfer Slip (PDF)')),
                  DropdownMenuItem(value: 'department_pdf', child: Text('Departmental Bank Transfer Slip (PDF)')),
                  DropdownMenuItem(value: 'expenses_excel', child: Text('Expenses Report (Excel)')),
                ],
                onChanged: (v) { if (v != null) setS(() => selType = v); },
              ),
              if (selType == 'department' || selType == 'department_pdf') ...[
                const SizedBox(height: 16),
                const Text('Select Department:', style: TextStyle(color: _kTextSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selDept,
                  dropdownColor: _kBgCard,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                  items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) { if (v != null) setS(() => selDept = v); },
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export Document', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  onPressed: () async {
                    if (selType == 'branch') await FinanceReportHelper.exportMonthlyExcel(branchId: widget.branchId, monthKey: _selectedMonth);
                    else if (selType == 'department') await FinanceReportHelper.exportMonthlyExcel(branchId: widget.branchId, monthKey: _selectedMonth, department: selDept);
                    else if (selType == 'consolidated') await FinanceReportHelper.exportConsolidatedAllBranchesExcel(branches: widget.branches, monthKey: _selectedMonth);
                    else if (selType == 'branch_pdf') await FinanceReportHelper.exportMonthlyPdf(branchId: widget.branchId, monthKey: _selectedMonth);
                    else if (selType == 'department_pdf') await FinanceReportHelper.exportMonthlyPdf(branchId: widget.branchId, monthKey: _selectedMonth, department: selDept);
                    else if (selType == 'expenses_excel') await FinanceReportHelper.exportExpensesExcel(branchId: widget.branchId, monthKey: _selectedMonth);
                    showCustomSnackBar(context, 'Export generated successfully.');
                  },
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildReconciliationTab() {
    if (_isReconcilingLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final reconciledCount = _reconcileItems.where((i) => i['isReconciled']).length;
    final totalCount = _reconcileItems.length;
    final progress = totalCount > 0 ? (reconciledCount / totalCount) : 1.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bank & Cash Statement Reconciliation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kTextPrimary)),
                    const SizedBox(height: 4),
                    Text('Reconcile current ledger transactions against statement lines for GMWF ($_selectedMonth)', style: const TextStyle(fontSize: 12, color: _kTextSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(8)),
                child: Text('Reconciled: $reconciledCount / $totalCount items', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kTextSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress, color: _kAccent, backgroundColor: Colors.grey[200]),
          const SizedBox(height: 24),
          Expanded(
            child: _reconcileItems.isEmpty
                ? const Center(child: Text('No active transactions found for this month.', style: TextStyle(color: _kTextTertiary)))
                : ListView.separated(
                    itemCount: _reconcileItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                    itemBuilder: (context, idx) {
                      final item = _reconcileItems[idx];
                      final isRec = item['isReconciled'] == true;

                      return CheckboxListTile(
                        value: isRec,
                        activeColor: _kAccent,
                        title: Row(
                          children: [
                            Text(item['type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextPrimary)),
                            const SizedBox(width: 8),
                            Text(item['date'], style: const TextStyle(color: _kTextTertiary, fontSize: 11)),
                          ],
                        ),
                        subtitle: Text(item['description'], style: const TextStyle(color: _kTextSecondary, fontSize: 12)),
                        secondary: Text(
                          _formatPaisa(item['amountMinor']),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isRec ? Colors.green : Colors.red),
                        ),
                        onChanged: (val) {
                          if (val != null) {
                            _toggleReconcile(item['id'], val);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showLockToggleDialog(bool locked) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _kBgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(locked ? 'Unlock Payroll Month' : 'Lock Payroll Month', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            locked
                ? 'Are you sure you want to unlock the payroll period for $_selectedMonth? This will allow modifications to past salary/repayments.'
                : 'Are you sure you want to lock the payroll period for $_selectedMonth? This will freeze all payroll and expense ledger entries for this month.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: locked ? Colors.orange : _kAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final settingsBox = Hive.box(LocalStorageService.financeSettingsBox);
                await settingsBox.put('month_lock_$_selectedMonth', !locked);
                
                // Propagate locked flag on all ledger entries of this month
                final ledgerBox = Hive.box(LocalStorageService.salaryLedgerBox);
                for (final key in ledgerBox.keys) {
                  final val = ledgerBox.get(key);
                  if (val is Map) {
                    final dateStr = val['date']?.toString() ?? '';
                    if (dateStr.length >= 7 && dateStr.substring(0, 7) == _selectedMonth) {
                      final updated = Map<String, dynamic>.from(val)..['periodLocked'] = !locked;
                      await ledgerBox.put(key, updated);
                    }
                  }
                }

                // Propagate to expenses
                final expensesBox = Hive.box(LocalStorageService.expensesBox);
                for (final key in expensesBox.keys) {
                  final val = expensesBox.get(key);
                  if (val is Map) {
                    final dateStr = val['date']?.toString() ?? '';
                    if (dateStr.length >= 7 && dateStr.substring(0, 7) == _selectedMonth) {
                      final updated = Map<String, dynamic>.from(val)..['periodLocked'] = !locked;
                      await expensesBox.put(key, updated);
                    }
                  }
                }

                await ledgerBox.flush();
                await expensesBox.flush();

                showCustomSnackBar(context, locked ? 'Payroll period unlocked.' : 'Payroll period closed and locked.');
                Navigator.pop(ctx);
                setState(() {});
                _loadReconcileData();
              },
              child: Text(locked ? 'Unlock' : 'Lock Period'),
            ),
          ],
        );
      },
    );
  }

  void _requestLockToggle(bool locked) async {
    try {
      final performedBy = Hive.box('local_users').values.firstOrNull?['name']?.toString() ?? 'System';
      await LocalStorageService.enqueueSync({
        'type': 'request_month_lock_approval',
        'branchId': widget.branchId,
        'data': {
          'id': 'pending_lock_${_selectedMonth}_${DateTime.now().millisecondsSinceEpoch}',
          'monthKey': _selectedMonth,
          'lockState': !locked,
          'requestedBy': performedBy,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }
      });
      showCustomSnackBar(context, 'Lock period request submitted for CEO approval.');
    } catch (e) {
      showCustomSnackBar(context, 'Error requesting lock toggle: $e', error: true);
    }
  }
}
