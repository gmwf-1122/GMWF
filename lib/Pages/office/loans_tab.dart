// lib/pages/office/loans_tab.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../services/local_storage_service.dart';
import '../../services/finance_loans_storage.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_ledger_storage.dart';
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

class LoansTab extends StatefulWidget {
  final String branchId;
  final String userRole;
  final String departmentFilter;

  const LoansTab({
    super.key,
    required this.branchId,
    required this.userRole,
    this.departmentFilter = 'all',
  });

  @override
  State<LoansTab> createState() => _LoansTabState();
}

class _LoansTabState extends State<LoansTab> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedBranchFilter = 'all';
  String _selectedDeptFilter = 'all';
  Map<String, dynamic>? _selectedLoan;

  bool get _isBranchScopedUser {
    if (widget.branchId.isNotEmpty && widget.branchId != 'all') return true;
    if (Hive.isBoxOpen('local_users')) {
      final curUser = Hive.box('local_users').values.firstOrNull;
      if (curUser is Map) {
        final r = (curUser['role']?.toString() ?? '').toLowerCase().trim();
        if (r.contains('branch manager') || r.contains('branch_manager') || r == 'bm' || r == 'supervisor') {
          return true;
        }
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _selectedDeptFilter = widget.departmentFilter;
    if (_isBranchScopedUser) {
      _selectedBranchFilter = widget.branchId.isNotEmpty ? widget.branchId : 'karachi';
    }
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase().trim());
    });
  }

  @override
  void didUpdateWidget(LoansTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isBranchScopedUser) {
      _selectedBranchFilter = widget.branchId.isNotEmpty ? widget.branchId : 'karachi';
    } else if (oldWidget.branchId != widget.branchId) {
      _selectedBranchFilter = 'all';
      _selectedDeptFilter = widget.departmentFilter;
    } else if (oldWidget.departmentFilter != widget.departmentFilter) {
      _selectedDeptFilter = widget.departmentFilter;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatPaisa(int paisa) {
    return NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0).format(paisa / 100);
  }

  int _parsePaisa(String value) {
    final clean = value.replaceAll(RegExp(r'[^\d.]'), '');
    final val = double.tryParse(clean) ?? 0.0;
    return (val * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final permissionService = PermissionService();
    final loanAccess = permissionService.getLoanAccess(widget.userRole);

    return Scaffold(
      backgroundColor: _kBg,
      body: Row(
        children: [
          // Left Sidebar list of loans
          Expanded(
            flex: 3,
            child: _buildLoansList(loanAccess),
          ),
          const VerticalDivider(width: 1, color: _kBorder),
          // Right detail panel
          Expanded(
            flex: 4,
            child: _buildLoanDetails(loanAccess),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final allEmployees = FinanceLocalStorage.getEmployees(widget.branchId);
    final depts = allEmployees
        .map((e) => e['department']?.toString() ?? 'Other')
        .map((dept) => dept.trim().isEmpty ? 'Other' : dept.trim())
        .where((dept) => dept.isNotEmpty);
    final sortedDepts = FinanceLedgerStorage.sortDepartmentsCanonical(depts);
    final deptOptions = ['all', ...sortedDepts];

    final branchesBox = Hive.box(LocalStorageService.branchesBox);
    final branchesList = branchesBox.values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    final branchNames = {
      'all': 'All Branches',
      for (final b in branchesList)
        b['id']?.toString() ?? '': b['name']?.toString() ?? (b['id']?.toString() ?? '')
    };
    final hasBranchFilter = widget.branchId == 'all';

    String safeDeptFilter = _selectedDeptFilter;
    if (!deptOptions.contains(safeDeptFilter)) {
      final matched = deptOptions.firstWhere(
        (d) => d.toLowerCase() == safeDeptFilter.toLowerCase(),
        orElse: () => 'all',
      );
      safeDeptFilter = matched;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          if (hasBranchFilter) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BRANCH',
                    style: TextStyle(
                      color: _kTextTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _isBranchScopedUser ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _isBranchScopedUser ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0)),
                    ),
                    child: _isBranchScopedUser ? Row(
                      children: [
                        const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            branchNames[_selectedBranchFilter] ?? _selectedBranchFilter.toUpperCase(),
                            style: const TextStyle(color: Color(0xFF064E3B), fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ) : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBranchFilter,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6B7280), size: 18),
                        style: const TextStyle(color: _kTextPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedBranchFilter = val);
                          }
                        },
                        items: branchNames.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEPARTMENT',
                  style: TextStyle(
                    color: _kTextTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: safeDeptFilter,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6B7280), size: 18),
                      style: const TextStyle(color: _kTextPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedDeptFilter = val);
                        }
                      },
                      items: deptOptions.map((dept) {
                        return DropdownMenuItem<String>(
                          value: dept,
                          child: Text(dept == 'all' ? 'All Departments' : dept, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoansList(FinanceAccess access) {
    final allLoans = FinanceLoansStorage.getAllLoansForBranch(widget.branchId, activeOnly: false);
    final filtered = allLoans.where((loan) {
      final name = (loan['employeeName'] ?? '').toString().toLowerCase();
      if (!name.contains(_searchQuery)) return false;

      if (_selectedBranchFilter != 'all') {
        final empId = loan['employeeId'] as String;
        final emp = FinanceLocalStorage.getEmployee(empId);
        final branchId = emp?['branchId']?.toString() ?? 'unknown';
        if (branchId != _selectedBranchFilter) return false;
      }

      if (_selectedDeptFilter != 'all') {
        final empId = loan['employeeId'] as String;
        final emp = FinanceLocalStorage.getEmployee(empId);
        final dept = emp?['department']?.toString() ?? 'Other';
        final cleanDept = dept.trim().isEmpty ? 'Other' : dept.trim();
        if (cleanDept.toLowerCase() != _selectedDeptFilter.toLowerCase()) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Top action bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildFilterBar(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search by employee...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (access == FinanceAccess.full || access == FinanceAccess.requestOnly)
                    ElevatedButton.icon(
                      onPressed: () => _showIssueLoanDialog(access),
                      style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Issue Loan', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _kBorder),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No loans found.', style: TextStyle(color: _kTextTertiary)))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                  itemBuilder: (context, idx) {
                    final loan = filtered[idx];
                    final isSel = _selectedLoan?['id'] == loan['id'];
                    final pMinor = (loan['principalMinor'] as num?)?.toInt() ?? 0;
                    final isClosed = loan['status'] == 'closed';



                    return ListTile(
                      tileColor: isClosed
                          ? const Color(0xFFF1F5F9)
                          : (isSel ? const Color(0xFFECFDF5) : _kBgCard),
                      title: Text(
                        loan['employeeName'] ?? 'Unknown Employee',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isClosed ? _kTextSecondary : _kTextPrimary,
                          decoration: isClosed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        'Issued: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(loan['dateIssued']))}',
                        style: TextStyle(color: isClosed ? _kTextTertiary : _kTextSecondary, fontSize: 11),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatPaisa(pMinor),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: isClosed ? _kTextTertiary : _kTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isClosed ? const Color(0xFFE2E8F0) : const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isClosed ? 'PAID OFF / CLOSED' : 'Active',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isClosed ? const Color(0xFF64748B) : _kAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => setState(() => _selectedLoan = loan),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLoanDetails(FinanceAccess access) {
    if (_selectedLoan == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_rounded, size: 48, color: _kTextTertiary),
            SizedBox(height: 12),
            Text('Select a loan to view history and repayments.', style: TextStyle(color: _kTextSecondary)),
          ],
        ),
      );
    }

    final loanId = _selectedLoan!['id'] as String;
    // Reload fresh loan data from box
    final freshRaw = Hive.box(LocalStorageService.financeLoansBox).get(loanId);
    if (freshRaw == null) {
      return const Center(child: Text('Loan details unavailable.'));
    }
    final loan = Map<String, dynamic>.from(freshRaw);
    final payments = List<Map<String, dynamic>>.from(
      (loan['payments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final activePayments = payments.where((p) => p['isVoided'] != true).toList();
    final activeRepayments = activePayments.where((p) => p['type'] != 'topup' && p['type'] != 'loan_issue').toList();


    final pMinor = (loan['principalMinor'] as num?)?.toInt() ?? 0;
    int paidMinor = 0;
    for (final p in activeRepayments) {
      paidMinor += (p['amountMinor'] as num?)?.toInt() ?? 0;
    }
    final outstandingMinor = (pMinor - paidMinor).clamp(0, 9999999999);
    final isClosed = loan['status'] == 'closed' || outstandingMinor <= 0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Closed Loan Banner
          if (isClosed) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                  SizedBox(width: 10),
                  Text(
                    '🎉 LOAN FULLY REPAID & CLOSED — Balance is 0 PKR',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Header info
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan['employeeName'] ?? 'Employee Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isClosed ? _kTextSecondary : _kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Repayment Type: ${loan['repaymentType'] == 'fixed' ? 'Fixed (Installments)' : 'Flexible'}',
                      style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Download Statement PDF Button
              OutlinedButton.icon(
                onPressed: () => FinanceReportHelper.exportLoanStatementPdf(loan),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kAccent,
                  side: const BorderSide(color: _kAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 8),

              if (!isClosed && (access == FinanceAccess.full || access == FinanceAccess.requestOnly)) ...[
                ElevatedButton.icon(
                  onPressed: () => _showRecordRepaymentDialog(loan, outstandingMinor, access),
                  style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
                  icon: const Icon(Icons.payment, size: 16),
                  label: const Text('Record Repayment', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Manual Close (Write-off)',
                  icon: const Icon(Icons.cancel_presentation_rounded, color: Colors.redAccent),
                  onPressed: () => _showWriteOffDialog(loan),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),


          // Cards Row
          Row(
            children: [
              _buildMetricCard('Principal', _formatPaisa(pMinor), Colors.blue),
              const SizedBox(width: 12),
              _buildMetricCard('Total Paid', _formatPaisa(paidMinor), Colors.green),
              const SizedBox(width: 12),
              _buildMetricCard('Outstanding', _formatPaisa(outstandingMinor), outstandingMinor > 0 ? Colors.orange : Colors.grey),
            ],
          ),
          const SizedBox(height: 24),

          // Payments Section
          const Text(
            'Transaction History / Ledger',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kTextPrimary),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: activePayments.isEmpty
                ? const Center(child: Text('No transactions recorded yet.', style: TextStyle(color: _kTextTertiary)))
                : ListView.separated(
                    itemCount: activePayments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                    itemBuilder: (context, index) {
                      final pay = activePayments[index];
                      final amt = (pay['amountMinor'] as num?)?.toInt() ?? 0;
                      final date = DateTime.parse(pay['date']);
                      final isVoided = pay['isVoided'] == true;
                      final isTopup = pay['type'] == 'topup' || pay['type'] == 'loan_issue';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: isTopup ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                          child: Icon(isTopup ? Icons.arrow_upward : Icons.arrow_downward, color: isTopup ? Colors.redAccent : _kAccent, size: 18),
                        ),
                        title: Text(
                          '${isTopup ? "+" : "-"}${_formatPaisa(amt)}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: isTopup ? Colors.redAccent : _kTextPrimary),
                        ),
                        subtitle: Text(
                          '${isTopup ? "Loan issued / Top-up" : "Repayment"} • Recorded by: ${pay['recordedBy']} on ${DateFormat('yyyy-MM-dd HH:mm').format(date)}',
                          style: const TextStyle(color: _kTextTertiary, fontSize: 11),
                        ),
                        trailing: (PermissionService().getLedgerVoidAccess(widget.userRole) == FinanceAccess.full)
                            ? TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                icon: const Icon(Icons.delete_outline, size: 14),
                                label: const Text('Void', style: TextStyle(fontSize: 11)),
                                onPressed: () => _showVoidRepaymentDialog(loan, pay),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _kBgCard,
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: _kTextSecondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              val,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showIssueLoanDialog(FinanceAccess access) {
    final employees = FinanceLocalStorage.getEmployees(widget.branchId);
    String? selectedEmpId;
    final principalCtrl = TextEditingController();
    final installmentCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String repaymentType = 'flexible';
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (dialogCtx, setDState) {
          final isFixed = repaymentType == 'fixed';
          return AlertDialog(
            backgroundColor: _kBgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Issue New Loan / Advance', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Employee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Autocomplete<Map<String, dynamic>>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return employees;
                        }
                        return employees.where((e) {
                          final name = (e['name'] ?? '').toString().toLowerCase();
                          return name.contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      displayStringForOption: (e) => e['name']?.toString() ?? '',
                      onSelected: (e) => setDState(() => selectedEmpId = e['id'] as String?),
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            hintText: 'Search or select employee...',
                            suffixIcon: controller.text.isNotEmpty 
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      controller.clear();
                                      setDState(() => selectedEmpId = null);
                                    },
                                  )
                                : const Icon(Icons.arrow_drop_down, size: 20),
                          ),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            color: _kBgCard,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 418,
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                border: Border.all(color: _kBorder),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final option = options.elementAt(index);
                                  return ListTile(
                                    dense: true,
                                    title: Text(option['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextPrimary)),
                                    subtitle: Text('${option['role'] ?? ""} • ${option['branchId'] ?? ""}', style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Principal Amount (PKR)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: principalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '0.00'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Repayment Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Radio<String>(
                          value: 'flexible',
                          groupValue: repaymentType,
                          activeColor: _kAccent,
                          onChanged: (val) => setDState(() => repaymentType = val!),
                        ),
                        const Text('Flexible'),
                        const SizedBox(width: 16),
                        Radio<String>(
                          value: 'fixed',
                          groupValue: repaymentType,
                          activeColor: _kAccent,
                          onChanged: (val) => setDState(() => repaymentType = val!),
                        ),
                        const Text('Fixed Installments'),
                      ],
                    ),
                    if (isFixed) ...[
                      const SizedBox(height: 16),
                      const Text('Usual Installment Amount (PKR/month)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: installmentCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '0.00'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text('Reason / Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Reason for loan'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
                onPressed: () async {
                  if (selectedEmpId == null) {
                    showCustomSnackBar(context, 'Please select an employee.', error: true);
                    return;
                  }
                  final principal = _parsePaisa(principalCtrl.text);
                  if (principal <= 0) {
                    showCustomSnackBar(context, 'Please enter a valid loan principal amount.', error: true);
                    return;
                  }
                  final empRecord = employees.firstWhere((e) => e['id'] == selectedEmpId);
                  final empName = empRecord['name'] ?? 'Employee';
                  final empBranchId = empRecord['branchId']?.toString() ?? widget.branchId;

                  final isRequestOnly = access == FinanceAccess.requestOnly;

                  try {
                    if (isRequestOnly) {
                      // Append as a pending request events in settings box or send directly to syncQueue as pending approval
                      final pendingId = 'pending_loan_${DateTime.now().millisecondsSinceEpoch}';
                      await LocalStorageService.enqueueSync({
                        'type': 'request_loan_approval',
                        'branchId': empBranchId,
                        'data': {
                          'id': pendingId,
                          'employeeId': selectedEmpId,
                          'employeeName': empName,
                          'principalMinor': principal,
                          'repaymentType': repaymentType,
                          'usualInstallmentMinor': isFixed ? _parsePaisa(installmentCtrl.text) : 0,
                          'reason': reasonCtrl.text,
                          'requestedBy': Hive.box('local_users').values.firstOrNull?['name']?.toString() ?? 'Manager',
                          'createdAt': DateTime.now().toUtc().toIso8601String(),
                        }
                      });
                      showCustomSnackBar(context, 'Loan request submitted for CEO approval.');
                    } else {
                      // Save directly
                      final loanId = await FinanceLoansStorage.createLoan(
                        branchId: empBranchId,
                        employeeId: selectedEmpId!,
                        employeeName: empName,
                        principal: principal / 100, // API expects double currently, we'll convert inside
                        repaymentType: repaymentType,
                        usualInstallment: isFixed ? _parsePaisa(installmentCtrl.text) / 100 : 0.0,
                        reason: reasonCtrl.text,
                        dateIssued: selectedDate,
                        performedBy: Hive.box('local_users').values.firstOrNull?['name']?.toString() ?? 'System',
                      );
                      showCustomSnackBar(context, 'Loan successfully issued.');
                    }
                    Navigator.pop(dialogCtx);
                    setState(() {});
                  } catch (e) {
                    showCustomSnackBar(context, 'Error issuing loan: $e', error: true);
                  }
                },
                child: Text(access == FinanceAccess.requestOnly ? 'Submit Request' : 'Issue'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showRecordRepaymentDialog(Map<String, dynamic> loan, int maxAmountMinor, FinanceAccess access) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _kBgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Record Repayment — ${loan['employeeName']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Max Outstanding: ${_formatPaisa(maxAmountMinor)}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Repayment Amount (PKR)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '0.00'),
              ),
              const SizedBox(height: 16),
              const Text('Note / Reference', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Note details'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final amtMinor = _parsePaisa(amountCtrl.text);
                if (amtMinor <= 0) {
                  showCustomSnackBar(context, 'Please enter a valid repayment amount.', error: true);
                  return;
                }
                if (amtMinor > maxAmountMinor) {
                  showCustomSnackBar(context, 'Amount exceeds total outstanding balance.', error: true);
                  return;
                }

                final performedBy = Hive.box('local_users').values.firstOrNull?['name']?.toString() ?? 'System';

                try {
                  if (access == FinanceAccess.requestOnly) {
                    await LocalStorageService.enqueueSync({
                      'type': 'request_loan_repayment_approval',
                      'branchId': loan['branchId'] ?? widget.branchId,
                      'data': {
                        'id': 'pending_repay_${DateTime.now().millisecondsSinceEpoch}',
                        'loanId': loan['id'],
                        'employeeId': loan['employeeId'],
                        'employeeName': loan['employeeName'],
                        'amountMinor': amtMinor,
                        'note': noteCtrl.text,
                        'requestedBy': performedBy,
                        'createdAt': DateTime.now().toUtc().toIso8601String(),
                      }
                    });
                    showCustomSnackBar(context, 'Repayment request submitted for approval.');
                  } else {
                    await FinanceLoansStorage.recordPayment(
                      loanId: loan['id'],
                      amount: amtMinor / 100,
                      note: noteCtrl.text,
                      performedBy: performedBy,
                    );
                    showCustomSnackBar(context, 'Repayment recorded successfully.');
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                } catch (e) {
                  showCustomSnackBar(context, 'Error recording repayment: $e', error: true);
                }
              },
              child: Text(access == FinanceAccess.requestOnly ? 'Submit Request' : 'Record'),
            ),
          ],
        );
      },
    );
  }

  void _showVoidRepaymentDialog(Map<String, dynamic> loan, Map<String, dynamic> payment) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _kBgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Void Repayment Entry', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount: ${_formatPaisa((payment['amountMinor'] as num?)?.toInt() ?? 0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('A reason is required to void this transaction:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter reason here...'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.isEmpty) {
                  showCustomSnackBar(context, 'Void reason is required.', error: true);
                  return;
                }

                // Check two-person rule for values above threshold (e.g. PKR 10,000)
                final amt = (payment['amountMinor'] as num?)?.toInt() ?? 0;
                final limit = 10000 * 100; // PKR 10,000 in paisa
                
                final userRole = (Hive.box('local_users').values.firstOrNull?['role']?.toString() ?? 'staff').toLowerCase();
                final bool isGlobalUser = userRole == 'admin' || userRole == 'hq manager' || userRole == 'ceo' || userRole == 'chairman';
                final isOverLimit = amt > limit && !isGlobalUser;

                final performedBy = Hive.box('local_users').values.firstOrNull?['name']?.toString() ?? 'System';

                try {
                  if (isOverLimit) {
                    // Queue for approval
                    await LocalStorageService.enqueueSync({
                      'type': 'request_void_repayment_approval',
                      'branchId': loan['branchId'] ?? widget.branchId,
                      'data': {
                        'id': 'pending_void_${DateTime.now().millisecondsSinceEpoch}',
                        'loanId': loan['id'],
                        'paymentId': payment['id'],
                        'amountMinor': amt,
                        'reason': reason,
                        'requestedBy': performedBy,
                        'createdAt': DateTime.now().toUtc().toIso8601String(),
                      }
                    });
                    showCustomSnackBar(context, 'Void request exceeds limit. Enqueued for CEO approval.');
                  } else {
                    await FinanceLoansStorage.voidPayment(
                      loanId: loan['id'],
                      paymentId: payment['id'],
                      performedBy: performedBy,
                      reason: reason,
                    );
                    showCustomSnackBar(context, 'Repayment successfully voided.');
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                } catch (e) {
                  showCustomSnackBar(context, 'Error voiding repayment: $e', error: true);
                }
              },
              child: const Text('Confirm Void'),
            ),
          ],
        );
      },
    );
  }

  void _showWriteOffDialog(Map<String, dynamic> loan) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _kBgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Write-off / Close Loan Manually', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This action will manually close the loan and forgive the remaining balance. Approval requires Owner (CEO/Chairman) authorization.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Reason for forgiveness:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'E.g., Medical relief, write-off...'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.isEmpty) {
                  showCustomSnackBar(context, 'Forgiveness reason is required.', error: true);
                  return;
                }

                final performedBy = Hive.box('local_users').values.firstOrNull?['name']?.toString() ?? 'System';

                try {
                  // Write-off requires Owner approval, queue as a request
                  await LocalStorageService.enqueueSync({
                    'type': 'request_loan_writeoff_approval',
                    'branchId': loan['branchId'] ?? widget.branchId,
                    'data': {
                      'id': 'pending_writeoff_${DateTime.now().millisecondsSinceEpoch}',
                      'loanId': loan['id'],
                      'employeeId': loan['employeeId'],
                      'employeeName': loan['employeeName'],
                      'reason': reason,
                      'requestedBy': performedBy,
                      'createdAt': DateTime.now().toUtc().toIso8601String(),
                    }
                  });
                  showCustomSnackBar(context, 'Write-off request submitted for CEO approval.');
                  Navigator.pop(ctx);
                  setState(() {});
                } catch (e) {
                  showCustomSnackBar(context, 'Error processing write-off: $e', error: true);
                }
              },
              child: const Text('Submit Request'),
            ),
          ],
        );
      },
    );
  }
}
