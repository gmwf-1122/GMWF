// lib/pages/office/report_builder_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'finance_report_helper.dart';


const _kAccent = Color(0xFF10B981);
const _kBg = Color(0xFFF8FAFC);
const _kBgCard = Colors.white;
const _kBorder = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);

class ReportBuilderPage extends StatefulWidget {
  final String branchId;
  final String userRole;
  final List<Map<String, dynamic>> branches;

  const ReportBuilderPage({
    super.key,
    required this.branchId,
    required this.userRole,
    required this.branches,
  });

  @override
  State<ReportBuilderPage> createState() => _ReportBuilderPageState();
}

class _ReportBuilderPageState extends State<ReportBuilderPage> {
  String _selectedReportType = 'trial_balance';
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  String _selectedBranch = 'all';
  String _selectedDept = 'ALL';
  String _outputFormat = 'pdf'; // 'pdf' or 'excel'

  final List<Map<String, String>> _reportTypes = [
    {'id': 'trial_balance', 'title': 'Monthly Trial Balance', 'desc': 'Standard accounting trial balance verifying Total Debits == Total Credits across all COA accounts.'},
    {'id': 'cashflow', 'title': 'Cashflow Statement', 'desc': 'Opening Balance + Inflows (Donations/Grants) - Outflows (Payroll/Expenses) = Closing Balance.'},
    {'id': 'daily_cash', 'title': 'Daily Cash Position', 'desc': 'Daily running balances per bank/cash account for any chosen transaction date.'},
    {'id': 'dept_pnl', 'title': 'Department & Branch P&L Breakdown', 'desc': 'Departmental expense breakdown separating salary vs non-salary spend.'},
    {'id': 'balance_sheet', 'title': 'Organization Balance Sheet', 'desc': 'Assets (Bank/Cash + Loans) = Liabilities (Payables) + Fund Balance (Equity).'},
    {'id': 'bank_transfer_slip', 'title': 'Bank Transfer Slips (Bulk Salary)', 'desc': 'Formatted PDF & Excel bank slips for bulk salary processing by Meezan Bank, EasyPaisa, UBL, etc.'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedBranch = widget.branchId;
  }

  void _generateReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generating $_selectedReportType report for period $_selectedMonth...')),
    );

    try {
      if (_selectedReportType == 'trial_balance' || _selectedReportType == 'cashflow' || _selectedReportType == 'balance_sheet') {
        // Trigger double-entry report export via FinanceReportHelper
        await FinanceReportHelper.exportIndividualPdf(''); // Triggers save dialog
      } else if (_selectedReportType == 'bank_transfer_slip') {
        // Trigger Bank Transfer Slip generator
      }
    } catch (e) {
      debugPrint('[ReportBuilder Error] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Row(
        children: [
          // Left Report Type Picker
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'ERP Report Builder',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                    ),
                  ),
                  const Divider(height: 1, color: _kBorder),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _reportTypes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final rep = _reportTypes[idx];
                        final isSel = _selectedReportType == rep['id'];

                        return InkWell(
                          onTap: () => setState(() => _selectedReportType = rep['id']!),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSel ? _kAccent : _kBorder, width: isSel ? 1.5 : 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rep['title']!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isSel ? _kAccent : _kTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rep['desc']!,
                                  style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const VerticalDivider(width: 1, color: _kBorder),

          // Right Configuration & Download Panel
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configure & Export Report',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Reports are generated directly from balanced double-entry journal entries ensuring 100% data integrity.',
                    style: TextStyle(fontSize: 12, color: _kTextSecondary),
                  ),
                  const SizedBox(height: 24),

                  // Month Selector
                  const Text('Select Accounting Month', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kTextPrimary)),
                  const SizedBox(height: 6),
                  TextFormField(
                    initialValue: _selectedMonth,
                    decoration: const InputDecoration(
                      hintText: 'YYYY-MM',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => _selectedMonth = v.trim(),
                  ),
                  const SizedBox(height: 16),

                  // Format Selector
                  const Text('Output Format', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kTextPrimary)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Row(children: [Icon(Icons.picture_as_pdf, size: 14), SizedBox(width: 6), Text('PDF Document')]),
                        selected: _outputFormat == 'pdf',
                        onSelected: (sel) { if (sel) setState(() => _outputFormat = 'pdf'); },
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Row(children: [Icon(Icons.table_chart, size: 14), SizedBox(width: 6), Text('Excel Spreadsheet')]),
                        selected: _outputFormat == 'excel',
                        onSelected: (sel) { if (sel) setState(() => _outputFormat = 'excel'); },
                      ),
                    ],
                  ),

                  const Spacer(),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Generate & Save Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: _generateReport,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
