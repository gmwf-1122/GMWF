// lib/pages/office/employee_detail_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_loans_storage.dart';
import '../../services/local_storage_service.dart';
import '../../services/permission_service.dart';
import 'finance_report_helper.dart';
import 'employee_form_sheet.dart';
import 'shared_widgets.dart';

class EmployeeDetailPage extends StatefulWidget {
  final String employeeId;
  final String userRole;
  final Function(BuildContext context, String employeeId)? openEmployeeForm;

  const EmployeeDetailPage({
    super.key,
    required this.employeeId,
    required this.userRole,
    this.openEmployeeForm,
  });

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedMonthKey = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showOffboardDialog(BuildContext context, Map<String, dynamic> emp) {
    DateTime exitDate = DateTime.now();
    String reason = 'Resigned';
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dCtx) {
        final t = RoleThemeScope.dataOf(context);
        return StatefulBuilder(
          builder: (dialogCtx, setDS) {
            return AlertDialog(
              backgroundColor: t.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.person_off_outlined, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Offboard ${emp['name'] ?? 'Employee'}',
                      style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to offboard this employee? Salary calculations and active status will be terminated.',
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  
                  // Exit Date Picker
                  Text('Exit Date', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogCtx,
                        initialDate: exitDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDS(() => exitDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.bgCardAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(DateFormat('dd MMM yyyy').format(exitDate), style: TextStyle(color: t.textPrimary, fontSize: 13)),
                          Icon(Icons.calendar_today_outlined, size: 16, color: t.accent),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Offboarding Reason
                  Text('Offboard Reason', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: reason,
                    dropdownColor: t.bgCard,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: t.bgCardAlt,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.bgRule)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.bgRule)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Resigned', child: Text('Resigned')),
                      DropdownMenuItem(value: 'Terminated', child: Text('Terminated')),
                      DropdownMenuItem(value: 'Contract Ended', child: Text('Contract Ended')),
                      DropdownMenuItem(value: 'Retired', child: Text('Retired')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDS(() => reason = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Notes / Remarks
                  Text('Offboarding Remarks (Optional)', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesCtrl,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter reason or exit notes...',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: t.bgCardAlt,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.bgRule)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.bgRule)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.pop(dCtx);
                    await FinanceLocalStorage.syncBiDirectionalOffboarding(
                      employeeId: widget.employeeId,
                      performedBy: widget.userRole,
                    );
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${emp['name'] ?? 'Employee'} has been offboarded.')),
                      );
                    }
                  },
                  child: const Text('Confirm Offboard'),
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
    final t = RoleThemeScope.dataOf(context);

    return ValueListenableBuilder(
      valueListenable: FinanceLocalStorage.employeesBox.listenable(),
      builder: (c, Box box, _) {
        final emp = FinanceLocalStorage.getEmployee(widget.employeeId);

        if (emp == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
          return Scaffold(
            backgroundColor: t.bg,
            appBar: AppBar(title: const Text('Employee Details')),
            body: const SizedBox.shrink(),
          );
        }

        final name = emp['name']?.toString() ?? '';
        final role = emp['role']?.toString() ?? emp['designation']?.toString() ?? 'Employee';
        final dept = emp['department']?.toString() ?? 'Office';
        final isActive = emp['isActive'] as bool? ?? true;
        final status = emp['status'] as String? ?? (isActive ? 'Active' : 'Offboarded');

        final curRole = widget.userRole.toLowerCase().trim();
        final empRole = role.toLowerCase().trim();
        final empDept = dept.toLowerCase().trim();
        final isExecOrAdmin = empRole == 'ceo' ||
            empRole == 'hq manager' ||
            empRole == 'hq_manager' ||
            empRole == 'admin' ||
            empRole == 'chairman' ||
            empDept == 'administration';
        final canEditEmp = curRole == 'chairman' || (!isExecOrAdmin);

        return Scaffold(
          backgroundColor: t.bg,
          appBar: AppBar(
            backgroundColor: t.bgCard,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: t.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('$role • $dept', style: TextStyle(color: t.textSecondary, fontSize: 11)),
              ],
            ),
            actions: [
              if (isActive && canEditEmp) ...[
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: t.accent),
                  tooltip: 'Edit Employee',
                  onPressed: () {
                    if (widget.openEmployeeForm != null) {
                      widget.openEmployeeForm!(context, widget.employeeId);
                    } else {
                      openEmployeeFormSheet(
                        context,
                        activeBranchId: emp['branchId']?.toString() ?? 'all',
                        branches: const [],
                        employeeId: widget.employeeId,
                        onSaved: () => setState(() {}),
                      );
                    }
                  },
                ),

                IconButton(
                  icon: const Icon(Icons.person_off_outlined, color: Colors.redAccent),
                  tooltip: 'Offboard Employee',
                  onPressed: () => _showOffboardDialog(context, emp),
                ),
              ],
              IconButton(
                icon: Icon(Icons.picture_as_pdf_outlined, color: t.accent),
                tooltip: 'Export Profile PDF',
                onPressed: () => FinanceReportHelper.exportIndividualPdf(widget.employeeId),
              ),
              IconButton(
                icon: Icon(Icons.receipt_long_outlined, color: t.accent),
                tooltip: 'Export Payment History PDF',
                onPressed: () => FinanceReportHelper.exportPaymentReportPdf(widget.employeeId),
              ),
            ],
          ),
          body: Column(
            children: [
              // Hero Profile Banner
              _buildHeaderBanner(emp, t, isActive, status),

              // Navigation TabBar
              Container(
                color: t.bgCard,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: t.accent,
                  labelColor: t.accent,
                  unselectedLabelColor: t.textTertiary,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Profile'),
                    Tab(icon: Icon(Icons.calendar_today_outlined, size: 18), text: 'Attendance'),
                    Tab(icon: Icon(Icons.verified_user_outlined, size: 18), text: 'Leaves'),
                    Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'History'),
                  ],
                ),
              ),

              // TabBar Body
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProfileTab(emp, t),
                    _buildAttendanceTab(emp, t),
                    _buildLeavesTab(emp, t),
                    _buildHistoryTab(emp, t),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderBanner(Map<String, dynamic> emp, RoleThemeData t, bool isActive, String status) {
    final name = emp['name']?.toString() ?? '';
    final role = emp['role']?.toString() ?? emp['designation']?.toString() ?? '';
    final dept = emp['department']?.toString() ?? '';
    final branchName = FinanceLocalStorage.getBranchName(emp['branchId']?.toString() ?? '');
    final salary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: t.bgCard,
        border: Border(bottom: BorderSide(color: t.bgRule)),
      ),
      child: Row(
        children: [
          buildInitialsAvatar(
            name: name,
            theme: t,
            radius: 28,
            imageUrl: emp['profilePictureUrl']?.toString(),
            imagePath: emp['profilePicturePath']?.toString(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
                    const SizedBox(width: 8),
                    buildStatusPill(
                      theme: t,
                      label: status.toUpperCase(),
                      variant: isActive ? StatusPillVariant.success : StatusPillVariant.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('$role • $dept ${branchName.isNotEmpty ? '($branchName)' : ''}', style: TextStyle(fontSize: 12, color: t.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 14, color: t.accent),
                    const SizedBox(width: 4),
                    Text('Salary: PKR ${NumberFormat('#,##0').format(salary.toInt())}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.accent)),
                    if (emp['joiningDate'] != null && emp['joiningDate'].toString().isNotEmpty) ...[
                      const SizedBox(width: 16),
                      Icon(Icons.event_available_outlined, size: 14, color: t.textTertiary),
                      const SizedBox(width: 4),
                      Text('Joined: ${emp['joiningDate']}', style: TextStyle(fontSize: 12, color: t.textTertiary)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Profile & Job Details ───────────────────────────────────────────
  Widget _buildProfileTab(Map<String, dynamic> emp, RoleThemeData t) {
    final salary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
    final bankName = emp['bankName']?.toString() ?? 'Meezan Bank Limited';
    final iban = emp['bankAccount']?.toString() ?? 'N/A';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailSection(
            title: 'JOB & FINANCIAL DETAILS',
            t: t,
            items: [
              _DetailRow('Joining Date', emp['joiningDate']?.toString() ?? 'N/A'),
              if (emp['exitDate'] != null && emp['exitDate'].toString().isNotEmpty)
                _DetailRow('Exit Date', emp['exitDate']?.toString() ?? 'N/A'),
              _DetailRow('Current Branch', FinanceLocalStorage.getBranchName(emp['branchId']?.toString() ?? '')),
              _DetailRow('Department', emp['department']?.toString() ?? 'N/A'),
              _DetailRow('Base Salary', 'PKR ${NumberFormat('#,##0').format(salary.toInt())}'),
              _DetailRow('Bank Name', bankName),
              _DetailRow('Account / IBAN', iban),
              _DetailRow('Education', emp['qualification']?.toString() ?? emp['education']?.toString() ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailSection(
            title: 'PERSONAL DETAILS',
            t: t,
            items: [
              _DetailRow('CNIC / Identification', emp['cnic']?.toString() ?? 'N/A'),
              _DetailRow('Date of Birth', emp['dob']?.toString() ?? 'N/A'),
              _DetailRow('Gender', emp['gender']?.toString() ?? 'N/A'),
              _DetailRow('Relationship Type', emp['relationshipType']?.toString() ?? 'Father'),
              _DetailRow('Contact Phone', emp['phone']?.toString() ?? 'N/A'),
              _DetailRow('Address', emp['address']?.toString() ?? 'N/A'),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Attendance ──────────────────────────────────────────────────────
  Widget _buildAttendanceTab(Map<String, dynamic> emp, RoleThemeData t) {
    final summary = FinanceLocalStorage.getPayrollAttendanceSummary(widget.employeeId, _selectedMonthKey);
    final daysInMonth = (summary['totalDays'] as num?)?.toInt() ?? 30;
    final present = (summary['presentDays'] as num?)?.toDouble() ?? 0.0;
    final lateDays = (summary['lateDays'] as num?)?.toDouble() ?? 0.0;
    final absent = (summary['absentDays'] as num?)?.toDouble() ?? 0.0;
    final paidLeaves = (summary['paidLeaves'] as num?)?.toDouble() ?? 0.0;
    final unpaidLeaves = (summary['unpaidLeaves'] as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Attendance Breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.textPrimary)),
              DropdownButton<String>(
                value: _selectedMonthKey,
                dropdownColor: t.bgCard,
                style: TextStyle(color: t.textPrimary, fontSize: 13),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedMonthKey = val);
                },
                items: List.generate(12, (index) {
                  final dt = DateTime(DateTime.now().year, DateTime.now().month - index, 1);
                  final key = DateFormat('yyyy-MM').format(dt);
                  return DropdownMenuItem(value: key, child: Text(DateFormat('MMMM yyyy').format(dt)));
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildAttendanceMetric('Total Days', '$daysInMonth', Colors.blue, t),
              _buildAttendanceMetric('Present', present.toStringAsFixed(1).replaceAll('.0', ''), Colors.green, t),
              _buildAttendanceMetric('Late Days', lateDays.toStringAsFixed(1).replaceAll('.0', ''), Colors.amber, t),
              _buildAttendanceMetric('Absent Days', absent.toStringAsFixed(1).replaceAll('.0', ''), Colors.redAccent, t),
              _buildAttendanceMetric('Paid Leaves', paidLeaves.toStringAsFixed(1).replaceAll('.0', ''), Colors.teal, t),
              _buildAttendanceMetric('Unpaid Leaves', unpaidLeaves.toStringAsFixed(1).replaceAll('.0', ''), Colors.purple, t),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Leaves & Quotas ─────────────────────────────────────────────────
  Widget _buildLeavesTab(Map<String, dynamic> emp, RoleThemeData t) {
    final usage = FinanceLocalStorage.getLeaveUsage(widget.employeeId, DateTime.now().year);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Leave Quota & Usage (${DateTime.now().year})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.textPrimary)),
          const SizedBox(height: 12),
          _buildLeaveRow('Casual Leaves', usage['casual'] ?? 0.0, 10.0, Colors.blue, t),
          const SizedBox(height: 10),
          _buildLeaveRow('Sick Leaves', usage['sick'] ?? 0.0, 8.0, Colors.orange, t),
          const SizedBox(height: 10),
          _buildLeaveRow('Annual Leaves', usage['annual'] ?? 0.0, 14.0, Colors.green, t),
          const SizedBox(height: 10),
          _buildLeaveRow('Unpaid Leaves', usage['unpaid'] ?? 0.0, 0.0, Colors.purple, t),
        ],
      ),
    );
  }

  // ── Tab 4: History & Audit Ledger ──────────────────────────────────────────
  Widget _buildHistoryTab(Map<String, dynamic> emp, RoleThemeData t) {
    final history = FinanceLocalStorage.getSalaryHistory(widget.employeeId);
    final transfers = FinanceLocalStorage.getTransfersForEmployee(widget.employeeId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Salary History Timeline', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.textPrimary)),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Text('No historical salary adjustments logged.', style: TextStyle(color: t.textTertiary, fontSize: 12))
          else
            ...history.map((h) {
              final amt = (h['amount'] as num?)?.toDouble() ?? 0.0;
              final date = h['effectiveDate']?.toString() ?? 'N/A';
              final reason = h['reason']?.toString() ?? 'Adjustment';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reason, style: TextStyle(fontWeight: FontWeight.bold, color: t.textPrimary, fontSize: 13)),
                        Text('Effective: $date', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                      ],
                    ),
                    Text('PKR ${NumberFormat('#,##0').format(amt.toInt())}', style: TextStyle(fontWeight: FontWeight.bold, color: t.accent, fontSize: 13)),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
          Text('Branch Transfer History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.textPrimary)),
          const SizedBox(height: 8),
          if (transfers.isEmpty)
            Text('No branch transfers recorded.', style: TextStyle(color: t.textTertiary, fontSize: 12))
          else
            ...transfers.map((tr) {
              final from = FinanceLocalStorage.getBranchName(tr['fromBranchId']?.toString() ?? '');
              final to = FinanceLocalStorage.getBranchName(tr['toBranchId']?.toString() ?? '');
              final date = tr['transferDate']?.toString() ?? 'N/A';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                child: Row(
                  children: [
                    Icon(Icons.compare_arrows_rounded, color: t.accent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$from ➔ $to', style: TextStyle(fontWeight: FontWeight.bold, color: t.textPrimary, fontSize: 13)),
                          Text('Date: $date', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── Helper Widgets ────────────────────────────────────────────────────────
  Widget _buildDetailSection({required String title, required RoleThemeData t, required List<_DetailRow> items}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: t.bgRule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t.accent, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          ...items.map((it) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(it.label, style: TextStyle(color: t.textSecondary, fontSize: 12)),
                Text(it.value, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildAttendanceMetric(String label, String value, Color color, RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: t.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildLeaveRow(String label, double used, double total, Color color, RoleThemeData t) {
    final progress = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.bgRule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: t.textPrimary, fontSize: 13)),
              Text('${used.toStringAsFixed(1)} / ${total > 0 ? total.toStringAsFixed(0) : '∞'} Days', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, backgroundColor: t.bgRule, color: color, minHeight: 6),
          ],
        ],
      ),
    );
  }
}

class _DetailRow {
  final String label;
  final String value;
  _DetailRow(this.label, this.value);
}
