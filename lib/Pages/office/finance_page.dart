// lib/pages/office/finance_page.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/permission_service.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_loans_storage.dart';
import '../../services/local_storage_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/global_module_wrapper.dart';
import 'attendance_tab.dart';
import 'employees_tab.dart';
import 'payroll_tab.dart';
import 'audit_trail_tab.dart';
import 'employee_form_sheet.dart';
import 'holiday_manager_dialog.dart';
import 'finance_report_helper.dart';
import 'xlsx_import_helper.dart';

class FinancePage extends StatefulWidget {
  final String branchId;
  final bool isAdmin;
  final int initialTabIndex;

  const FinancePage({
    super.key,
    required this.branchId,
    this.isAdmin = false,
    this.initialTabIndex = 0,
  });

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _activeBranchId;
  List<Map<String, dynamic>> _branches = [];
  bool _isLoadingBranches = false;
  bool _isDownloadingData = false;

  // ── Sync status tracking ──────────────────────────────────────────────────
  int _pendingSyncCount = 0;
  late final Box _syncBox;

  // ── Search & Filter states ────────────────────────────────────────────────
  final TextEditingController _auditSearchCtrl = TextEditingController();

  // ── Attendance states ─────────────────────────────────────────────────────
  DateTime _attendanceDate = DateTime.now();

  // ── Payroll states ────────────────────────────────────────────────────────
  String _payrollMonthKey = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _activeBranchId = widget.branchId;
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
    _syncBox = Hive.box(LocalStorageService.syncBox);
    _updateSyncCount();

    // Listen to local sync queue changes
    _syncBox.listenable().addListener(_updateSyncCount);

