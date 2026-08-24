// lib/pages/office/expenses_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_expenses_storage.dart';
import '../../services/local_storage_service.dart';
import 'shared_widgets.dart';

class ExpensesTab extends StatefulWidget {
  final String branchId;
  final String userRole;

  const ExpensesTab({
    super.key,
    required this.branchId,
    required this.userRole,
  });

  @override
  State<ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<ExpensesTab> {
  DateTime _selectedDate = DateTime.now();
  bool _viewAllBranches = false;
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

  final List<String> _categories = [
    'Office',
    'Administration',
    'Dasterkhawaan',
    'Dispensary',
    'Madrassa',
    'School',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (_isBranchScopedUser) {
      _viewAllBranches = false;
    } else if (widget.branchId == 'all') {
      _viewAllBranches = true;
    }
  }

  String _getEffectiveBranchId() {
    if (_isBranchScopedUser) return widget.branchId.isNotEmpty ? widget.branchId : 'karachi';
    if (_viewAllBranches) return 'all';
    return widget.branchId;
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'masjid':
        return Icons.mosque_outlined;
      case 'dasterkhawaan':
        return Icons.restaurant_outlined;
      case 'school':
        return Icons.school_outlined;
      case 'office':
        return Icons.work_outline;
      case 'dispensary':
        return Icons.local_hospital_outlined;
      case 'home':
        return Icons.home_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Color _getCategoryColor(String category, RoleThemeData t) {
    switch (category.toLowerCase()) {
      case 'masjid':
        return Colors.teal;
      case 'dasterkhawaan':
        return Colors.orange;
      case 'school':
        return Colors.blue;
      case 'office':
        return Colors.indigo;
      case 'dispensary':
        return Colors.red;
      case 'home':
        return Colors.purple;
      default:
        return t.accent;
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
  }

  void _openAddExpenseSheet(BuildContext context, RoleThemeData tOriginal) {
    final t = RoleThemeData(
      roleLabel: tOriginal.roleLabel,
      isDarkCanvas: false,
      bg: const Color(0xFFF8FAFC),
      bgCard: Colors.white,
      bgCardAlt: const Color(0xFFF1F5F9),
      bgRule: const Color(0xFFE2E8F0),
      accent: const Color(0xFF10B981),
      accentLight: const Color(0xFF34D399),
      accentMuted: const Color(0xFFD1FAE5),
      accentGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
      glassTint: const Color(0x1A10B981),
      textPrimary: const Color(0xFF111827),
      textSecondary: const Color(0xFF6B7280),
      textTertiary: const Color(0xFF9CA3AF),
      danger: const Color(0xFFEF4444),
      zakat: tOriginal.zakat,
      nonZakat: tOriginal.nonZakat,
      gmwf: tOriginal.gmwf,
      cardFillTokens: tOriginal.cardFillTokens,
      cardFillPrescriptions: tOriginal.cardFillPrescriptions,
      cardFillDispensary: tOriginal.cardFillDispensary,
      chartBar1: tOriginal.chartBar1,
      chartBar2: tOriginal.chartBar2,
      chartBar3: tOriginal.chartBar3,
      chartGrid: tOriginal.chartGrid,
    );
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final customCatCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(_selectedDate));
    
    String selectedCategory = _categories.first;
    bool isOtherSelected = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return RoleThemeScope(
          role: RoleTheme.admin,
          child: StatefulBuilder(
            builder: (dialogCtx, setDialogState) {
              return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(dialogCtx).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: t.bgCard,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Log Daily Expense',
                          style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: t.textSecondary),
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    
                    // Amount Field
                    buildFormField(
                      controller: amountCtrl,
                      label: 'Amount (PKR)',
                      icon: Icons.payments_outlined,
                      theme: t,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                    ),

                    // Date Field
                    buildDatePickerField(
                      context: dialogCtx,
                      controller: dateCtrl,
                      label: 'Expense Date',
                      icon: Icons.calendar_today_outlined,
                      theme: t,
                    ),

                    // Category Dropdown Container
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: t.bgCardAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButtonFormField<String>(
                          value: selectedCategory,
                          dropdownColor: t.bgCard,
                          style: TextStyle(color: t.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Category',
                            labelStyle: TextStyle(color: t.textTertiary, fontSize: 11),
                            prefixIcon: Icon(_getCategoryIcon(selectedCategory), color: _getCategoryColor(selectedCategory, t), size: 18),
                            border: InputBorder.none,
                          ),
                          items: _categories.map((cat) {
                            return DropdownMenuItem<String>(
                              value: cat,
                              child: Text(cat, style: TextStyle(color: t.textPrimary)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedCategory = val;
                                isOtherSelected = (val == 'Other');
                              });
                            }
                          },
                        ),
                      ),
                    ),

                    // Custom Category Name (Conditional)
                    if (isOtherSelected)
                      buildFormField(
                        controller: customCatCtrl,
                        label: 'Custom Category Name',
                        icon: Icons.edit_note_outlined,
                        theme: t,
                      ),

                    // Description Field
                    buildFormField(
                      controller: descCtrl,
                      label: 'Description / Remarks',
                      icon: Icons.description_outlined,
                      theme: t,
                      maxLines: 2,
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final amt = double.tryParse(amountCtrl.text);
                          final desc = descCtrl.text.trim();
                          final dateStr = dateCtrl.text.trim();

                          if (amt == null || amt <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid amount')),
                            );
                            return;
                          }

                          if (desc.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a description')),
                            );
                            return;
                          }

                          if (isOtherSelected && customCatCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please specify the custom category')),
                            );
                            return;
                          }

                          DateTime expDate;
                          try {
                            expDate = DateFormat('yyyy-MM-dd').parse(dateStr);
                          } catch (_) {
                            expDate = DateTime.now();
                          }

                          // Retrieve Current User
                          final userMap = Hive.box('local_users').values.firstOrNull;
                          final username = userMap?['name']?.toString() ?? userMap?['username']?.toString() ?? 'Admin';
                          final userId = userMap?['uid']?.toString() ?? userMap?['id']?.toString() ?? 'unknown';

                          final bId = widget.branchId == 'all' ? 'hq' : widget.branchId;

                          try {
                            await FinanceExpensesStorage.saveExpense(
                              branchId: bId,
                              amount: amt,
                              category: selectedCategory,
                              customCategory: isOtherSelected ? customCatCtrl.text.trim() : null,
                              description: desc,
                              performedBy: userId,
                              performedByName: username,
                              date: expDate,
                            );

                            if (context.mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Daily Expense logged successfully')),
                              );
                            }
                          } catch (e) {
                            showCustomSnackBar(dialogCtx, e.toString().replaceAll('Exception: ', ''), error: true);
                          }
                        },
                        child: const Text('Save Expense', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

  void _openVoidConfirmDialog(BuildContext context, Map<String, dynamic> expense, RoleThemeData t) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: t.bgCard,
          title: Text(
            'Void Expense',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to void this expense of PKR ${expense['amount']}?',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              buildFormField(
                controller: reasonCtrl,
                label: 'Void Reason',
                icon: Icons.comment_bank_outlined,
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
              style: ElevatedButton.styleFrom(backgroundColor: t.danger, foregroundColor: Colors.white),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a void reason')),
                  );
                  return;
                }

                // Retrieve Current User
                final userMap = Hive.box('local_users').values.firstOrNull;
                final username = userMap?['name']?.toString() ?? userMap?['username']?.toString() ?? 'Admin';

                final bId = expense['branchId']?.toString() ?? widget.branchId;

                try {
                  await FinanceExpensesStorage.voidExpense(
                    branchId: bId,
                    expenseId: expense['id']?.toString() ?? '',
                    voidedBy: username,
                    voidReason: reason,
                  );

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Expense has been voided')),
                    );
                  }
                } catch (e) {
                  showCustomSnackBar(ctx, e.toString().replaceAll('Exception: ', ''), error: true);
                }
              },
              child: const Text('Void Record', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tOriginal = RoleThemeScope.dataOf(context);
    final t = RoleThemeData(
      roleLabel: tOriginal.roleLabel,
      isDarkCanvas: false,
      bg: const Color(0xFFF8FAFC),
      bgCard: Colors.white,
      bgCardAlt: const Color(0xFFF1F5F9),
      bgRule: const Color(0xFFE2E8F0),
      accent: const Color(0xFF10B981),
      accentLight: const Color(0xFF34D399),
      accentMuted: const Color(0xFFD1FAE5),
      accentGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
      glassTint: const Color(0x1A10B981),
      textPrimary: const Color(0xFF111827),
      textSecondary: const Color(0xFF6B7280),
      textTertiary: const Color(0xFF9CA3AF),
      danger: const Color(0xFFEF4444),
      zakat: tOriginal.zakat,
      nonZakat: tOriginal.nonZakat,
      gmwf: tOriginal.gmwf,
      cardFillTokens: tOriginal.cardFillTokens,
      cardFillPrescriptions: tOriginal.cardFillPrescriptions,
      cardFillDispensary: tOriginal.cardFillDispensary,
      chartBar1: tOriginal.chartBar1,
      chartBar2: tOriginal.chartBar2,
      chartBar3: tOriginal.chartBar3,
      chartGrid: tOriginal.chartGrid,
    );
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final isGlobalRole = ['admin', 'ceo', 'chairman', 'global admin', 'hq manager'].contains(widget.userRole.toLowerCase());
    final monthKey = DateFormat('yyyy-MM').format(_selectedDate);
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          if (isLocked)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.amber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The period $monthKey is locked and closed. Logging or voiding expenses is disabled.',
                      style: TextStyle(color: Colors.amber[800], fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          // ── Date Navigator + Toggle bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.5)),
            ),
            child: Row(
              children: [
                // Previous Day
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                  color: const Color(0xFF6B7280),
                  onPressed: () => _changeDate(-1),
                ),
                
                // Active Date Label
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      child: Text(
                        DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                // Next Day
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                  color: const Color(0xFF6B7280),
                  onPressed: () => _changeDate(1),
                ),

                const SizedBox(width: 10),
                // Today Button
                Builder(builder: (context) {
                  final today = DateTime.now();
                  final isToday = _selectedDate.year == today.year &&
                      _selectedDate.month == today.month &&
                      _selectedDate.day == today.day;
                  if (isToday) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          const Text('Today', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5)),
                        ],
                      ),
                    );
                  }
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedDate = DateTime.now());
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.today_outlined, size: 10, color: Color(0xFF10B981)),
                          SizedBox(width: 4),
                          Text('GO TO TODAY', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(width: 4),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLocked ? Colors.grey : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: isLocked ? null : () => _openAddExpenseSheet(context, t),
                ),

                // Cross-branch Reporting Switch (Executive roles only)
                if (isGlobalRole && widget.branchId == 'all') ...[
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'All Branches',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Switch(
                        activeColor: const Color(0xFF10B981),
                        value: _viewAllBranches,
                        onChanged: (val) {
                          setState(() => _viewAllBranches = val);
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // ── Reactive Expenses List & Breakdowns ──────────────────────────────────
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: Hive.box(LocalStorageService.expensesBox).listenable(),
              builder: (context, Box box, _) {
                final activeBranch = _getEffectiveBranchId();
                final dayExpenses = FinanceExpensesStorage.getExpensesForDate(activeBranch, dateKey);
                final breakdown = FinanceExpensesStorage.getCategoryBreakdown(dayExpenses);

                double totalDailySpend = 0.0;
                for (final exp in dayExpenses) {
                  if (exp['isVoided'] != true) {
                    totalDailySpend += (exp['amount'] as num?)?.toDouble() ?? 0.0;
                  }
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Total Spent Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _viewAllBranches ? 'Total Cross-Branch Spent Today' : 'Total Spent Today',
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'PKR ${NumberFormat('#,##0.00').format(totalDailySpend)}',
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Category Breakdown Chips / Bar list
                      if (breakdown.isNotEmpty) ...[
                        const Text(
                          'Category Breakdown',
                          style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 52,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: breakdown.length,
                            itemBuilder: (context, idx) {
                              final cat = breakdown.keys.elementAt(idx);
                              final val = breakdown[cat]!;
                              final catColor = _getCategoryColor(cat, t);
                              
                              return Container(
                                margin: const EdgeInsets.only(right: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(color: catColor, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$cat: ',
                                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'PKR ${NumberFormat('#,##0').format(val)}',
                                      style: const TextStyle(color: Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Activity Log Header
                      const Text(
                        'Daily Spend Log',
                        style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      if (dayExpenses.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wallet_outlined, size: 52, color: Color(0xFF9CA3AF)),
                                SizedBox(height: 12),
                                Text(
                                  'No expenses logged for this day',
                                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tap the "+" button to log a spend',
                                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: dayExpenses.length,
                          itemBuilder: (context, index) {
                            final exp = dayExpenses[index];
                            final isVoided = exp['isVoided'] == true;
                            
                            final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
                            final cat = exp['category']?.toString() ?? 'Other';
                            final customCat = exp['customCategory']?.toString();
                            final desc = exp['description']?.toString() ?? '';
                            final perfBy = exp['performedByName']?.toString() ?? 'Staff';
                            final branchTag = exp['branchId']?.toString() ?? '';
                            final syncStatus = exp['syncStatus']?.toString() ?? 'synced';

                            // Format Date string
                            var timeStr = '';
                            final dtStr = exp['date']?.toString();
                            if (dtStr != null) {
                              final parsed = DateTime.tryParse(dtStr);
                              if (parsed != null) {
                                timeStr = DateFormat('jm').format(parsed.toLocal());
                              }
                            }

                            final categoryDisplay = (cat == 'Other' && customCat != null && customCat.isNotEmpty) ? customCat : cat;
                            final catColor = _getCategoryColor(cat, t);
                            final catIcon = _getCategoryIcon(cat);

                            return Card(
                              color: Colors.white,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: isVoided ? const Color(0xFFE2E8F0).withOpacity(0.5) : const Color(0xFFE2E8F0), width: 0.75),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: catColor.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(catIcon, color: catColor, size: 20),
                                ),
                                title: Text(
                                  desc,
                                  style: TextStyle(
                                    color: isVoided ? const Color(0xFF9CA3AF) : const Color(0xFF111827),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    decoration: isVoided ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        // Category Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: catColor.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            categoryDisplay,
                                            style: TextStyle(color: catColor, fontSize: 10, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Logger Name
                                        Text(
                                          'By $perfBy',
                                          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                                        ),
                                        if (timeStr.isNotEmpty) ...[
                                          const SizedBox(width: 4),
                                          Text('• $timeStr', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
                                        ],
                                        // Branch Identifier if viewed globally
                                        if (_viewAllBranches && branchTag.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE2E8F0),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              branchTag.toUpperCase(),
                                              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (isVoided) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 12),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Voided: "${exp['voidReason'] ?? 'no reason'}" by ${exp['voidedBy'] ?? 'Unknown'}',
                                              style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Local Sync Status Indicator
                                    if (!isVoided)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Icon(
                                          syncStatus == 'synced' ? Icons.cloud_done : Icons.cloud_upload,
                                          size: 14,
                                          color: syncStatus == 'synced' ? Colors.green.shade400 : Colors.orange.shade400,
                                        ),
                                      ),
                                    Text(
                                      'PKR ${NumberFormat('#,##0').format(amt)}',
                                      style: TextStyle(
                                        color: isVoided ? const Color(0xFF9CA3AF) : const Color(0xFF111827),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        decoration: isVoided ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                    if (!isVoided &&
                                        ['admin', 'ceo', 'chairman', 'global admin', 'hq manager', 'branch manager', 'supervisor']
                                            .contains(widget.userRole.toLowerCase()))
                                      IconButton(
                                        icon: Icon(Icons.delete_sweep_outlined, color: isLocked ? Colors.grey : Colors.red, size: 18),
                                        onPressed: isLocked ? null : () => _openVoidConfirmDialog(context, exp, t),
                                        tooltip: isLocked ? 'Period is locked' : 'Void this record',
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
