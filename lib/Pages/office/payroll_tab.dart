// lib/pages/office/payroll_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_loans_storage.dart';
import '../../services/permission_service.dart';
import 'shared_widgets.dart';

class PayrollTab extends StatefulWidget {
  final String branchId;
  final String monthKey;
  final ValueChanged<String> onMonthChanged;
  final String userRole;

  const PayrollTab({
    super.key,
    required this.branchId,
    required this.monthKey,
    required this.onMonthChanged,
    required this.userRole,
  });

  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> {
  final TextEditingController _ledgerSearchCtrl = TextEditingController();
  final TextEditingController _payrollSearchCtrl = TextEditingController();
  String _selectedLedgerEmployeeId = 'all';
  bool _showLedger = false;

  // Tracks which payroll rows have their secondary breakdown expanded.
  // Progressive disclosure: collapsed by default, one tap away.
  final Set<String> _expandedRows = {};

  @override
  void dispose() {
    _ledgerSearchCtrl.dispose();
    _payrollSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return Column(
      children: [
        _buildMonthPickerBar(t),
        Expanded(
          child: _showLedger ? _buildLedgerTimelineView(t) : _buildPayrollBoard(t),
        ),
      ],
    );
  }

  Widget _buildMonthPickerBar(RoleThemeData t) {
    final displayDate = DateFormat('yyyy-MM').parse(widget.monthKey);

    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        border: Border(bottom: BorderSide(color: t.bgRule, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: t.bgCardAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.bgRule),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left_rounded, size: 20, color: t.textPrimary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        final prev = DateTime(displayDate.year, displayDate.month - 1);
                        widget.onMonthChanged(DateFormat('yyyy-MM').format(prev));
                      },
                    ),
                    Container(width: 0.5, height: 20, color: t.bgRule),
                    IconButton(
                      icon: Icon(Icons.chevron_right_rounded, size: 20, color: t.textPrimary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: widget.monthKey == DateFormat('yyyy-MM').format(DateTime.now())
                          ? null
                          : () {
                              final next = DateTime(displayDate.year, displayDate.month + 1);
                              widget.onMonthChanged(DateFormat('yyyy-MM').format(next));
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  Icon(Icons.calendar_month_outlined, color: t.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMMM yyyy').format(displayDate),
                    style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
            ],
          ),
          Container(
            height: 34,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: t.bgCardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.bgRule),
            ),
            child: Row(
              children: [
                _buildToggleButton('Board View', !_showLedger, t),
                _buildToggleButton('Ledger Logs', _showLedger, t),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool active, RoleThemeData t) {
    return InkWell(
      onTap: () => setState(() => _showLedger = label == 'Ledger Logs'),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active ? [
            BoxShadow(
              color: t.accent.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : t.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildPayrollBoard(RoleThemeData t) {
    return Column(
      children: [
        Container(
          color: t.bgCard,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: t.bgCardAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.bgRule),
            ),
            child: TextField(
              controller: _payrollSearchCtrl,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search payroll by employee name...',
                hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                prefixIcon: Icon(Icons.search, color: t.textTertiary, size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: FinanceLocalStorage.employeesBox.listenable(),
            builder: (ctx, Box box, _) {
              final query = _payrollSearchCtrl.text.trim().toLowerCase();
              final activeEmployees = FinanceLocalStorage.getEmployees(widget.branchId).where((e) {
                if (e['isActive'] != true) return false;
                if (query.isNotEmpty) {
                  final name = e['name']?.toString().toLowerCase() ?? '';
                  return name.contains(query);
                }
                return true;
              }).toList();

              if (activeEmployees.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline_rounded, size: 48, color: t.textTertiary),
                      const SizedBox(height: 12),
                      Text(
                        query.isNotEmpty ? 'No matching employees found.' : 'No active employees registered.',
                        style: TextStyle(color: t.textTertiary, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return ValueListenableBuilder(
                valueListenable: FinanceLocalStorage.salaryLedgerBox.listenable(),
                builder: (c, Box ledgerBox, _) {
                  return ValueListenableBuilder(
                    valueListenable: FinanceLocalStorage.attendanceBox.listenable(),
                    builder: (c2, Box attBox, _) {
                      // Calculate Aggregate Summaries for the Dashboard Header
                      int paidCount = 0;
                      double disbursedTotal = 0.0;
                      double pendingTotal = 0.0;

                      for (final emp in activeEmployees) {
                        final empId = emp['localId']?.toString() ?? '';
                        final payrollSummary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, widget.monthKey);
                        final baseSalaryEarned = (payrollSummary['baseSalaryEarned'] as num).toDouble();
                        final absenceDeductions = (payrollSummary['absenceDeductions'] as num).toDouble();
                        final holidayBonus = (payrollSummary['holidayBonus'] as num).toDouble();
                        final sundayOvertimeBonus = (payrollSummary['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;
                        final overtimeBonusTotal = holidayBonus + sundayOvertimeBonus;
                        final advance = FinanceLocalStorage.getAdvanceBalance(empId);

                        final payouts = ledgerBox.values.where((val) {
                          if (val is! Map) return false;
                          final entry = Map<String, dynamic>.from(val);
                          return entry['employeeId'] == empId &&
                                 entry['monthKey'] == widget.monthKey &&
                                 entry['type'] == 'payout' &&
                                 entry['isVoided'] != true;
                        }).toList();

                        if (payouts.isNotEmpty) {
                          paidCount++;
                          disbursedTotal += (payouts.first['amount'] as num).toDouble();
                        } else {
                          final estNet = (baseSalaryEarned - absenceDeductions + overtimeBonusTotal).clamp(0.0, double.infinity);
                          pendingTotal += estNet;
                        }
                      }

                      int unpaidCount = activeEmployees.length - paidCount;

                      return Column(
                        children: [
                          // ── PAYROLL DASHBOARD HEADER ──────────────────────
                          // Flat metric cards, no gradient — see redesign plan §3.B.
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: buildMetricCardRow(
                              theme: t,
                              cards: [
                                buildMetricCard(
                                  theme: t,
                                  label: 'Month Disbursement',
                                  value: '$paidCount / ${activeEmployees.length} PAID',
                                  valueColor: Colors.green[600],
                                  caption: '$unpaidCount pending payout',
                                ),
                                buildMetricCard(
                                  theme: t,
                                  label: 'Disbursed Total',
                                  value: 'PKR ${_fmtCurrency(disbursedTotal)}',
                                  valueColor: Colors.green[600],
                                  caption: 'Cleared payout',
                                ),
                                buildMetricCard(
                                  theme: t,
                                  label: 'Pending Total',
                                  value: 'PKR ${_fmtCurrency(pendingTotal)}',
                                  caption: 'Est. required',
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              itemCount: activeEmployees.length,
                              itemBuilder: (ctx, i) {
                                final emp = activeEmployees[i];
                                final empId = emp['localId']?.toString() ?? '';
                                final ps = PermissionService();

                                // Lookup salary for this payroll month
                                final payrollSummary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, widget.monthKey);
                                final baseSalary = (payrollSummary['fullMonthWeightedSalary'] as num).toDouble();
                                final baseSalaryEarned = (payrollSummary['baseSalaryEarned'] as num).toDouble();
                                final absentDays = (payrollSummary['absentDays'] as num).toDouble();
                                final unpaidLeaves = (payrollSummary['unpaidLeaves'] as num).toDouble();
                                final workingDays = (payrollSummary['workingDays'] as num).toDouble();
                                final totalDays = (payrollSummary['totalDays'] as num).toInt();
                                final totalEmployedDays = (payrollSummary['totalEmployedDays'] as num).toInt();
                                final sundayOvertimeDays = (payrollSummary['sundayOvertimeDays'] as num?)?.toDouble() ?? 0.0;
                                final sundayOvertimeBonus = (payrollSummary['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;

                                final absenceDeductions = (payrollSummary['absenceDeductions'] as num).toDouble();
                                final holidayBonus = (payrollSummary['holidayBonus'] as num).toDouble();
                                final overtimeBonusTotal = holidayBonus + sundayOvertimeBonus;

                                final paidDays = totalEmployedDays - absentDays - unpaidLeaves;
                                final paidDaysStr = paidDays.toStringAsFixed(1).replaceAll('.0', '');

                                // Fetch derived advance balance
                                final advance = FinanceLocalStorage.getAdvanceBalance(empId);

                                // Query if payout already processed for this employee in this month
                                final payouts = ledgerBox.values.where((val) {
                                  if (val is! Map) return false;
                                  final entry = Map<String, dynamic>.from(val);
                                  return entry['employeeId'] == empId &&
                                         entry['monthKey'] == widget.monthKey &&
                                         entry['type'] == 'payout' &&
                                         entry['isVoided'] != true;
                                }).toList();

                                final isPaid = payouts.isNotEmpty;
                                final paidAmount = isPaid ? (payouts.first['amount'] as num).toDouble() : 0.0;
                                final netEstimate = (baseSalaryEarned - absenceDeductions + overtimeBonusTotal).clamp(0.0, double.infinity);
                                final netPayDisplay = isPaid ? paidAmount : netEstimate;
                                final isExpanded = _expandedRows.contains(empId);

                                return _buildPayrollRow(
                                  t: t,
                                  ps: ps,
                                  emp: emp,
                                  empId: empId,
                                  isPaid: isPaid,
                                  netPayDisplay: netPayDisplay,
                                  baseSalary: baseSalary,
                                  baseSalaryEarned: baseSalaryEarned,
                                  absenceDeductions: absenceDeductions,
                                  overtimeBonusTotal: overtimeBonusTotal,
                                  totalDays: totalDays,
                                  totalEmployedDays: totalEmployedDays,
                                  workingDays: workingDays,
                                  absentDays: absentDays,
                                  unpaidLeaves: unpaidLeaves,
                                  paidDaysStr: paidDaysStr,
                                  sundayOvertimeDays: sundayOvertimeDays,
                                  advance: advance,
                                  isExpanded: isExpanded,
                                  payouts: payouts,
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Redesigned payroll row ────────────────────────────────────────────────
  // Two-tier layout: name/role + one primary number (Net Pay) up top;
  // everything else collapses behind a "Details" toggle. One primary action
  // ("Process Salary", gold); "Issue Loan"/"Log Repayment" live in a kebab
  // overflow menu since they're occasional, not the main task of this screen.
  Widget _buildPayrollRow({
    required RoleThemeData t,
    required PermissionService ps,
    required Map<String, dynamic> emp,
    required String empId,
    required bool isPaid,
    required double netPayDisplay,
    required double baseSalary,
    required double baseSalaryEarned,
    required double absenceDeductions,
    required double overtimeBonusTotal,
    required int totalDays,
    required int totalEmployedDays,
    required double workingDays,
    required double absentDays,
    required double unpaidLeaves,
    required String paidDaysStr,
    required double sundayOvertimeDays,
    required double advance,
    required bool isExpanded,
    required List payouts,
  }) {
    final name = emp['name']?.toString() ?? '';
    final role = emp['role']?.toString() ?? '';
    final dept = emp['department']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.bgRule, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top line: identity + status pill ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      buildInitialsAvatar(name: name, theme: t, radius: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                            Text('$role • $dept', style: TextStyle(color: t.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                buildStatusPill(
                  theme: t,
                  label: isPaid ? 'PAID' : 'UNPAID',
                  variant: isPaid ? StatusPillVariant.success : StatusPillVariant.warning,
                  icon: isPaid ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── The one number that matters: Net Pay ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isPaid ? 'NET PAID' : 'NET ESTIMATE', style: TextStyle(color: t.textTertiary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                    const SizedBox(height: 3),
                    Text(
                      'PKR ${_fmtCurrency(netPayDisplay)}',
                      style: TextStyle(color: isPaid ? Colors.green[600] : t.textPrimary, fontSize: 22, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _expandedRows.remove(empId);
                    } else {
                      _expandedRows.add(empId);
                    }
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(isExpanded ? 'Hide details' : 'Details', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                        Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: t.accent, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Secondary breakdown, one tap away (progressive disclosure) ──
            if (isExpanded) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.bgCardAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.bgRule),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBreakdownColumn('Base Salary', baseSalaryEarned, false, t),
                        _buildBreakdownColumn('Deductions', absenceDeductions, true, t),
                        _buildBreakdownColumn('Bonuses/OT', overtimeBonusTotal, false, t),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Divider(color: t.bgRule, height: 1),
                    const SizedBox(height: 10),
                    Text(
                      '${totalEmployedDays < totalDays ? "Contract: $totalEmployedDays/$totalDays days" : "Full Month ($totalDays days)"} • Pay for $paidDaysStr days • worked $workingDays d • $absentDays abs • $unpaidLeaves unpaid lv${sundayOvertimeDays > 0 ? " • sun OT: $sundayOvertimeDays" : ""}',
                      style: TextStyle(color: t.textTertiary, fontSize: 11),
                    ),
                    if (!isPaid && totalEmployedDays < totalDays) ...[
                      const SizedBox(height: 4),
                      Text('Salary Rate: PKR ${_fmtCurrency(baseSalary)}', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ],

            // ── Advance pill, only when non-zero ──
            if (advance > 0) ...[
              const SizedBox(height: 10),
              buildStatusPill(
                theme: t,
                label: 'Advance: PKR ${_fmtCurrency(advance)}',
                variant: StatusPillVariant.warning,
                icon: Icons.money_off_rounded,
              ),
            ],

            const SizedBox(height: 12),

            // ── One primary action + overflow for occasional actions ──
            if (!isPaid) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.payment, size: 14),
                      label: const Text('Process Salary', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _openPayoutDialog(context, empId, name, baseSalary, advance),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: t.bgRule),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: t.textSecondary, size: 18),
                      color: t.bgCardAlt,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onSelected: (val) {
                        if (val == 'loan') {
                          _openIssueLoanDialog(context, empId, name);
                        } else if (val == 'repay') {
                          _openLogRepaymentDialog(context, empId, name);
                        }
                      },
                      itemBuilder: (menuCtx) => [
                        PopupMenuItem(
                          value: 'loan',
                          child: Row(
                            children: [
                              Icon(Icons.add_card, size: 16, color: t.textSecondary),
                              const SizedBox(width: 8),
                              Text('Issue Loan', style: TextStyle(color: t.textPrimary, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (advance > 0)
                          PopupMenuItem(
                            value: 'repay',
                            child: Row(
                              children: [
                                Icon(Icons.payments_outlined, size: 16, color: t.textSecondary),
                                const SizedBox(width: 8),
                                Text('Log Repayment', style: TextStyle(color: t.textPrimary, fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (ps.hasPermission(widget.userRole, AppPermission.voidFinanceRecord)) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.danger,
                    side: BorderSide(color: t.danger, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.undo, size: 14),
                  label: const Text('Reverse Payout (Mark Unpaid)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () => _showVoidDialog(context, payouts.first['localId']),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmtCurrency(double amt) {
    return NumberFormat('#,###').format(amt);
  }

  Widget _buildLedgerTimelineView(RoleThemeData t) {
    final employees = FinanceLocalStorage.getEmployees(widget.branchId);
    final dropdownItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('All Employees')),
    ];
    for (final emp in employees) {
      final id = emp['localId']?.toString() ?? '';
      final name = emp['name']?.toString() ?? 'Unknown';
      final role = emp['role']?.toString() ?? 'Staff';
      dropdownItems.add(DropdownMenuItem(
        value: id,
        child: Text('$name ($role)'),
      ));
    }

    return Column(
      children: [
        Container(
          color: t.bgCard,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            children: [
              Container(
                height: 38,
                decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                child: TextField(
                  controller: _ledgerSearchCtrl,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search ledger logs...',
                    hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                    prefixIcon: Icon(Icons.search, color: t.textTertiary, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLedgerEmployeeId,
                    dropdownColor: t.bgCard,
                    isExpanded: true,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    items: dropdownItems,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedLedgerEmployeeId = val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: FinanceLocalStorage.salaryLedgerBox.listenable(),
            builder: (ctx, Box box, _) {
              final query = _ledgerSearchCtrl.text.trim().toLowerCase();
              final entries = FinanceLocalStorage.getLedgerEntries(widget.branchId).where((e) {
                if (_selectedLedgerEmployeeId != 'all' && e['employeeId'] != _selectedLedgerEmployeeId) {
                  return false;
                }
                if (query.isNotEmpty) {
                  final name = e['employeeName']?.toString().toLowerCase() ?? '';
                  final note = e['note']?.toString().toLowerCase() ?? '';
                  final type = e['type']?.toString().toLowerCase() ?? '';
                  return name.contains(query) || note.contains(query) || type.contains(query);
                }
                return true;
              }).toList();

              if (entries.isEmpty) {
                return Center(child: Text('No payroll records logged.', style: TextStyle(color: t.textTertiary, fontSize: 12)));
              }

              final ps = PermissionService();

              return ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: entries.length,
                itemBuilder: (c, idx) {
                  final e = entries[idx];
                  final isVoid = e['isVoided'] == true;
                  final type = e['type']?.toString();
                  final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
                  final date = DateFormat('EEE, dd MMM yyyy').format(DateTime.parse(e['date']));

                  Color amountColor = Colors.green;
                  String typeLabel = 'Salary Payout';
                  IconData icon = Icons.payments_outlined;
                  StatusPillVariant typeVariant = StatusPillVariant.success;

                  if (type == 'advance_payment') {
                    amountColor = Colors.orange;
                    typeLabel = 'Advance Issue';
                    icon = Icons.add_card;
                    typeVariant = StatusPillVariant.warning;
                  } else if (type == 'arrears_payment') {
                    amountColor = Colors.purple;
                    typeLabel = 'Arrears Paid';
                    icon = Icons.redo_outlined;
                    typeVariant = StatusPillVariant.pro;
                  }

                  return Card(
                    color: t.bgCard,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.bgRule)),
                    child: Opacity(
                      opacity: isVoid ? 0.45 : 1.0,
                      child: Tooltip(
                        message: isVoid ? 'Voided by ${e['voidedBy']}: ${e['voidReason']}' : '',
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: isVoid ? t.bgRule : amountColor.withOpacity(0.12),
                            child: Icon(icon, color: isVoid ? t.textTertiary : amountColor, size: 18),
                          ),
                          title: Row(
                            children: [
                              Text(e['employeeName'] ?? '', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, decoration: isVoid ? TextDecoration.lineThrough : null)),
                              const SizedBox(width: 8),
                              buildStatusPill(theme: t, label: typeLabel, variant: isVoid ? StatusPillVariant.accent : typeVariant),
                            ],
                          ),
                          subtitle: Text(
                            'Period: ${e['monthKey']} • Date: $date\n${e['note'] ?? ""}',
                            style: TextStyle(color: t.textTertiary, fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'PKR ${NumberFormat('#,###').format(amount)}',
                                style: TextStyle(color: isVoid ? t.textTertiary : amountColor, fontWeight: FontWeight.bold, fontSize: 13, decoration: isVoid ? TextDecoration.lineThrough : null),
                              ),
                              if (!isVoid && ps.hasPermission(widget.userRole, AppPermission.voidFinanceRecord)) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _showVoidDialog(context, e['localId']),
                                  child: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 18),
                                )
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showVoidDialog(BuildContext context, String recordId) {
    final t = RoleThemeScope.dataOf(context);
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: t.bgCard,
          title: Text('Void Financial Record', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WARNING: Voiding a financial ledger record will immediately adjust the employee\'s advance balance. This action is audited and cannot be undone.',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                style: TextStyle(color: t.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Reason for Voiding *',
                  labelStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.bgRule)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Please enter a reason for voiding this transaction.'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ));
                  return;
                }
                try {
                  final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

                  await FinanceLocalStorage.voidLedgerEntry(
                    branchId: widget.branchId,
                    recordId: recordId,
                    voidedBy: curUser,
                    voidReason: reasonController.text.trim(),
                    approvedBy: curUser,
                  );

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Transaction voided and ledger recalculated.'),
                      backgroundColor: t.accent,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                } catch (e) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Failed: $e'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
              child: const Text('Void Transaction', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _openIssueLoanDialog(BuildContext context, String employeeId, String employeeName) {
    final t = RoleThemeScope.dataOf(context);
    final amountController = TextEditingController();
    final usualController = TextEditingController();
    final noteController = TextEditingController();
    String repaymentType = 'fixed';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return AlertDialog(
              backgroundColor: t.bgCard,
              title: Text('Issue Loan - $employeeName', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildFormField(
                    controller: amountController,
                    label: 'Loan Amount (PKR) *',
                    icon: Icons.payments,
                    theme: t,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 10),
                  buildDropdownField(
                    label: 'Repayment Type *',
                    value: repaymentType == 'fixed' ? 'Fixed Monthly Installment' : 'Flexible (pay as able)',
                    items: const ['Fixed Monthly Installment', 'Flexible (pay as able)'],
                    onChanged: (val) => setSheetState(() {
                      repaymentType = val == 'Fixed Monthly Installment' ? 'fixed' : 'flexible';
                    }),
                    theme: t,
                  ),
                  const SizedBox(height: 10),
                  buildFormField(
                    controller: usualController,
                    label: repaymentType == 'fixed'
                        ? 'Monthly Installment (PKR) *'
                        : 'Usual Repayment Amount (PKR, optional reference)',
                    icon: Icons.calendar_view_month,
                    theme: t,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 10),
                  buildFormField(
                    controller: noteController,
                    label: 'Reason / Notes',
                    icon: Icons.note_alt_outlined,
                    theme: t,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'This loan is tracked separately and never reduces salary payouts.\nRepayments are logged on their own via "Log Repayment".',
                      style: TextStyle(color: t.textTertiary, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: t.accent),
                  onPressed: () async {
                    final amt = double.tryParse(amountController.text.trim());
                    if (amt == null || amt <= 0) {
                      showCustomSnackBar(sheetCtx, 'Please enter a valid loan amount.', error: true);
                      return;
                    }
                    final usual = double.tryParse(usualController.text.trim()) ?? 0.0;
                    if (repaymentType == 'fixed' && usual <= 0) {
                      showCustomSnackBar(sheetCtx, 'Please enter the monthly installment amount.', error: true);
                      return;
                    }
                    try {
                      final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
                      await FinanceLoansStorage.createLoan(
                        branchId: widget.branchId,
                        employeeId: employeeId,
                        employeeName: employeeName,
                        principal: amt,
                        repaymentType: repaymentType,
                        usualInstallment: usual,
                        reason: noteController.text.trim(),
                        performedBy: curUser,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showCustomSnackBar(context, 'Loan of PKR ${NumberFormat('#,###').format(amt)} issued to $employeeName');
                      }
                    } catch (e) {
                      showCustomSnackBar(sheetCtx, 'Failed: $e', error: true);
                    }
                  },
                  child: const Text('Issue Loan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openLogRepaymentDialog(BuildContext context, String employeeId, String employeeName) {
    final t = RoleThemeScope.dataOf(context);
    final loans = FinanceLoansStorage.getActiveLoansForEmployee(employeeId);

    if (loans.isEmpty) {
      showCustomSnackBar(context, '$employeeName has no active loans.', error: true);
      return;
    }

    String selectedLoanId = loans.first['localId'].toString();
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final selectedLoan = loans.firstWhere((l) => l['localId'] == selectedLoanId);
            final balance = FinanceLoansStorage.getLoanBalance(selectedLoan);

            return AlertDialog(
              backgroundColor: t.bgCard,
              title: Text('Log Repayment - $employeeName', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loans.length > 1)
                    buildDropdownField(
                      label: 'Which Loan?',
                      value: '${selectedLoan['reason']} (PKR ${NumberFormat('#,###').format(balance)} left)',
                      items: loans.map((l) {
                        final b = FinanceLoansStorage.getLoanBalance(l);
                        return '${l['reason']} (PKR ${NumberFormat('#,###').format(b)} left)';
                      }).toList(),
                      onChanged: (val) {
                        final idx = loans.indexWhere((l) {
                          final b = FinanceLoansStorage.getLoanBalance(l);
                          return '${l['reason']} (PKR ${NumberFormat('#,###').format(b)} left)' == val;
                        });
                        if (idx != -1) setSheetState(() => selectedLoanId = loans[idx]['localId'].toString());
                      },
                      theme: t,
                    ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Outstanding Balance', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                        Text('PKR ${NumberFormat('#,###').format(balance)}',
                            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (selectedLoan['repaymentType'] == 'fixed')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Usual installment: PKR ${NumberFormat('#,###').format((selectedLoan['usualInstallment'] as num?)?.toDouble() ?? 0.0)}/month',
                        style: TextStyle(color: t.textTertiary, fontSize: 11),
                      ),
                    ),
                  buildFormField(
                    controller: amountController,
                    label: 'Amount Paid Today (PKR) *',
                    icon: Icons.payments,
                    theme: t,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 10),
                  buildFormField(
                    controller: noteController,
                    label: 'Note (optional)',
                    icon: Icons.note_alt_outlined,
                    theme: t,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: t.accent),
                  onPressed: () async {
                    final amt = double.tryParse(amountController.text.trim());
                    if (amt == null || amt <= 0) {
                      showCustomSnackBar(sheetCtx, 'Please enter a valid amount.', error: true);
                      return;
                    }
                    try {
                      final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
                      await FinanceLoansStorage.recordPayment(
                        loanId: selectedLoanId,
                        amount: amt,
                        note: noteController.text.trim(),
                        performedBy: curUser,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showCustomSnackBar(context, 'Repayment of PKR ${NumberFormat('#,###').format(amt)} logged.');
                      }
                    } catch (e) {
                      showCustomSnackBar(sheetCtx, 'Failed: $e', error: true);
                    }
                  },
                  child: const Text('Log Repayment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openPayoutDialog(
    BuildContext context,
    String employeeId,
    String employeeName,
    double baseSalary,
    double advanceBalance,
  ) {
    final t = RoleThemeScope.dataOf(context);

    // Compute payroll attendance summaries, including holidays and absence counts.
    final payrollSummary = FinanceLocalStorage.getPayrollAttendanceSummary(employeeId, widget.monthKey);
    final baseSalaryWeighted = (payrollSummary['fullMonthWeightedSalary'] as num).toDouble();
    final baseSalaryEarned = (payrollSummary['baseSalaryEarned'] as num).toDouble();
    final absentDays = (payrollSummary['absentDays'] as num).toDouble();
    final unpaidLeaves = (payrollSummary['unpaidLeaves'] as num).toDouble();
    final workingDays = (payrollSummary['workingDays'] as num).toDouble();
    final paidLeaves = (payrollSummary['paidLeaves'] as num).toDouble();
    final holidayWorkedDays = (payrollSummary['holidayWorkedDays'] as num).toDouble();
    final holidayCount = (payrollSummary['holidayCount'] as num).toInt();
    final totalDays = (payrollSummary['totalDays'] as num).toInt();
    final totalEmployedDays = (payrollSummary['totalEmployedDays'] as num).toInt();
    final sundayOvertimeDays = (payrollSummary['sundayOvertimeDays'] as num?)?.toDouble() ?? 0.0;
    final sundayOvertimeBonus = (payrollSummary['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;

    // Daily rate for average reference display
    final dailyRate = baseSalaryWeighted / totalDays;
    final absenceDeductions = (payrollSummary['absenceDeductions'] as num).toDouble();
    final holidayBonus = (payrollSummary['holidayBonus'] as num).toDouble();
    final overtimeBonusTotal = holidayBonus + sundayOvertimeBonus;

    final emp = FinanceLocalStorage.getEmployee(employeeId);
    final isCash = emp?['bankName'] == 'Cash' || emp?['bankName'] == null;
    String paymentMethod = isCash ? 'cash' : 'bank_transfer';

    // Controllers
    final otherDeductionsCtrl = TextEditingController(text: '0');
    final arrearsCtrl = TextEditingController(text: '0');
    final overtimeBonusCtrl = TextEditingController(text: overtimeBonusTotal.toStringAsFixed(0));
    final noteCtrl = TextEditingController();

    double netPaid = baseSalaryEarned - absenceDeductions + overtimeBonusTotal;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            void updateCalculations() {
              final otherDed = double.tryParse(otherDeductionsCtrl.text) ?? 0.0;
              final arrs = double.tryParse(arrearsCtrl.text) ?? 0.0;
              final otBonus = double.tryParse(overtimeBonusCtrl.text) ?? 0.0;

              setSheetState(() {
                netPaid = (baseSalaryEarned - absenceDeductions - otherDed + arrs + otBonus).clamp(0.0, double.infinity);
              });
            }

            return Container(
              padding: EdgeInsets.only(top: 20, left: 16, right: 16, bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Process Payroll Payout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Employee: $employeeName', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Payroll Period: ${widget.monthKey}', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                    const SizedBox(height: 14),
                    if (totalEmployedDays < totalDays) ...[
                      _buildCalculationRow('Contract Base Salary', baseSalaryWeighted, false, t),
                      _buildCalculationRow('Prorated Base Salary (Employed $totalEmployedDays/$totalDays days)', baseSalaryEarned, false, t),
                    ] else ...[
                      _buildCalculationRow('Base Salary', baseSalaryWeighted, false, t),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Automatically Detected Days', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                          Text('${totalEmployedDays < totalDays ? "Employed: $totalEmployedDays" : "Total: $totalDays"} | Worked: $workingDays | Paid Leaves: $paidLeaves', style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    _buildCalculationRow('Reference Salary Rate Per Day', dailyRate, false, t),
                    _buildCalculationRow('Absence Deductions (${absentDays + unpaidLeaves} days absent/unpaid)', absenceDeductions, true, t),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Overtime & Holiday details', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                          Text('Holidays: $holidayCount | Worked: $holidayWorkedDays | Sun OT: $sundayOvertimeDays', style: TextStyle(color: t.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    buildFormField(
                      controller: overtimeBonusCtrl,
                      label: 'Overtime & Holiday Bonus (PKR)',
                      icon: Icons.star_border,
                      theme: t,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => updateCalculations(),
                    ),
                    const SizedBox(height: 10),
                    Divider(color: t.bgRule, height: 1),
                    const SizedBox(height: 14),

                    // Input: Other deductions
                    buildFormField(
                      controller: otherDeductionsCtrl,
                      label: 'Other Deductions (Fine, tax, etc.)',
                      icon: Icons.money_off,
                      theme: t,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => updateCalculations(),
                    ),

                    // Input: Arrears adjustment
                    buildFormField(
                      controller: arrearsCtrl,
                      label: 'Arrears / Bonuses Adjustment (Arrears add to net paid)',
                      icon: Icons.add_card,
                      theme: t,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => updateCalculations(),
                    ),

                    buildDropdownField(
                      label: 'Payment Method *',
                      value: paymentMethod == 'cash' ? 'Cash' : (paymentMethod == 'bank_transfer' ? 'Bank Transfer' : 'Cheque'),
                      items: ['Cash', 'Bank Transfer', 'Cheque'],
                      onChanged: (val) => setSheetState(() {
                        if (val == 'Cash') paymentMethod = 'cash';
                        if (val == 'Bank Transfer') paymentMethod = 'bank_transfer';
                        if (val == 'Cheque') paymentMethod = 'cheque';
                      }),
                      theme: t,
                    ),

                    const SizedBox(height: 10),
                    buildFormField(
                      controller: noteCtrl,
                      label: 'Payroll Remarks / Notes',
                      icon: Icons.note_alt_outlined,
                      theme: t,
                      maxLines: 2,
                    ),

                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('NET PAID SALARY', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            'PKR ${NumberFormat('#,###').format(netPaid)}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final otherDed = double.tryParse(otherDeductionsCtrl.text.trim()) ?? 0.0;
                        final arrs = double.tryParse(arrearsCtrl.text.trim()) ?? 0.0;
                        final otBonus = double.tryParse(overtimeBonusCtrl.text.trim()) ?? 0.0;

                        // Check if already paid to prevent duplicate payouts
                        final doubleCheckPaid = FinanceLocalStorage.salaryLedgerBox.values.any((val) {
                          if (val is! Map) return false;
                          final entry = Map<String, dynamic>.from(val);
                          return entry['employeeId'] == employeeId &&
                                 entry['monthKey'] == widget.monthKey &&
                                 entry['type'] == 'payout' &&
                                 entry['isVoided'] != true;
                        });

                        if (doubleCheckPaid) {
                          showCustomSnackBar(sheetCtx, 'Salary has already been processed for this month.', error: true);
                          return;
                        }

                        // Double confirmation dialog with payout breakdown
                        final confirm = await showDialog<bool>(
                          context: sheetCtx,
                          builder: (confirmCtx) {
                            return AlertDialog(
                              backgroundColor: t.bgCard,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: Text('Confirm Salary Payout', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Are you sure you want to disburse salary for $employeeName?', style: TextStyle(color: t.textSecondary, fontSize: 13)),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.bgRule)),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Base Salary Earned:', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                            Text('PKR ${NumberFormat('#,###').format(baseSalaryEarned)}', style: TextStyle(color: t.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        if (absenceDeductions > 0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Absence Deductions:', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                              Text('- PKR ${NumberFormat('#,###').format(absenceDeductions)}', style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                        if (otherDed > 0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Other Deductions:', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                              Text('- PKR ${NumberFormat('#,###').format(otherDed)}', style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                        if (arrs > 0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Arrears / Adjustment:', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                              Text('+ PKR ${NumberFormat('#,###').format(arrs)}', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                        if (otBonus > 0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('OT & Holiday Bonus:', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                              Text('+ PKR ${NumberFormat('#,###').format(otBonus)}', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Divider(color: t.bgRule, height: 1),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Net Disbursed Amount:', style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                                            Text('PKR ${NumberFormat('#,###').format(netPaid)}', style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(confirmCtx, false),
                                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => Navigator.pop(confirmCtx, true),
                                  child: const Text('Confirm & Disburse', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            );
                          },
                        );

                        if (confirm != true) return;

                        try {
                          final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

                          final ledgerData = {
                            'employeeId': employeeId,
                            'employeeName': employeeName,
                            'type': 'payout',
                            'amount': netPaid,
                            'monthKey': widget.monthKey,
                            'date': DateTime.now().toIso8601String(),
                            'advanceDeductions': 0.0,
                            'absenceDeductions': absenceDeductions,
                            'holidayBonus': otBonus,
                            'holidayWorkedDays': holidayWorkedDays,
                            'sundayOvertimeDays': sundayOvertimeDays,
                            'sundayOvertimeBonus': 0.0,
                            'baseSalaryWeighted': baseSalaryWeighted,
                            'baseSalaryEarned': baseSalaryEarned,
                            'otherDeductions': otherDed,
                            'advanceAdded': 0.0,
                            'paymentMethod': paymentMethod,
                            'note': noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : 'Monthly salary processed.',
                          };

                          await FinanceLocalStorage.saveLedgerEntry(
                            branchId: widget.branchId,
                            data: ledgerData,
                            performedBy: curUser,
                          );

                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx);
                            showCustomSnackBar(context, 'Salary processed successfully for $employeeName. Net Paid: PKR ${NumberFormat('#,###').format(netPaid)}');
                          }
                        } catch (e) {
                          showCustomSnackBar(sheetCtx, 'Failed: $e', error: true);
                        }
                      },

                      child: const Text('Disburse Payout', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCalculationRow(String label, double amount, bool isDeduction, RoleThemeData t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 12)),
          Text(
            '${isDeduction ? "-" : ""} PKR ${NumberFormat('#,###').format(amount)}',
            style: TextStyle(color: isDeduction ? Colors.red : t.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownColumn(
    String label,
    double amount,
    bool isDeduction,
    RoleThemeData t, {
    Color? highlightColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: t.textTertiary, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          '${isDeduction ? "-" : ""}PKR ${NumberFormat('#,###').format(amount)}',
          style: TextStyle(
            color: highlightColor ?? (isDeduction ? Colors.red[400] : t.textPrimary),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}