    _loadBranches();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _auditSearchCtrl.dispose();
    _syncBox.listenable().removeListener(_updateSyncCount);
    super.dispose();
  }

  void _updateSyncCount() {
    if (mounted) {
      setState(() {
        _pendingSyncCount = _syncBox.values
            .where((v) => v is Map && (v['type']?.toString().startsWith('save_employee') == true ||
                v['type']?.toString().startsWith('save_salary') == true ||
                v['type']?.toString().startsWith('save_attendance') == true ||
                v['type']?.toString().startsWith('save_finance_settings') == true ||
                v['type']?.toString().startsWith('save_branch_transfer') == true ||
                v['type']?.toString().startsWith('save_audit_log') == true))
            .length;
      });
    }
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoadingBranches = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('branches').get();
      if (mounted) {
        setState(() {
          _branches = snap.docs.map((d) {
            final data = d.data();
            return {'id': d.id, 'name': data['name'] as String? ?? d.id};
          }).toList();
          if (_activeBranchId == 'all' && _branches.isNotEmpty) {
            _activeBranchId = _branches.first['id'];
          }
          _isLoadingBranches = false;
        });
        _triggerDownloadForActiveBranch();
      }
    } catch (e) {
      // Fallback to local branches box
      final box = Hive.box(LocalStorageService.branchesBox);
      if (mounted) {
        setState(() {
          _branches = box.values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
          if (_activeBranchId == 'all' && _branches.isNotEmpty) {
            _activeBranchId = _branches.first['id'];
          }
          _isLoadingBranches = false;
        });
        _triggerDownloadForActiveBranch();
      }
    }
  }

  Future<void> _triggerDownloadForActiveBranch({bool force = false}) async {
    final bId = _activeBranchId;
    if (bId == 'all' || bId.isEmpty) return;
    setState(() => _isDownloadingData = true);
    try {
      // Route through SyncService so TTL guards in FinanceLocalStorage are
      // respected — avoids re-downloading everything every time this page opens.
      await SyncService().triggerFinanceRefresh(force: force);
      await FinanceLoansStorage.migrateLegacyAdvancesToLoans(performedBy: 'System');
    } catch (e) {
      debugPrint('[FinancePage] Error downloading data for branch $bId: $e');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingData = false);
      }
    }
  }

  String _getBranchName(String id) {
    final match = _branches.firstWhereOrNull((b) => b['id'] == id);
    return match != null ? (match['name']?.toString() ?? id) : id;
  }

  void _openEmployeeForm(BuildContext context, String? employeeId) {
    openEmployeeFormSheet(
      context,
      activeBranchId: _activeBranchId,
      branches: _branches,
      employeeId: employeeId,
      onSaved: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  void _openExportReportsDialog(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    String selectedType = 'branch'; // 'branch', 'consolidated', 'department'
    String selectedMonth = _payrollMonthKey;
    String selectedDept = 'Dispensary';

    final depts = ['Dispensary', 'Dasterkhwaan', 'Madrassa', 'Office', 'Administration']
      ..addAll(FinanceLocalStorage.getCustomDepartments());

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (diagCtx, setDiagState) {
            return AlertDialog(
              backgroundColor: t.bgCard,
              title: Text('Export HR & Payroll Reports', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Report Type:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    dropdownColor: t.bgCard,
                    value: selectedType,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: t.bgCardAlt,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      DropdownMenuItem(value: 'branch', child: Text('Branch Payroll Excel', style: TextStyle(color: t.textPrimary))),
                      DropdownMenuItem(value: 'department', child: Text('Department Payroll Excel', style: TextStyle(color: t.textPrimary))),
                      DropdownMenuItem(value: 'consolidated', child: Text('All Branches Consolidated Excel', style: TextStyle(color: t.textPrimary))),
                      DropdownMenuItem(value: 'branch_pdf', child: Text('Branch Payroll PDF', style: TextStyle(color: t.textPrimary))),
                      DropdownMenuItem(value: 'department_pdf', child: Text('Department Payroll PDF', style: TextStyle(color: t.textPrimary))),
                    ],
                    onChanged: (val) {
                      if (val != null) setDiagState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (selectedType == 'department' || selectedType == 'department_pdf') ...[
                    Text('Select Department:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      dropdownColor: t.bgCard,
                      value: selectedDept,
                      style: TextStyle(color: t.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: t.bgCardAlt,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                      ),
                      items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: TextStyle(color: t.textPrimary)))).toList(),
                      onChanged: (val) {
                        if (val != null) setDiagState(() => selectedDept = val);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Select Month Key (yyyy-MM):', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, size: 14),
                        onPressed: () {
                          final parsed = DateFormat('yyyy-MM').parse(selectedMonth);
                          final prev = DateTime(parsed.year, parsed.month - 1, 1);
                          setDiagState(() => selectedMonth = DateFormat('yyyy-MM').format(prev));
                        },
                      ),
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(border: Border.all(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            DateFormat('MMMM yyyy').format(DateFormat('yyyy-MM').parse(selectedMonth)),
                            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 14),
                        onPressed: selectedMonth == DateFormat('yyyy-MM').format(DateTime.now())
                            ? null
                            : () {
                                final parsed = DateFormat('yyyy-MM').parse(selectedMonth);
                                final next = DateTime(parsed.year, parsed.month + 1, 1);
                                setDiagState(() => selectedMonth = DateFormat('yyyy-MM').format(next));
                              },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Export', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (selectedType == 'branch') {
                      await FinanceReportHelper.exportMonthlyExcel(
                        branchId: _activeBranchId,
                        monthKey: selectedMonth,
                      );
                    } else if (selectedType == 'department') {
                      await FinanceReportHelper.exportMonthlyExcel(
                        branchId: _activeBranchId,
                        monthKey: selectedMonth,
                        department: selectedDept,
                      );
                    } else if (selectedType == 'consolidated') {
                      await FinanceReportHelper.exportConsolidatedAllBranchesExcel(
                        branches: _branches,
                        monthKey: selectedMonth,
                      );
                    } else if (selectedType == 'branch_pdf') {
                      await FinanceReportHelper.exportMonthlyPdf(
                        branchId: _activeBranchId,
                        monthKey: selectedMonth,
                      );
                    } else if (selectedType == 'department_pdf') {
                      await FinanceReportHelper.exportMonthlyPdf(
                        branchId: _activeBranchId,
                        monthKey: selectedMonth,
                        department: selectedDept,
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userRole = (Hive.box('local_users').values.firstOrNull?['role']?.toString() ?? 'staff').toLowerCase();
    final ps = PermissionService();
    final canViewAudits = ps.hasPermission(userRole, AppPermission.manageFinance) && 
        ['admin', 'ceo', 'chairman', 'hq manager', 'global admin', 'branch manager'].contains(userRole);

    return RoleThemeScope(
      role: RoleTheme.globalUser,
      child: Builder(
        builder: (context) {
          final t = RoleThemeScope.dataOf(context);
          return Scaffold(
            backgroundColor: t.bg,
            appBar: AppBar(
        automaticallyImplyLeading: !GlobalModuleWrapper.isWrapped(context),
        backgroundColor: t.bgCard,
        elevation: 0,
        title: Row(
          children: [
            Text('Finance & HR', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            if (_branches.isNotEmpty && (widget.branchId == 'all' || ['admin', 'ceo', 'chairman', 'global admin', 'hq manager'].contains(userRole)))
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: t.bgCardAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.bgRule),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _activeBranchId,
                    dropdownColor: t.bgCard,
                    items: _branches.map((b) {
                      final bId = b['id']?.toString() ?? '';
                      return DropdownMenuItem<String>(
                        value: bId,
                        child: Text('${b['name']} ($bId)', style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _activeBranchId = val);
                        _triggerDownloadForActiveBranch();
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
        actions: [
          if (canViewAudits) ...[
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'Manage Holidays',
              color: t.accent,
              onPressed: () => _openHolidaysManager(context),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Import Employees / Attendance from XLSX',
              color: t.accent,
              onPressed: () => XlsxImportHelper.openImportDialog(
                context: context,
                branchId: _activeBranchId,
                theme: t,
                onImported: () {
                  if (mounted) setState(() {});
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export Reports',
              color: t.accent,
              onPressed: () => _openExportReportsDialog(context),
            ),
          ],
          if (_isDownloadingData)
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
              ),
            ),
          _buildSyncIndicator(t),
          const SizedBox(width: 14),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: t.accent,
          unselectedLabelColor: t.textTertiary,
          indicatorColor: t.accent,
          isScrollable: MediaQuery.of(context).size.width < 600,
          tabAlignment: MediaQuery.of(context).size.width < 600 ? TabAlignment.start : TabAlignment.fill,
          tabs: [
            const Tab(text: 'Attendance', icon: Icon(Icons.today_outlined)),
            const Tab(text: 'Employees', icon: Icon(Icons.people_outline)),
            const Tab(text: 'Payroll', icon: Icon(Icons.payments_outlined)),
            Tab(text: 'Audit Trail', icon: Icon(canViewAudits ? Icons.history_edu_outlined : Icons.lock_outline)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          AttendanceTab(
            branchId: _activeBranchId,
            date: _attendanceDate,
            onDateChanged: (d) => setState(() => _attendanceDate = d),
            onAddEmployee: () => _openEmployeeForm(context, null),
          ),
          EmployeesTab(
            branchId: _activeBranchId,
            userRole: userRole,
            openEmployeeForm: _openEmployeeForm,
            branches: _branches,
          ),
          PayrollTab(
            branchId: _activeBranchId,
            monthKey: _payrollMonthKey,
            onMonthChanged: (m) => setState(() => _payrollMonthKey = m),
            userRole: userRole,
          ),
          canViewAudits
              ? AuditTrailTab(
                  branchId: _activeBranchId,
                  searchQuery: _auditSearchCtrl.text,
                  onSearchChanged: (q) => setState(() {}),
                )
              : _buildLockedAuditView(t),
        ],
      ),
    );
        },
      ),
    );
  }

  Widget _buildLockedAuditView(RoleThemeData t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 54, color: t.textTertiary),
          const SizedBox(height: 14),
          Text('Access Restricted', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textSecondary)),
          const SizedBox(height: 6),
          Text('You do not have permissions to view the financial audit trails.', style: TextStyle(fontSize: 12, color: t.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildSyncIndicator(RoleThemeData t) {
    if (_pendingSyncCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
            const SizedBox(width: 8),
            Text('▲ Syncing ($_pendingSyncCount pending)...', style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    final isOnline = _syncBox.get('last_online_state') as bool? ?? true; // fallback
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.withOpacity(0.12) : Colors.blue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isOnline ? Colors.green.withOpacity(0.4) : Colors.blue.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOnline ? Icons.check_circle_outline_rounded : Icons.offline_pin_outlined, color: isOnline ? Colors.green : Colors.blue, size: 14),
          const SizedBox(width: 6),
          Text(
            isOnline ? '✓ Synced' : '● All changes saved locally',
            style: TextStyle(color: isOnline ? Colors.green : Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _openHolidaysManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Card(
          margin: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: HolidayManagerDialog(
            branchId: _activeBranchId,
            branches: _branches,
            userRole: (Hive.box('local_users').values.firstOrNull?['role']?.toString() ?? 'staff').toLowerCase(),
          ),
        );
      },
    );
  }
}
