// lib/pages/office/employee_report_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_loans_storage.dart';
import 'finance_report_helper.dart';

class EmployeeReportPage extends StatefulWidget {
  final String employeeId;

  const EmployeeReportPage({super.key, required this.employeeId});

  @override
  State<EmployeeReportPage> createState() => _EmployeeReportPageState();
}

class _EmployeeReportPageState extends State<EmployeeReportPage> {
  String _monthKey = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final emp = FinanceLocalStorage.getEmployee(widget.employeeId);

    if (emp == null) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(title: const Text('Employee Report')),
        body: const Center(child: Text('Employee not found.')),
      );
    }

    final summary = FinanceLocalStorage.getPayrollAttendanceSummary(widget.employeeId, _monthKey);
    final loans = FinanceLoansStorage.getLoansForEmployee(widget.employeeId);
    final outstanding = FinanceLoansStorage.getOutstandingBalance(widget.employeeId);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bgCard,
        elevation: 0,
        title: Text(emp['name']?.toString() ?? 'Employee Report', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: t.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf_outlined, color: t.accent),
            tooltip: 'Export PDF',
            onPressed: () => FinanceReportHelper.exportIndividualPdf(widget.employeeId),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileCard(emp, t),
          const SizedBox(height: 16),
          _buildMonthPicker(t),
          const SizedBox(height: 8),
          _buildEarningsCard(summary, t),
          const SizedBox(height: 16),
          _buildLoansSection(loans, outstanding, t),
        ],
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> emp, RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.bgRule)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: t.accentMuted,
            child: Text(
              (emp['name']?.toString() ?? '?').isNotEmpty ? emp['name'].toString()[0].toUpperCase() : '?',
              style: TextStyle(color: t.accent, fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp['name']?.toString() ?? '', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text('${emp['role']} \u2022 ${emp['department']}', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text('CNIC: ${emp['cnic'] ?? 'N/A'} \u2022 ${emp['phone'] ?? 'N/A'}', style: TextStyle(color: t.textTertiary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthPicker(RoleThemeData t) {
    final parsed = DateFormat('yyyy-MM').parse(_monthKey);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() {
            final prev = DateTime(parsed.year, parsed.month - 1, 1);
            _monthKey = DateFormat('yyyy-MM').format(prev);
          }),
        ),
        Text(DateFormat('MMMM yyyy').format(parsed), style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _monthKey == DateFormat('yyyy-MM').format(DateTime.now())
              ? null
              : () => setState(() {
                    final next = DateTime(parsed.year, parsed.month + 1, 1);
                    _monthKey = DateFormat('yyyy-MM').format(next);
                  }),
        ),
      ],
    );
  }

  Widget _buildEarningsCard(Map<String, dynamic> s, RoleThemeData t) {
    final earned = (s['baseSalaryEarned'] as num).toDouble();
    final deductions = (s['absenceDeductions'] as num).toDouble();
    final holidayBonus = (s['holidayBonus'] as num).toDouble();
    final sunBonus = (s['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;
    final net = (earned - deductions + holidayBonus + sunBonus).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.bgRule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EARNINGS THIS MONTH', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 10),
          _row('Present days', '${s['workingDays']}', t),
          _row('Absent days', '${s['absentDays']}', t),
          _row('Paid leaves', '${s['paidLeaves']}', t),
          _row('Unpaid leaves', '${s['unpaidLeaves']}', t),
          _row('Holiday days worked', '${s['holidayWorkedDays']}', t),
          _row('Sunday overtime days', '${s['sundayOvertimeDays']}', t),
          const Divider(height: 20),
          _row('Base earned', 'PKR ${NumberFormat('#,###').format(earned)}', t),
          _row('Absence deductions', '- PKR ${NumberFormat('#,###').format(deductions)}', t, color: Colors.red),
          _row('Holiday bonus', '+ PKR ${NumberFormat('#,###').format(holidayBonus)}', t, color: Colors.green),
          _row('Sunday OT bonus', '+ PKR ${NumberFormat('#,###').format(sunBonus)}', t, color: Colors.green),
          const Divider(height: 20),
          _row('Net earned so far', 'PKR ${NumberFormat('#,###').format(net)}', t, bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, RoleThemeData t, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 12)),
          Text(value, style: TextStyle(color: color ?? t.textPrimary, fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildLoansSection(List<Map<String, dynamic>> loans, double outstanding, RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.bgRule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LOANS & ADVANCES', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text('Outstanding: PKR ${NumberFormat('#,###').format(outstanding)}',
                  style: TextStyle(color: outstanding > 0 ? Colors.orange : t.textTertiary, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          if (loans.isEmpty)
            Text('No loans recorded.', style: TextStyle(color: t.textTertiary, fontSize: 12))
          else
            ...loans.map((loan) {
              final balance = FinanceLoansStorage.getLoanBalance(loan);
              final payments = (loan['payments'] as List? ?? []);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('PKR ${NumberFormat('#,###').format((loan['principal'] as num).toDouble())} \u2022 ${loan['repaymentType']}',
                            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(loan['status'] == 'closed' ? 'PAID OFF' : 'Balance: PKR ${NumberFormat('#,###').format(balance)}',
                            style: TextStyle(color: loan['status'] == 'closed' ? Colors.green : Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Text(loan['reason']?.toString() ?? '', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                    if (payments.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...payments.where((p) => p['isVoided'] != true).map((p) {
                        final pm = Map<String, dynamic>.from(p as Map);
                        return Text(
                          '\u2022 ${DateFormat('yyyy-MM-dd').format(DateTime.parse(pm['date']))}: PKR ${NumberFormat('#,###').format((pm['amount'] as num).toDouble())}',
                          style: TextStyle(color: t.textSecondary, fontSize: 11),
                        );
                      }),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
