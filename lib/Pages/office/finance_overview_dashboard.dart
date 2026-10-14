// lib/pages/office/finance_overview_dashboard.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gmwf/design/design_system.dart';
import 'package:intl/intl.dart';
import '../../services/finance_ledger_storage.dart';
import '../../widgets/bank_logo_widget.dart';
import 'shared_finance_components.dart';

const _kAccent = SoftPalette.emerald350;
const _kBg = SoftPalette.gray50;
const _kBgCard = SoftPalette.gray50;
const _kBorder = SoftPalette.slate150;
const _kTextPrimary = SoftPalette.slate900;
const _kTextSecondary = SoftPalette.slate550;

class FinanceOverviewDashboard extends StatefulWidget {
  final String branchId;
  final String userRole;
  final Function(int tabIndex) onNavigateToTab;
  final VoidCallback onOpenBankAccounts;

  const FinanceOverviewDashboard({
    super.key,
    required this.branchId,
    required this.userRole,
    required this.onNavigateToTab,
    required this.onOpenBankAccounts,
  });

  @override
  State<FinanceOverviewDashboard> createState() => _FinanceOverviewDashboardState();
}

class _FinanceOverviewDashboardState extends State<FinanceOverviewDashboard> {
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());

  List<OrgBankAccount> _orgAccounts = [];
  Map<String, int> _accountBalancesPaisa = {};
  double _totalBankBalance = 0.0;
  double _cashOnHand = 0.0;
  double _loansReceivable = 0.0;
  double _monthInflow = 0.0;
  double _monthOutflow = 0.0;
  List<JournalEntry> _recentEntries = [];
  bool _isLoading = true;

  StreamSubscription? _journalSub;
  StreamSubscription? _bankAccountsSub;
  Timer? _debounceTimer;

  String _fmtCurrency(double amt) {
    return NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0).format(amt);
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _journalSub = FinanceLedgerStorage.journalBox.watch().listen((_) => _debouncedReload());
    _bankAccountsSub = FinanceLedgerStorage.bankAccountsBox.watch().listen((_) => _debouncedReload());
  }

  @override
  void didUpdateWidget(FinanceOverviewDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      _loadDashboardData();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _journalSub?.cancel();
    _bankAccountsSub?.cancel();
    super.dispose();
  }

  void _debouncedReload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadDashboardData();
    });
  }

  void _loadDashboardData() {
    final orgAccounts = FinanceLedgerStorage.getOrgBankAccounts();
    final metrics = FinanceLedgerStorage.getDashboardMetrics(
      monthKey: _selectedMonth,
      branchId: widget.branchId,
    );
    final balances = (metrics['balances'] as Map<String, int>?) ?? <String, int>{};

    double totalBank = 0.0;
    double cash = 0.0;
    for (final acc in orgAccounts) {
      final balPaisa = balances[acc.accountCode] ?? 0;
      final balPkr = balPaisa / 100.0;
      if (acc.accountCode == '1030') {
        cash += balPkr;
      } else {
        totalBank += balPkr;
      }
    }

    final loansPaisa = balances['1040'] ?? 0;
    final loans = loansPaisa / 100.0;

    final monthInflow = ((metrics['monthInflowPaisa'] as int? ?? 0) / 100.0);
    final monthOutflow = ((metrics['monthOutflowPaisa'] as int? ?? 0) / 100.0);

    final recent = FinanceLedgerStorage.getAllJournalEntries(
      branchId: widget.branchId,
      limit: 10,
    );

    if (mounted) {
      setState(() {
        _orgAccounts = orgAccounts;
        _accountBalancesPaisa = balances;
        _totalBankBalance = totalBank;
        _cashOnHand = cash;
        _loansReceivable = loans;
        _monthInflow = monthInflow;
        _monthOutflow = monthOutflow;
        _recentEntries = recent;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.adapt(_kBg),
        body: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }

    return Scaffold(
      backgroundColor: context.adapt(_kBg),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Bar
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Treasury & Financial Overview',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.adapt(_kTextPrimary), letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live double-entry general ledger summary & org bank accounts balance',
                        style: TextStyle(fontSize: 12, color: context.adapt(_kTextSecondary)),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenBankAccounts,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kAccent,
                    side: const BorderSide(color: _kAccent, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.account_balance_rounded, size: 18),
                  label: const Text('Manage Org Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Top KPI Cards Grid
            LayoutBuilder(builder: (ctx, constraints) {
              final wide = constraints.maxWidth > 900;
              final crossCount = wide ? 4 : 2;
              final childRatio = wide ? 1.6 : 1.4;

              return GridView.count(
                crossAxisCount: crossCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: childRatio,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildKpiCard(
                    title: 'Total Bank Balance',
                    value: _fmtCurrency(_totalBankBalance),
                    subtitle: '${_orgAccounts.where((a) => a.accountCode != '1030').length} Active Bank Accounts',
                    icon: Icons.account_balance_rounded,
                    color: SoftPalette.sky500,
                    onTap: () => widget.onNavigateToTab(6), // Reports / Reconcile
                  ),
                  _buildKpiCard(
                    title: 'Cash in Hand (Petty)',
                    value: _fmtCurrency(_cashOnHand),
                    subtitle: 'Petty Cash Fund (COA: 1030)',
                    icon: Icons.payments_rounded,
                    color: SoftPalette.emerald350,
                    onTap: () => widget.onNavigateToTab(4), // Expenses
                  ),
                  _buildKpiCard(
                    title: 'This Month Outflow',
                    value: _fmtCurrency(_monthOutflow),
                    subtitle: 'Payroll & Operating Expenses ($_selectedMonth)',
                    icon: Icons.output_rounded,
                    color: SoftPalette.red400,
                    onTap: () => widget.onNavigateToTab(4), // Expenses
                  ),
                  _buildKpiCard(
                    title: 'Loans Receivable',
                    value: _fmtCurrency(_loansReceivable),
                    subtitle: 'Active Staff Advances (COA: 1040)',
                    icon: Icons.credit_card_rounded,
                    color: SoftPalette.amber300,
                    onTap: () => widget.onNavigateToTab(3), // Loans
                  ),
                ],
              );
            }),
            const SizedBox(height: 28),

            // Org Bank Accounts Section
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded, size: 20, color: _kAccent),
                const SizedBox(width: 8),
                Text(
                  'Foundation Bank & Treasury Accounts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.adapt(_kTextPrimary)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onOpenBankAccounts,
                  child: const Text('+ Add Account', style: TextStyle(fontWeight: FontWeight.bold, color: _kAccent)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisExtent: 90,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _orgAccounts.length,
              itemBuilder: (context, idx) {
                final acc = _orgAccounts[idx];
                final balPaisa = _accountBalancesPaisa[acc.accountCode] ?? 0;
                final balStr = _fmtCurrency(balPaisa / 100.0);

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.adapt(_kBgCard),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.adapt(_kBorder)),
                    boxShadow: [
                      BoxShadow(color: SoftPalette.gray900.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      BankLogoWidget(bankName: acc.bankName, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              acc.accountTitle,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: context.adapt(_kTextPrimary)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              balStr,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _kAccent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 28),

            // Recent Double-Entry Journal Feed
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 20, color: _kAccent),
                const SizedBox(width: 8),
                Text(
                  'Recent Double-Entry Journal Feed',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.adapt(_kTextPrimary)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => widget.onNavigateToTab(6), // Reports & Audit
                  child: const Text('View All Ledger Entries ➔', style: TextStyle(fontWeight: FontWeight.bold, color: _kAccent)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: context.adapt(_kBgCard),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.adapt(_kBorder)),
              ),
              child: _recentEntries.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No journal entries posted yet.', style: TextStyle(color: context.adapt(_kTextSecondary)))),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recentEntries.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: context.adapt(_kBorder)),
                      itemBuilder: (context, idx) {
                        final entry = _recentEntries[idx];
                        final dept = entry.departmentId ?? 'ADMIN';


                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: context.adapt(SoftPalette.slate100),
                            child: Text(
                              entry.sourceType.substring(0, 2),
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: context.adapt(_kTextPrimary)),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(entry.sourceType, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: context.adapt(_kTextPrimary))),
                              const SizedBox(width: 8),
                              DepartmentChip(department: dept),
                              const SizedBox(width: 8),
                              BranchChip(branchId: entry.branchId),
                            ],
                          ),
                          subtitle: Text(
                            '${entry.description} • Posted by ${entry.createdBy} on ${entry.date}',
                            style: TextStyle(fontSize: 11, color: context.adapt(_kTextSecondary)),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _fmtCurrency(entry.totalDebits / 100.0),
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.adapt(_kTextPrimary)),
                              ),
                              const Text('Balanced Dr = Cr', style: TextStyle(fontSize: 9, color: _kAccent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.adapt(_kBgCard),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.adapt(_kBorder)),
          boxShadow: [
            BoxShadow(color: SoftPalette.gray900.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: context.adapt(_kTextSecondary)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.adapt(_kTextSecondary))),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 10, color: context.adapt(SoftPalette.slate350))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
