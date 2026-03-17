// lib/pages/assets.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────────

class DispensaryAsset {
  final String id;
  final String name;
  final String category;
  final double purchasePrice;
  final DateTime purchaseDate;
  final String notes;
  final DateTime? repairDate;
  final double? repairCost;
  final String? damageDescription;
  final double depreciationRate; // Annual % e.g. 10 = 10% per year

  DispensaryAsset({
    required this.id,
    required this.name,
    required this.category,
    required this.purchasePrice,
    required this.purchaseDate,
    required this.notes,
    this.repairDate,
    this.repairCost,
    this.damageDescription,
    this.depreciationRate = 0.0,
  });

  /// Current book value using reducing-balance (compound) depreciation
  double get currentValue {
    if (depreciationRate <= 0) return purchasePrice;
    final years = DateTime.now().difference(purchaseDate).inDays / 365.0;
    final val = purchasePrice * pow(1 - depreciationRate / 100, years);
    return (val as double).clamp(0.0, purchasePrice);
  }

  double get totalDepreciated => purchasePrice - currentValue;

  factory DispensaryAsset.fromMap(String id, Map<String, dynamic> map) =>
      DispensaryAsset(
        id: id,
        name: map['name'] ?? '',
        category: map['category'] ?? '',
        purchasePrice: (map['purchasePrice'] as num?)?.toDouble() ?? 0.0,
        purchaseDate:
            (map['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        notes: map['notes'] ?? '',
        repairDate: (map['repairDate'] as Timestamp?)?.toDate(),
        repairCost: (map['repairCost'] as num?)?.toDouble(),
        damageDescription: map['damageDescription'] as String?,
        depreciationRate:
            (map['depreciationRate'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'purchasePrice': purchasePrice,
        'purchaseDate': purchaseDate,
        'notes': notes,
        'repairDate': repairDate,
        'repairCost': repairCost,
        'damageDescription': damageDescription,
        'depreciationRate': depreciationRate,
      };
}

class EmployeeSalary {
  final String id;
  final String name;
  final String designation;
  final String cnic;
  final DateTime joiningDate;
  final double baseSalary;
  final double advance;
  final double deductions;
  final String notes;
  /// Default annual increment %, e.g. 10.0 = 10%. 0 means no default set.
  final double defaultIncrementRate;
  /// When true this employee is exempt from increment (high-salary exception).
  final bool noIncrement;

  EmployeeSalary({
    required this.id,
    required this.name,
    required this.designation,
    required this.cnic,
    required this.joiningDate,
    required this.baseSalary,
    required this.advance,
    required this.deductions,
    required this.notes,
    this.defaultIncrementRate = 0.0,
    this.noIncrement = false,
  });

  double get netSalary => baseSalary - advance - deductions;

  factory EmployeeSalary.fromMap(String id, Map<String, dynamic> map) =>
      EmployeeSalary(
        id: id,
        name: map['name'] ?? '',
        designation: map['designation'] ?? '',
        cnic: map['cnic'] ?? '',
        joiningDate:
            (map['joiningDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        baseSalary: (map['baseSalary'] as num?)?.toDouble() ?? 0.0,
        advance: (map['advance'] as num?)?.toDouble() ?? 0.0,
        deductions: (map['deductions'] as num?)?.toDouble() ?? 0.0,
        notes: map['notes'] ?? '',
        defaultIncrementRate:
            (map['defaultIncrementRate'] as num?)?.toDouble() ?? 0.0,
        noIncrement: map['noIncrement'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'designation': designation,
        'cnic': cnic,
        'joiningDate': joiningDate,
        'baseSalary': baseSalary,
        'advance': advance,
        'deductions': deductions,
        'notes': notes,
        'defaultIncrementRate': defaultIncrementRate,
        'noIncrement': noIncrement,
      };
}

/// One entry in an employee's salary history subcollection
class SalaryHistoryEntry {
  final String id;
  final String type; // 'increment' | 'decrement' | 'advance' | 'deduction'
  final double amount;       // Rs. amount of the change
  final double? percentage;  // % used for increment/decrement (null for advance/deduction)
  final double previousSalary;
  final double newSalary;
  final DateTime date;
  final String notes;
  final DateTime recordedAt;

  SalaryHistoryEntry({
    required this.id,
    required this.type,
    required this.amount,
    this.percentage,
    required this.previousSalary,
    required this.newSalary,
    required this.date,
    required this.notes,
    required this.recordedAt,
  });

  factory SalaryHistoryEntry.fromMap(String id, Map<String, dynamic> map) =>
      SalaryHistoryEntry(
        id: id,
        type: map['type'] ?? 'increment',
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        percentage: (map['percentage'] as num?)?.toDouble(),
        previousSalary: (map['previousSalary'] as num?)?.toDouble() ?? 0.0,
        newSalary: (map['newSalary'] as num?)?.toDouble() ?? 0.0,
        date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        notes: map['notes'] ?? '',
        recordedAt:
            (map['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

class OperatingExpense {
  final String id;
  final String name;
  final String category;
  final double amount;
  final String notes;
  final DateTime addedAt;

  OperatingExpense({
    required this.id,
    required this.name,
    required this.category,
    required this.amount,
    required this.notes,
    required this.addedAt,
  });

  factory OperatingExpense.fromMap(String id, Map<String, dynamic> map) =>
      OperatingExpense(
        id: id,
        name: map['name'] ?? '',
        category: map['category'] ?? 'Miscellaneous',
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        notes: map['notes'] ?? '',
        addedAt: (map['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

/// Snapshot of a salary payment for a specific month
class PayrollRecord {
  final String id;
  final String employeeId;
  final String employeeName;
  final int month;
  final int year;
  final double baseSalary;
  final double advance;
  final double deductions;
  final double netSalary;
  final bool paid;
  final DateTime? paidAt;
  final String notes;

  PayrollRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.year,
    required this.baseSalary,
    required this.advance,
    required this.deductions,
    required this.netSalary,
    required this.paid,
    this.paidAt,
    this.notes = '',
  });

  factory PayrollRecord.fromMap(String id, Map<String, dynamic> map) =>
      PayrollRecord(
        id: id,
        employeeId: map['employeeId'] ?? '',
        employeeName: map['employeeName'] ?? '',
        month: map['month'] ?? 0,
        year: map['year'] ?? 0,
        baseSalary: (map['baseSalary'] as num?)?.toDouble() ?? 0.0,
        advance: (map['advance'] as num?)?.toDouble() ?? 0.0,
        deductions: (map['deductions'] as num?)?.toDouble() ?? 0.0,
        netSalary: (map['netSalary'] as num?)?.toDouble() ?? 0.0,
        paid: map['paid'] ?? false,
        paidAt: (map['paidAt'] as Timestamp?)?.toDate(),
        notes: map['notes'] ?? '',
      );
}

/// Payment record for an operating expense in a given month
class ExpensePaymentRecord {
  final String id;
  final String expenseId;
  final String name;
  final String category;
  final double baseAmount;
  final double actualAmount;
  final int month;
  final int year;
  final bool paid;
  final DateTime? paidAt;
  final String notes;

  ExpensePaymentRecord({
    required this.id,
    required this.expenseId,
    required this.name,
    required this.category,
    required this.baseAmount,
    required this.actualAmount,
    required this.month,
    required this.year,
    required this.paid,
    this.paidAt,
    this.notes = '',
  });

  factory ExpensePaymentRecord.fromMap(String id, Map<String, dynamic> map) =>
      ExpensePaymentRecord(
        id: id,
        expenseId: map['expenseId'] ?? '',
        name: map['name'] ?? '',
        category: map['category'] ?? 'Miscellaneous',
        baseAmount: (map['baseAmount'] as num?)?.toDouble() ?? 0.0,
        actualAmount: (map['actualAmount'] as num?)?.toDouble() ?? 0.0,
        month: map['month'] ?? 0,
        year: map['year'] ?? 0,
        paid: map['paid'] ?? false,
        paidAt: (map['paidAt'] as Timestamp?)?.toDate(),
        notes: map['notes'] ?? '',
      );
}

// ─────────────────────────────────────────────
//  THEME
// ─────────────────────────────────────────────

class _AppTheme {
  static const Color adminPrimary = Color(0xFF37474F);
  static const Color adminAccent = Color(0xFF26A69A);
  static const Color adminDanger = Color(0xFFE57373);
  static const Color adminSurface = Color(0xFFF5F5F5);
  static const Color adminCard = Colors.white;
  static const Color adminText = Color(0xFF212121);
  static const Color adminSub = Color(0xFF757575);

  static const Color superPrimary = Color(0xFF2E7D32);
  static const Color superAccent = Color(0xFF4CAF50);
  static const Color superDanger = Color(0xFFE53935);
  static const Color superSurface = Color(0xFFF1F8E9);
  static const Color superCard = Color(0xFFFFFFFF);
  static const Color superText = Color(0xFF1B5E20);
  static const Color superSub = Color(0xFF558B2F);
}

class _Palette {
  final Color primary;
  final Color accent;
  final Color danger;
  final Color surface;
  final Color card;
  final Color text;
  final Color sub;

  const _Palette({
    required this.primary,
    required this.accent,
    required this.danger,
    required this.surface,
    required this.card,
    required this.text,
    required this.sub,
  });

  factory _Palette.admin() => const _Palette(
        primary: _AppTheme.adminPrimary,
        accent: _AppTheme.adminAccent,
        danger: _AppTheme.adminDanger,
        surface: _AppTheme.adminSurface,
        card: _AppTheme.adminCard,
        text: _AppTheme.adminText,
        sub: _AppTheme.adminSub,
      );

  factory _Palette.supervisor() => const _Palette(
        primary: _AppTheme.superPrimary,
        accent: _AppTheme.superAccent,
        danger: _AppTheme.superDanger,
        surface: _AppTheme.superSurface,
        card: _AppTheme.superCard,
        text: _AppTheme.superText,
        sub: _AppTheme.superSub,
      );
}

// ─────────────────────────────────────────────
//  EXPENSE CATEGORIES
// ─────────────────────────────────────────────

const List<Map<String, dynamic>> kExpenseCategories = [
  {'label': 'Tea / Refreshments', 'icon': Icons.emoji_food_beverage},
  {'label': 'Electricity & Utilities', 'icon': Icons.bolt},
  {'label': 'Rent', 'icon': Icons.home_work},
  {'label': 'Internet / Phone', 'icon': Icons.wifi},
  {'label': 'Cleaning & Hygiene', 'icon': Icons.cleaning_services},
  {'label': 'Stationery & Office', 'icon': Icons.edit_note},
  {'label': 'Repairs & Maintenance', 'icon': Icons.build},
  {'label': 'Miscellaneous', 'icon': Icons.more_horiz},
];

IconData _categoryIcon(String cat) {
  final match = kExpenseCategories.firstWhere(
    (e) => e['label'] == cat,
    orElse: () => {'icon': Icons.receipt_long},
  );
  return match['icon'] as IconData;
}

Color _categoryColor(String cat, _Palette p) {
  const colors = [
    Color(0xFF8D6E63),
    Color(0xFFF9A825),
    Color(0xFF5C6BC0),
    Color(0xFF26C6DA),
    Color(0xFF66BB6A),
    Color(0xFFEC407A),
    Color(0xFFFF7043),
    Color(0xFF78909C),
  ];
  final idx = kExpenseCategories.indexWhere((e) => e['label'] == cat);
  return idx >= 0 ? colors[idx % colors.length] : p.accent;
}

// ─────────────────────────────────────────────
//  SALARY CHANGE TYPE CONFIG
// ─────────────────────────────────────────────

const _kSalaryChangeTypes = [
  {'value': 'increment', 'label': 'Increment', 'icon': Icons.trending_up, 'color': Color(0xFF43A047)},
  {'value': 'decrement', 'label': 'Decrement', 'icon': Icons.trending_down, 'color': Color(0xFFE53935)},
  {'value': 'advance', 'label': 'Advance', 'icon': Icons.monetization_on_outlined, 'color': Color(0xFFFB8C00)},
  {'value': 'deduction', 'label': 'Deduction', 'icon': Icons.remove_circle_outline, 'color': Color(0xFF8E24AA)},
];

Color _changeTypeColor(String type) {
  final match = _kSalaryChangeTypes.firstWhere((t) => t['value'] == type,
      orElse: () => {'color': const Color(0xFF757575)});
  return match['color'] as Color;
}

IconData _changeTypeIcon(String type) {
  final match = _kSalaryChangeTypes.firstWhere((t) => t['value'] == type,
      orElse: () => {'icon': Icons.swap_horiz});
  return match['icon'] as IconData;
}

// ─────────────────────────────────────────────
//  MAIN PAGE
// ─────────────────────────────────────────────

class AssetsPage extends StatefulWidget {
  final String branchId;
  final bool isAdmin;

  const AssetsPage({
    super.key,
    required this.branchId,
    required this.isAdmin,
  });

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _allowEditing = false;

  // ── form keys ──
  final _assetFormKey = GlobalKey<FormState>();
  final _salaryFormKey = GlobalKey<FormState>();
  final _expenseFormKey = GlobalKey<FormState>();
  final _salaryChangeFormKey = GlobalKey<FormState>();

  // ── asset controllers ──
  final _assetNameCtrl = TextEditingController();
  final _assetCategoryCtrl = TextEditingController();
  final _assetPriceCtrl = TextEditingController();
  final _assetNotesCtrl = TextEditingController();
  final _repairCostCtrl = TextEditingController();
  final _damageCtrl = TextEditingController();
  final _depreciationCtrl = TextEditingController(); // NEW
  DateTime _assetDate = DateTime.now();
  DateTime? _repairDate;

  // ── salary controllers ──
  final _empNameCtrl = TextEditingController();
  final _empDesignationCtrl = TextEditingController();
  final _empCnicCtrl = TextEditingController();
  final _empSalaryCtrl = TextEditingController();
  final _empAdvanceCtrl = TextEditingController();
  final _empDeductionCtrl = TextEditingController();
  final _empNotesCtrl = TextEditingController();
  final _empIncrementRateCtrl = TextEditingController(); // NEW – default annual %
  bool _empNoIncrement = false;                          // NEW – exempt flag
  DateTime _empJoiningDate = DateTime.now();

  // ── expense controllers ──
  final _expNameCtrl = TextEditingController();
  final _expAmountCtrl = TextEditingController();
  final _expNotesCtrl = TextEditingController();
  String _expCategory = 'Miscellaneous';

  // ── salary change controllers (NEW) ──
  final _salaryChangeAmtCtrl = TextEditingController();
  final _salaryChangeNotesCtrl = TextEditingController();
  String _salaryChangeType = 'increment';
  DateTime _salaryChangeDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _listenEditPermission();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _listenEditPermission() {
    FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('settings')
        .doc('assets')
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _allowEditing = snap.data()?['allowSupervisorEdit'] ?? false;
        });
      }
    });
  }

  Future<void> _toggleEditPermission(bool v) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('settings')
        .doc('assets')
        .set({'allowSupervisorEdit': v}, SetOptions(merge: true));
  }

  bool get canEdit => widget.isAdmin || _allowEditing;
  _Palette get p => widget.isAdmin ? _Palette.admin() : _Palette.supervisor();

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: p.surface,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSummaryBanner(isWide),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _AssetsTab(
                  branchId: widget.branchId,
                  palette: p,
                  canEdit: canEdit,
                  onAdd: _showAddAssetDialog,
                  onEdit: _showEditAssetDialog,
                  onDelete: _deleteAsset,
                ),
                _SalaryTab(
                  branchId: widget.branchId,
                  palette: p,
                  canEdit: canEdit,
                  onAdd: _showAddSalaryDialog,
                  onEdit: _showEditSalaryDialog,
                  onDelete: _deleteEmployee,
                  onRecordChange: _showRecordSalaryChangeDialog,
                ),
                _ExpensesTab(
                  branchId: widget.branchId,
                  palette: p,
                  canEdit: canEdit,
                  onAdd: _showAddExpenseDialog,
                  onDelete: _deleteExpense,
                ),
                _PayablesTab(
                  branchId: widget.branchId,
                  palette: p,
                  canEdit: canEdit,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: canEdit ? _buildSpeedDial() : null,
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: p.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: const BackButton(color: Colors.white),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Assets & Financials',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
          Text(
            widget.isAdmin ? 'Admin View' : 'Supervisor View',
            style:
                TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
          ),
        ],
      ),
      actions: widget.isAdmin
          ? [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Text('Supervisor Edit',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13)),
                    Switch(
                      value: _allowEditing,
                      onChanged: _toggleEditPermission,
                      activeColor: p.accent,
                    ),
                  ],
                ),
              ),
            ]
          : [
              if (!_allowEditing)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Chip(
                    label: const Text('Read-only',
                        style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.white.withOpacity(0.15),
                    labelStyle: const TextStyle(color: Colors.white),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
    );
  }

  Widget _buildSummaryBanner(bool isWide) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('dispensary_assets')
          .snapshots(),
      builder: (_, assetSnap) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('employee_salaries')
            .snapshots(),
        builder: (_, salSnap) => StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('monthly_bills')
              .snapshots(),
          builder: (_, expSnap) {
            final assets = assetSnap.data?.docs ?? [];
            final totalAssets = assets.fold<double>(
                0,
                (s, d) =>
                    s + ((d['purchasePrice'] as num?)?.toDouble() ?? 0));
            // Current value after depreciation
            final currentAssetValue = assets.fold<double>(0, (s, d) {
              final asset = DispensaryAsset.fromMap(
                  d.id, d.data() as Map<String, dynamic>);
              return s + asset.currentValue;
            });

            final salaries = salSnap.data?.docs ?? [];
            final totalSalaries = salaries.fold<double>(
                0,
                (s, d) =>
                    s +
                    (((d['baseSalary'] as num?)?.toDouble() ?? 0) -
                        ((d['advance'] as num?)?.toDouble() ?? 0) -
                        ((d['deductions'] as num?)?.toDouble() ?? 0)));

            final expenses = expSnap.data?.docs ?? [];
            final totalExpenses = expenses.fold<double>(
                0, (s, d) => s + ((d['amount'] as num?)?.toDouble() ?? 0));

            final totalMonthly = totalSalaries + totalExpenses;

            return Container(
              color: p.primary,
              padding: EdgeInsets.fromLTRB(
                  isWide ? 32 : 16, 0, isWide ? 32 : 16, 20),
              child: isWide
                  ? Row(
                      children: [
                        _summaryTile('Asset Book Value',
                            'Rs. ${_fmt(currentAssetValue)}',
                            Icons.account_balance_wallet),
                        _vDivider(),
                        _summaryTile('Original Cost',
                            'Rs. ${_fmt(totalAssets)}',
                            Icons.inventory_2),
                        _vDivider(),
                        _summaryTile('Monthly Salaries',
                            'Rs. ${_fmt(totalSalaries)}', Icons.people),
                        _vDivider(),
                        _summaryTile('Other Expenses',
                            'Rs. ${_fmt(totalExpenses)}',
                            Icons.receipt_long),
                        _vDivider(),
                        _summaryTile('Total Monthly Outflow',
                            'Rs. ${_fmt(totalMonthly)}', Icons.payments,
                            highlight: true),
                      ],
                    )
                  : Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        _summaryTile('Book Value',
                            'Rs. ${_fmt(currentAssetValue)}',
                            Icons.account_balance_wallet),
                        _summaryTile('Monthly Outflow',
                            'Rs. ${_fmt(totalMonthly)}', Icons.payments,
                            highlight: true),
                        _summaryTile('Salaries',
                            'Rs. ${_fmt(totalSalaries)}', Icons.people),
                        _summaryTile('Expenses',
                            'Rs. ${_fmt(totalExpenses)}',
                            Icons.receipt_long),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _summaryTile(String label, String value, IconData icon,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: highlight
                  ? p.accent.withOpacity(0.25)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: highlight ? p.accent : Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.65), fontSize: 11)),
              Text(value,
                  style: TextStyle(
                      color: highlight ? p.accent : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
      height: 36,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withOpacity(0.2));

  Widget _buildTabBar() {
    return Container(
      color: p.primary,
      child: TabBar(
        controller: _tab,
        indicatorColor: p.accent,
        indicatorWeight: 3,
        labelColor: p.accent,
        unselectedLabelColor: Colors.white.withOpacity(0.6),
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(icon: Icon(Icons.inventory_2, size: 18), text: 'Assets'),
          Tab(icon: Icon(Icons.people, size: 18), text: 'Salaries'),
          Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Expenses'),
          Tab(icon: Icon(Icons.payment, size: 18), text: 'Payables'),
        ],
      ),
    );
  }

  Widget _buildSpeedDial() {
    return _SpeedDialFAB(
      palette: p,
      onAddAsset: () {
        _tab.animateTo(0);
        Future.delayed(const Duration(milliseconds: 200), _showAddAssetDialog);
      },
      onAddEmployee: () {
        _tab.animateTo(1);
        Future.delayed(
            const Duration(milliseconds: 200), _showAddSalaryDialog);
      },
      onAddExpense: () {
        _tab.animateTo(2);
        Future.delayed(
            const Duration(milliseconds: 200), _showAddExpenseDialog);
      },
    );
  }

  // ─────────────────────────────────────────────
  //  ASSET DIALOGS
  // ─────────────────────────────────────────────

  void _clearAssetForm() {
    _assetNameCtrl.clear();
    _assetCategoryCtrl.clear();
    _assetPriceCtrl.clear();
    _assetNotesCtrl.clear();
    _repairCostCtrl.clear();
    _damageCtrl.clear();
    _depreciationCtrl.clear();
    _assetDate = DateTime.now();
    _repairDate = null;
  }

  void _showAddAssetDialog() => _showAssetDialog();
  void _showEditAssetDialog(DispensaryAsset asset) =>
      _showAssetDialog(asset: asset);

  void _showAssetDialog({DispensaryAsset? asset}) {
    final isEdit = asset != null;
    if (isEdit) {
      _assetNameCtrl.text = asset!.name;
      _assetCategoryCtrl.text = asset.category;
      _assetPriceCtrl.text = asset.purchasePrice.toStringAsFixed(0);
      _assetNotesCtrl.text = asset.notes;
      _assetDate = asset.purchaseDate;
      _repairDate = asset.repairDate;
      _repairCostCtrl.text = asset.repairCost?.toStringAsFixed(0) ?? '';
      _damageCtrl.text = asset.damageDescription ?? '';
      _depreciationCtrl.text = asset.depreciationRate > 0
          ? asset.depreciationRate.toStringAsFixed(1)
          : '';
    } else {
      _clearAssetForm();
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        return _StyledDialog(
          palette: p,
          title: isEdit ? 'Edit Asset' : 'Add Asset',
          icon: isEdit ? Icons.edit : Icons.inventory_2,
          width: 640,
          formKey: _assetFormKey,
          content: [
            _row([
              _field(_assetNameCtrl, 'Asset Name', required: true),
              _field(_assetCategoryCtrl, 'Category', required: true),
            ]),
            _row([
              _field(_assetPriceCtrl, 'Purchase Price (Rs.)',
                  required: true, number: true),
              _datePicker('Purchase Date', _assetDate,
                  (d) => setLocal(() => _assetDate = d!)),
            ]),
            // Depreciation section
            _sectionDivider('Depreciation'),
            _row([
              _field(
                _depreciationCtrl,
                'Annual Depreciation Rate (%)',
                number: true,
                hint: 'e.g. 10 for 10% per year',
              ),
              // Live preview
              StatefulBuilder(builder: (_, setSub) {
                final price =
                    double.tryParse(_assetPriceCtrl.text) ?? 0;
                final rate =
                    double.tryParse(_depreciationCtrl.text) ?? 0;
                final years = DateTime.now()
                        .difference(_assetDate)
                        .inDays /
                    365.0;
                final current = rate > 0
                    ? (price * pow(1 - rate / 100, years))
                        .clamp(0.0, price)
                    : price;
                final depreciated = price - current;
                return Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: p.accent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.accent.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Book Value',
                          style: TextStyle(color: p.sub, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        'Rs. ${_fmt(current)}',
                        style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (depreciated > 0)
                        Text(
                          'Depreciated: Rs. ${_fmt(depreciated)}',
                          style: TextStyle(
                              color: p.danger, fontSize: 11),
                        ),
                    ],
                  ),
                );
              }),
            ]),
            _field(_assetNotesCtrl, 'Notes', maxLines: 2),
            _sectionDivider('Damage & Repair (Optional)'),
            _field(_damageCtrl, 'Damage Description', maxLines: 2),
            _row([
              _datePicker('Repair Date', _repairDate,
                  (d) => setLocal(() => _repairDate = d)),
              _field(_repairCostCtrl, 'Repair Cost (Rs.)', number: true),
            ]),
          ],
          onSave: () async {
            if (!_assetFormKey.currentState!.validate()) return false;
            final data = {
              'name': _assetNameCtrl.text.trim(),
              'category': _assetCategoryCtrl.text.trim(),
              'purchasePrice': double.parse(_assetPriceCtrl.text),
              'purchaseDate': _assetDate,
              'notes': _assetNotesCtrl.text.trim(),
              'damageDescription': _damageCtrl.text.isEmpty
                  ? null
                  : _damageCtrl.text.trim(),
              'repairDate': _repairDate,
              'repairCost': _repairCostCtrl.text.isEmpty
                  ? null
                  : double.tryParse(_repairCostCtrl.text),
              'depreciationRate':
                  double.tryParse(_depreciationCtrl.text) ?? 0.0,
            };
            final ref = FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('dispensary_assets');
            isEdit
                ? await ref.doc(asset!.id).update(data)
                : await ref.add(data);
            return true;
          },
          saveLabel: isEdit ? 'Update Asset' : 'Save Asset',
        );
      }),
    );
  }

  Future<void> _deleteAsset(String id, String name) async {
    final confirmed = await _confirmDelete(context, 'asset "$name"');
    if (!confirmed) return;
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('dispensary_assets')
        .doc(id)
        .delete();
    _snack('$name deleted', p.danger);
  }

  // ─────────────────────────────────────────────
  //  SALARY DIALOGS
  // ─────────────────────────────────────────────

  void _clearSalaryForm() {
    _empNameCtrl.clear();
    _empDesignationCtrl.clear();
    _empCnicCtrl.clear();
    _empSalaryCtrl.clear();
    _empAdvanceCtrl.clear();
    _empDeductionCtrl.clear();
    _empNotesCtrl.clear();
    _empIncrementRateCtrl.clear();
    _empNoIncrement = false;
    _empJoiningDate = DateTime.now();
  }

  void _showAddSalaryDialog() => _showSalaryDialog();
  void _showEditSalaryDialog(EmployeeSalary emp) =>
      _showSalaryDialog(employee: emp);

  void _showSalaryDialog({EmployeeSalary? employee}) {
    final isEdit = employee != null;
    if (isEdit) {
      _empNameCtrl.text = employee!.name;
      _empDesignationCtrl.text = employee.designation;
      _empCnicCtrl.text = employee.cnic;
      _empSalaryCtrl.text = employee.baseSalary.toStringAsFixed(0);
      _empAdvanceCtrl.text =
          employee.advance > 0 ? employee.advance.toStringAsFixed(0) : '';
      _empDeductionCtrl.text = employee.deductions > 0
          ? employee.deductions.toStringAsFixed(0)
          : '';
      _empNotesCtrl.text = employee.notes;
      _empJoiningDate = employee.joiningDate;
      _empIncrementRateCtrl.text = employee.defaultIncrementRate > 0
          ? employee.defaultIncrementRate.toStringAsFixed(1)
          : '';
      _empNoIncrement = employee.noIncrement;
    } else {
      _clearSalaryForm();
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        return _StyledDialog(
          palette: p,
          title: isEdit ? 'Edit Employee' : 'Add Employee',
          icon: isEdit ? Icons.edit : Icons.person_add,
          width: 620,
          formKey: _salaryFormKey,
          content: [
            _row([
              _field(_empNameCtrl, 'Full Name', required: true),
              _field(_empDesignationCtrl, 'Designation / Role',
                  required: true),
            ]),
            _row([
              _field(_empCnicCtrl, 'CNIC (optional)'),
              _datePicker('Joining Date', _empJoiningDate,
                  (d) => setLocal(() => _empJoiningDate = d!)),
            ]),
            _sectionDivider('Salary Details'),
            _row([
              _field(_empSalaryCtrl, 'Base Salary (Rs.)',
                  required: true, number: true),
              _field(_empAdvanceCtrl, 'Advance Taken (Rs.)',
                  number: true),
            ]),
            _row([
              _field(_empDeductionCtrl, 'Other Deductions (Rs.)',
                  number: true),
              _netSalaryPreview(),
            ]),
            _sectionDivider('Annual Increment Policy'),
            // No-increment toggle
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => setLocal(() {
                  _empNoIncrement = !_empNoIncrement;
                  if (_empNoIncrement) _empIncrementRateCtrl.clear();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _empNoIncrement
                        ? p.danger.withOpacity(0.07)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _empNoIncrement
                          ? p.danger.withOpacity(0.4)
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _empNoIncrement
                            ? Icons.block
                            : Icons.trending_up,
                        color: _empNoIncrement ? p.danger : p.sub,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _empNoIncrement
                                  ? 'No Increment (Exempt)'
                                  : 'Eligible for increment',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _empNoIncrement
                                    ? p.danger
                                    : p.text,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _empNoIncrement
                                  ? 'This employee will be skipped during annual increments'
                                  : 'Tap to mark as exempt from increments',
                              style: TextStyle(
                                  color: p.sub, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _empNoIncrement,
                        onChanged: (v) => setLocal(() {
                          _empNoIncrement = v;
                          if (v) _empIncrementRateCtrl.clear();
                        }),
                        activeColor: p.danger,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_empNoIncrement)
              _row([
                _field(
                  _empIncrementRateCtrl,
                  'Default Annual Increment (%)',
                  number: true,
                  hint: 'e.g. 10 for 10% per year',
                  onChanged: (_) => setLocal(() {}),
                ),
                // Live increment preview
                StatefulBuilder(builder: (_, setSub) {
                  final base =
                      double.tryParse(_empSalaryCtrl.text) ?? 0;
                  final rate = double.tryParse(
                          _empIncrementRateCtrl.text) ??
                      0;
                  final incrementAmt = base * rate / 100;
                  final newBase = base + incrementAmt;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFF43A047).withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('After next increment',
                            style: TextStyle(
                                color: p.sub, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(
                          'Rs. ${_fmt(newBase)}',
                          style: const TextStyle(
                            color: Color(0xFF43A047),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (incrementAmt > 0)
                          Text(
                            '+Rs. ${_fmt(incrementAmt)}',
                            style: const TextStyle(
                                color: Color(0xFF43A047),
                                fontSize: 11),
                          ),
                      ],
                    ),
                  );
                }),
              ]),
            _field(_empNotesCtrl, 'Notes (optional)', maxLines: 2),
          ],
          onSave: () async {
            if (!_salaryFormKey.currentState!.validate()) return false;
            final data = {
              'name': _empNameCtrl.text.trim(),
              'designation': _empDesignationCtrl.text.trim(),
              'cnic': _empCnicCtrl.text.trim(),
              'joiningDate': _empJoiningDate,
              'baseSalary': double.parse(_empSalaryCtrl.text),
              'advance': double.tryParse(_empAdvanceCtrl.text) ?? 0.0,
              'deductions':
                  double.tryParse(_empDeductionCtrl.text) ?? 0.0,
              'notes': _empNotesCtrl.text.trim(),
              'defaultIncrementRate':
                  _empNoIncrement
                      ? 0.0
                      : (double.tryParse(_empIncrementRateCtrl.text) ?? 0.0),
              'noIncrement': _empNoIncrement,
            };
            final ref = FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('employee_salaries');
            isEdit
                ? await ref.doc(employee!.id).update(data)
                : await ref.add(data);
            return true;
          },
          saveLabel: isEdit ? 'Update Employee' : 'Save Employee',
        );
      }),
    );
  }

  Widget _netSalaryPreview() {
    return StatefulBuilder(builder: (_, setS) {
      final base = double.tryParse(_empSalaryCtrl.text) ?? 0;
      final adv = double.tryParse(_empAdvanceCtrl.text) ?? 0;
      final ded = double.tryParse(_empDeductionCtrl.text) ?? 0;
      final net = base - adv - ded;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.accent.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Net Payable',
                style: TextStyle(color: p.sub, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Rs. ${_fmt(net)}',
                style: TextStyle(
                    color: net >= 0 ? p.accent : p.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
      );
    });
  }

  Future<void> _deleteEmployee(String id, String name) async {
    final confirmed = await _confirmDelete(context, 'employee "$name"');
    if (!confirmed) return;
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('employee_salaries')
        .doc(id)
        .delete();
    _snack('$name removed', p.danger);
  }

  // ─────────────────────────────────────────────
  //  SALARY CHANGE DIALOG
  // ─────────────────────────────────────────────

  void _showRecordSalaryChangeDialog(EmployeeSalary employee) {
    _salaryChangeAmtCtrl.clear();
    _salaryChangeNotesCtrl.clear();
    _salaryChangeDate = DateTime.now();

    // Default to the employee's policy rate when opening for an increment
    _salaryChangeType = employee.noIncrement ? 'advance' : 'increment';

    // Separate controller for percentage input (increment/decrement)
    final pctCtrl = TextEditingController(
      text: (!employee.noIncrement && employee.defaultIncrementRate > 0)
          ? employee.defaultIncrementRate.toStringAsFixed(1)
          : '',
    );

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        final isPercentType = _salaryChangeType == 'increment' ||
            _salaryChangeType == 'decrement';

        // Live calculation
        final pct = double.tryParse(pctCtrl.text) ?? 0;
        final flatAmt = double.tryParse(_salaryChangeAmtCtrl.text) ?? 0;

        // For inc/dec: amount derived from percentage of base salary
        final derivedAmt = isPercentType
            ? (employee.baseSalary * pct / 100)
            : flatAmt;

        double newSalary = employee.baseSalary;
        double newAdvance = employee.advance;
        double newDeductions = employee.deductions;

        if (_salaryChangeType == 'increment') newSalary += derivedAmt;
        if (_salaryChangeType == 'decrement') newSalary -= derivedAmt;
        if (_salaryChangeType == 'advance') newAdvance += flatAmt;
        if (_salaryChangeType == 'deduction') newDeductions += flatAmt;

        final newNet = newSalary - newAdvance - newDeductions;
        final hasValue = isPercentType ? pct > 0 : flatAmt > 0;

        return _StyledDialog(
          palette: p,
          title: 'Record Salary Change',
          icon: Icons.swap_vert,
          width: 540,
          formKey: _salaryChangeFormKey,
          content: [
            // ── Employee info header ──
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: p.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: p.primary.withOpacity(0.15),
                    child: Text(
                      employee.name.isNotEmpty
                          ? employee.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          color: p.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(employee.name,
                            style: TextStyle(
                                color: p.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        Text(
                          'Base Rs. ${NumberFormat('#,##0').format(employee.baseSalary)}'
                          ' · Net Rs. ${NumberFormat('#,##0').format(employee.netSalary)}',
                          style: TextStyle(color: p.sub, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // Show exemption badge if applicable
                  if (employee.noIncrement)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: p.danger.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block,
                              color: p.danger, size: 12),
                          const SizedBox(width: 4),
                          Text('Exempt',
                              style: TextStyle(
                                  color: p.danger,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  else if (employee.defaultIncrementRate > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF43A047).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF43A047).withOpacity(0.3)),
                      ),
                      child: Text(
                        '${employee.defaultIncrementRate.toStringAsFixed(1)}%/yr',
                        style: const TextStyle(
                            color: Color(0xFF43A047),
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),

            // ── Change type selector ──
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kSalaryChangeTypes.map((t) {
                  final val = t['value'] as String;
                  final label = t['label'] as String;
                  final icon = t['icon'] as IconData;
                  final color = t['color'] as Color;
                  final selected = _salaryChangeType == val;
                  // Shade exempt employees' increment option
                  final dimmed =
                      employee.noIncrement && val == 'increment';
                  return GestureDetector(
                    onTap: () {
                      setLocal(() {
                        _salaryChangeType = val;
                        // Pre-fill default rate when switching to increment
                        if (val == 'increment' &&
                            employee.defaultIncrementRate > 0 &&
                            pctCtrl.text.isEmpty) {
                          pctCtrl.text = employee.defaultIncrementRate
                              .toStringAsFixed(1);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withOpacity(0.12)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? color
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon,
                              size: 16,
                              color: selected
                                  ? color
                                  : dimmed
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade500),
                          const SizedBox(width: 6),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: selected
                                      ? color
                                      : dimmed
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade700)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Exempt warning for increment ──
            if (employee.noIncrement && _salaryChangeType == 'increment')
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.danger.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: p.danger.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: p.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This employee is marked as increment-exempt. '
                        'You can still record an override increment below.',
                        style: TextStyle(
                            color: p.danger,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Input area ──
            if (isPercentType) ...[
              // Percentage input + live Rs. breakdown
              _row([
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: pctCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: _salaryChangeType == 'increment'
                          ? 'Increment (%)'
                          : 'Decrement (%)',
                      hintText: employee.defaultIncrementRate > 0
                          ? 'Default: ${employee.defaultIncrementRate.toStringAsFixed(1)}%'
                          : 'e.g. 10',
                      hintStyle: TextStyle(
                          color: Colors.grey.shade400, fontSize: 12),
                      suffixText: '%',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: p.primary, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter a percentage';
                      }
                      final n = double.tryParse(v);
                      if (n == null || n <= 0) {
                        return 'Must be > 0';
                      }
                      return null;
                    },
                  ),
                ),
                // Derived Rs. preview tile
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12, right: 8),
                  decoration: BoxDecoration(
                    color: _changeTypeColor(_salaryChangeType)
                        .withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _changeTypeColor(_salaryChangeType)
                          .withOpacity(0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('= Rs. amount',
                          style: TextStyle(
                              color: p.sub, fontSize: 10)),
                      const SizedBox(height: 4),
                      Text(
                        pct > 0
                            ? 'Rs. ${NumberFormat('#,##0').format(derivedAmt)}'
                            : '—',
                        style: TextStyle(
                          color: _changeTypeColor(_salaryChangeType),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (pct > 0)
                        Text(
                          '$pct% of ${NumberFormat('#,##0').format(employee.baseSalary)}',
                          style: TextStyle(
                              color: p.sub, fontSize: 10),
                        ),
                    ],
                  ),
                ),
              ]),
              // Quick preset chips (use default, or common percentages)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (employee.defaultIncrementRate > 0)
                      _pctChip(
                        'Default (${employee.defaultIncrementRate.toStringAsFixed(1)}%)',
                        employee.defaultIncrementRate,
                        pctCtrl,
                        setLocal,
                        isDefault: true,
                      ),
                    for (final pctVal in [5.0, 10.0, 15.0, 20.0, 25.0])
                      if (pctVal != employee.defaultIncrementRate)
                        _pctChip(
                          '$pctVal%',
                          pctVal,
                          pctCtrl,
                          setLocal,
                        ),
                  ],
                ),
              ),
            ] else ...[
              // Flat amount input for advance / deduction
              _field(
                _salaryChangeAmtCtrl,
                _salaryChangeType == 'advance'
                    ? 'Advance Amount (Rs.)'
                    : 'Deduction Amount (Rs.)',
                required: true,
                number: true,
                onChanged: (_) => setLocal(() {}),
              ),
            ],

            _row([
              _datePicker('Effective Date', _salaryChangeDate,
                  (d) => setLocal(() => _salaryChangeDate = d!)),
              const SizedBox(), // spacer
            ]),
            _field(_salaryChangeNotesCtrl, 'Notes (optional)',
                maxLines: 2),

            // ── Effect preview bar ──
            if (hasValue)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                decoration: BoxDecoration(
                  color:
                      _changeTypeColor(_salaryChangeType).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _changeTypeColor(_salaryChangeType)
                        .withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _previewCol(
                          'Was',
                          'Rs. ${NumberFormat('#,##0').format(employee.baseSalary)}',
                          p.sub,
                        ),
                        Icon(Icons.arrow_forward,
                            color: _changeTypeColor(_salaryChangeType),
                            size: 16),
                        _previewCol(
                          'New Base',
                          'Rs. ${NumberFormat('#,##0').format(newSalary)}',
                          _changeTypeColor(_salaryChangeType),
                        ),
                        _previewCol(
                          'Net Pay',
                          'Rs. ${NumberFormat('#,##0').format(newNet)}',
                          newNet >= 0 ? p.accent : p.danger,
                        ),
                      ],
                    ),
                    if (isPercentType && pct > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              _changeTypeColor(_salaryChangeType)
                                  .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_salaryChangeType == 'decrement' ? '−' : '+'}${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%'
                          ' = ${_salaryChangeType == 'decrement' ? '−' : '+'}Rs. ${NumberFormat('#,##0').format(derivedAmt)}',
                          style: TextStyle(
                            color: _changeTypeColor(_salaryChangeType),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
          onSave: () async {
            if (!_salaryChangeFormKey.currentState!.validate()) {
              return false;
            }

            final double appliedPct =
                isPercentType ? (double.tryParse(pctCtrl.text) ?? 0) : 0;
            final double amt = isPercentType
                ? (employee.baseSalary * appliedPct / 100)
                : (double.tryParse(_salaryChangeAmtCtrl.text) ?? 0);

            final empRef = FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('employee_salaries')
                .doc(employee.id);

            final Map<String, dynamic> updateData = {};
            double updatedBaseSalary = employee.baseSalary;

            if (_salaryChangeType == 'increment') {
              updatedBaseSalary += amt;
              updateData['baseSalary'] = updatedBaseSalary;
            } else if (_salaryChangeType == 'decrement') {
              updatedBaseSalary -= amt;
              updateData['baseSalary'] = updatedBaseSalary;
            } else if (_salaryChangeType == 'advance') {
              updateData['advance'] = employee.advance + amt;
            } else if (_salaryChangeType == 'deduction') {
              updateData['deductions'] = employee.deductions + amt;
            }

            await empRef.update(updateData);

            // Record history with percentage for inc/dec
            await empRef.collection('salary_history').add({
              'type': _salaryChangeType,
              'amount': amt,
              if (isPercentType) 'percentage': appliedPct,
              'previousSalary': employee.baseSalary,
              'newSalary': updatedBaseSalary,
              'date': _salaryChangeDate,
              'notes': _salaryChangeNotesCtrl.text.trim(),
              'recordedAt': FieldValue.serverTimestamp(),
            });

            return true;
          },
          saveLabel: 'Record Change',
        );
      }),
    );
  }

  /// Small percentage preset chip
  Widget _pctChip(
    String label,
    double pctVal,
    TextEditingController ctrl,
    StateSetter setLocal, {
    bool isDefault = false,
  }) {
    final color = isDefault
        ? const Color(0xFF43A047)
        : Colors.blueGrey.shade600;
    return GestureDetector(
      onTap: () => setLocal(() {
        ctrl.text = pctVal == pctVal.roundToDouble()
            ? pctVal.toInt().toString()
            : pctVal.toStringAsFixed(1);
      }),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: color.withOpacity(0.35), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: isDefault ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _previewCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: p.sub, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  EXPENSE DIALOGS
  // ─────────────────────────────────────────────

  void _clearExpenseForm() {
    _expNameCtrl.clear();
    _expAmountCtrl.clear();
    _expNotesCtrl.clear();
    _expCategory = 'Miscellaneous';
  }

  void _showAddExpenseDialog() {
    _clearExpenseForm();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        return _StyledDialog(
          palette: p,
          title: 'Add Monthly Expense',
          icon: Icons.add_card,
          width: 500,
          formKey: _expenseFormKey,
          content: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kExpenseCategories.map((cat) {
                final label = cat['label'] as String;
                final icon = cat['icon'] as IconData;
                final selected = _expCategory == label;
                return GestureDetector(
                  onTap: () => setLocal(() => _expCategory = label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? _categoryColor(label, p).withOpacity(0.15)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selected
                              ? _categoryColor(label, p)
                              : Colors.transparent,
                          width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon,
                            size: 16,
                            color: selected
                                ? _categoryColor(label, p)
                                : Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: selected
                                    ? _categoryColor(label, p)
                                    : Colors.grey.shade700)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _field(
                _expNameCtrl,
                'Description (e.g. "Monthly tea budget")',
                required: true),
            _row([
              _field(_expAmountCtrl, 'Base Amount (Rs.)',
                  required: true, number: true),
            ]),
            _field(_expNotesCtrl, 'Notes (optional)', maxLines: 2),
          ],
          onSave: () async {
            if (!_expenseFormKey.currentState!.validate()) return false;
            await FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('monthly_bills')
                .add({
              'name': _expNameCtrl.text.trim(),
              'category': _expCategory,
              'amount': double.parse(_expAmountCtrl.text),
              'notes': _expNotesCtrl.text.trim(),
              'addedAt': FieldValue.serverTimestamp(),
            });
            return true;
          },
          saveLabel: 'Save Expense',
        );
      }),
    );
  }

  Future<void> _deleteExpense(String id, String name) async {
    final confirmed = await _confirmDelete(context, 'expense "$name"');
    if (!confirmed) return;
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('monthly_bills')
        .doc(id)
        .delete();
    _snack('$name removed', p.danger);
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────

  static String _fmt(double v) =>
      NumberFormat('#,##0', 'en_US').format(v.abs());

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12))));
  }

  Future<bool> _confirmDelete(BuildContext ctx, String target) async {
    return await showDialog<bool>(
          context: ctx,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Confirm Delete',
                style: TextStyle(fontWeight: FontWeight.w700)),
            content: Text('Are you sure you want to delete $target?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: p.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    bool number = false,
    int maxLines = 1,
    String? hint,
    void Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: number ? TextInputType.number : null,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: p.primary, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        validator: required
            ? (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (number && double.tryParse(v) == null) {
                  return 'Invalid number';
                }
                return null;
              }
            : null,
      ),
    );
  }

  Widget _datePicker(
      String label, DateTime? date, Function(DateTime?) onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            builder: (context, child) => Theme(
              data: ThemeData.light().copyWith(
                  colorScheme:
                      ColorScheme.light(primary: p.primary)),
              child: child!,
            ),
          );
          if (d != null) onPick(d);
        },
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            suffixIcon:
                Icon(Icons.calendar_today, color: p.primary, size: 18),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: Text(
            date == null
                ? 'Not set'
                : DateFormat('dd MMM yyyy').format(date),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => Row(
        children: children
            .map((w) => Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: w,
                )))
            .toList(),
      );

  Widget _sectionDivider(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade300)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(label,
                  style: TextStyle(
                      color: p.sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────
//  STYLED DIALOG
// ─────────────────────────────────────────────

class _StyledDialog extends StatelessWidget {
  final _Palette palette;
  final String title;
  final IconData icon;
  final double width;
  final GlobalKey<FormState> formKey;
  final List<Widget> content;
  final Future<bool> Function() onSave;
  final String saveLabel;

  const _StyledDialog({
    required this.palette,
    required this.title,
    required this.icon,
    required this.width,
    required this.formKey,
    required this.content,
    required this.onSave,
    required this.saveLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        decoration: BoxDecoration(
          color: palette.primary.withOpacity(0.05),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: palette.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.text)),
          ],
        ),
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 16),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: content,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('Cancel', style: TextStyle(color: palette.sub)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
          ),
          onPressed: () async {
            final ok = await onSave();
            if (ok && context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('$saveLabel successful!'),
                  backgroundColor: palette.accent,
                  behavior: SnackBarBehavior.floating));
            }
          },
          child: Text(saveLabel,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  ASSETS TAB
// ─────────────────────────────────────────────

class _AssetsTab extends StatelessWidget {
  final String branchId;
  final _Palette palette;
  final bool canEdit;
  final VoidCallback onAdd;
  final Function(DispensaryAsset) onEdit;
  final Function(String, String) onDelete;

  const _AssetsTab({
    required this.branchId,
    required this.palette,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('dispensary_assets')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child:
                  CircularProgressIndicator(color: palette.primary));
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.inventory_2_outlined,
            label: 'No assets added yet',
            sub: canEdit ? 'Tap + to add your first asset' : '',
            palette: palette,
          );
        }

        final assets = docs
            .map((d) => DispensaryAsset.fromMap(
                d.id, d.data() as Map<String, dynamic>))
            .toList();

        // Total book value banner
        final totalPurchase =
            assets.fold<double>(0, (s, a) => s + a.purchasePrice);
        final totalCurrent =
            assets.fold<double>(0, (s, a) => s + a.currentValue);
        final isWide = MediaQuery.of(context).size.width > 700;

        return Column(
          children: [
            // Depreciation summary bar
            Container(
              margin: EdgeInsets.fromLTRB(
                  isWide ? 24 : 12, isWide ? 16 : 10, isWide ? 24 : 12, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.accent.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: palette.accent.withOpacity(0.25), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_down, color: palette.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${assets.length} assets · Original: Rs. ${NumberFormat('#,##0').format(totalPurchase)}',
                      style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Book Value',
                          style: TextStyle(
                              color: palette.sub, fontSize: 10)),
                      Text(
                        'Rs. ${NumberFormat('#,##0').format(totalCurrent)}',
                        style: TextStyle(
                            color: palette.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      if (totalPurchase - totalCurrent > 0)
                        Text(
                          '↓ Rs. ${NumberFormat('#,##0').format(totalPurchase - totalCurrent)} depreciated',
                          style: TextStyle(
                              color: palette.danger, fontSize: 10),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(isWide ? 24 : 12),
                itemCount: assets.length,
                itemBuilder: (_, i) => _AssetCard(
                  asset: assets[i],
                  palette: palette,
                  canEdit: canEdit,
                  onEdit: onEdit,
                  onDelete: onDelete,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AssetCard extends StatelessWidget {
  final DispensaryAsset asset;
  final _Palette palette;
  final bool canEdit;
  final Function(DispensaryAsset) onEdit;
  final Function(String, String) onDelete;

  const _AssetCard({
    required this.asset,
    required this.palette,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasRepair = asset.repairDate != null || asset.repairCost != null;
    final hasDepreciation = asset.depreciationRate > 0;
    final depreciationPct = hasDepreciation
        ? (asset.totalDepreciated / asset.purchasePrice * 100)
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: palette.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child:
              Icon(Icons.inventory_2, color: palette.primary, size: 22),
        ),
        title: Text(asset.name,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: palette.text,
                fontSize: 15)),
        subtitle: Row(
          children: [
            Text(asset.category,
                style: TextStyle(color: palette.sub, fontSize: 12)),
            const SizedBox(width: 8),
            if (hasDepreciation)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                    '${asset.depreciationRate.toStringAsFixed(0)}%/yr',
                    style: TextStyle(
                        color: palette.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 4),
            if (hasRepair)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Repaired',
                    style: TextStyle(
                        color: palette.danger,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Current book value (or purchase price if no depreciation)
                Text(
                  'Rs. ${NumberFormat('#,##0').format(hasDepreciation ? asset.currentValue : asset.purchasePrice)}',
                  style: TextStyle(
                      color: palette.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                if (hasDepreciation)
                  Text(
                    'Cost: ${NumberFormat('#,##0').format(asset.purchasePrice)}',
                    style: TextStyle(
                        color: palette.sub,
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough),
                  )
                else
                  Text(
                      DateFormat('dd MMM yyyy')
                          .format(asset.purchaseDate),
                      style:
                          TextStyle(color: palette.sub, fontSize: 11)),
              ],
            ),
            if (canEdit) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit(asset);
                  if (v == 'delete') onDelete(asset.id, asset.name);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('Edit')
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete,
                            size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: Colors.red))
                      ])),
                ],
              ),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailChip(Icons.calendar_today, 'Purchase Date',
                    DateFormat('dd MMM yyyy').format(asset.purchaseDate),
                    palette.sub),
                if (hasDepreciation) ...[
                  _DetailChip(
                      Icons.trending_down,
                      'Depreciation',
                      '${asset.depreciationRate.toStringAsFixed(1)}% / year  →  ${depreciationPct.toStringAsFixed(1)}% depreciated',
                      palette.accent),
                  _DetailChip(
                      Icons.account_balance_wallet,
                      'Current Book Value',
                      'Rs. ${NumberFormat('#,##0').format(asset.currentValue)}  (lost Rs. ${NumberFormat('#,##0').format(asset.totalDepreciated)})',
                      palette.accent),
                ],
                if (asset.notes.isNotEmpty)
                  _DetailChip(
                      Icons.notes, 'Notes', asset.notes, palette.sub),
                if (asset.damageDescription != null)
                  _DetailChip(Icons.warning_amber, 'Damage',
                      asset.damageDescription!, palette.danger),
                if (asset.repairDate != null)
                  _DetailChip(
                      Icons.build,
                      'Repair Date',
                      DateFormat('dd MMM yyyy')
                          .format(asset.repairDate!),
                      palette.danger),
                if (asset.repairCost != null)
                  _DetailChip(
                      Icons.attach_money,
                      'Repair Cost',
                      'Rs. ${NumberFormat('#,##0').format(asset.repairCost!)}',
                      palette.danger),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailChip(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SALARY TAB
// ─────────────────────────────────────────────

class _SalaryTab extends StatelessWidget {
  final String branchId;
  final _Palette palette;
  final bool canEdit;
  final VoidCallback onAdd;
  final Function(EmployeeSalary) onEdit;
  final Function(String, String) onDelete;
  final Function(EmployeeSalary) onRecordChange; // NEW

  const _SalaryTab({
    required this.branchId,
    required this.palette,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRecordChange,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('employee_salaries')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child:
                  CircularProgressIndicator(color: palette.primary));
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.people_outline,
            label: 'No employees added yet',
            sub: canEdit ? 'Tap + to add an employee' : '',
            palette: palette,
          );
        }

        final employees = docs
            .map((d) => EmployeeSalary.fromMap(
                d.id, d.data() as Map<String, dynamic>))
            .toList();

        final totalPayable =
            employees.fold<double>(0, (s, e) => s + e.netSalary);
        final isWide = MediaQuery.of(context).size.width > 700;

        return Column(
          children: [
            Container(
              margin: EdgeInsets.fromLTRB(
                  isWide ? 24 : 12, isWide ? 16 : 10, isWide ? 24 : 12, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: palette.accent.withOpacity(0.3), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: palette.accent),
                  const SizedBox(width: 10),
                  Text('${employees.length} Employees',
                      style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total Payable',
                          style: TextStyle(
                              color: palette.sub, fontSize: 11)),
                      Text(
                        'Rs. ${NumberFormat('#,##0').format(totalPayable)}',
                        style: TextStyle(
                            color: palette.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(isWide ? 24 : 12),
                itemCount: employees.length,
                itemBuilder: (_, i) => _EmployeeCard(
                  employee: employees[i],
                  branchId: branchId,
                  palette: palette,
                  canEdit: canEdit,
                  onEdit: onEdit,
                  onDelete: onDelete,
                  onRecordChange: onRecordChange,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final EmployeeSalary employee;
  final String branchId;
  final _Palette palette;
  final bool canEdit;
  final Function(EmployeeSalary) onEdit;
  final Function(String, String) onDelete;
  final Function(EmployeeSalary) onRecordChange;

  const _EmployeeCard({
    required this.employee,
    required this.branchId,
    required this.palette,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
    required this.onRecordChange,
  });

  void _showHistorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.history, color: palette.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${employee.name} — Salary History',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('branches')
                      .doc(branchId)
                      .collection('employee_salaries')
                      .doc(employee.id)
                      .collection('salary_history')
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (_, snap) {
                    if (snap.connectionState ==
                        ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(
                              color: palette.primary));
                    }
                    final entries = (snap.data?.docs ?? [])
                        .map((d) => SalaryHistoryEntry.fromMap(
                            d.id,
                            d.data() as Map<String, dynamic>))
                        .toList();

                    if (entries.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off,
                                size: 48,
                                color: palette.sub.withOpacity(0.4)),
                            const SizedBox(height: 12),
                            Text('No changes recorded yet',
                                style: TextStyle(
                                    color: palette.sub, fontSize: 14)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        final color = _changeTypeColor(e.type);
                        final icon = _changeTypeIcon(e.type);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: color.withOpacity(0.2),
                                width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                                child: Icon(icon,
                                    color: color, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          e.type[0].toUpperCase() +
                                              e.type.substring(1),
                                          style: TextStyle(
                                              color: color,
                                              fontWeight:
                                                  FontWeight.w700,
                                              fontSize: 13),
                                        ),
                                        const Spacer(),
                                        Text(
                                          DateFormat('dd MMM yyyy')
                                              .format(e.date),
                                          style: TextStyle(
                                              color: palette.sub,
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (e.type == 'increment' ||
                                        e.type == 'decrement')
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Show percentage prominently if stored
                                          if (e.percentage != null)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  bottom: 4),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color:
                                                    color.withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${e.type == 'decrement' ? '−' : '+'}${e.percentage!.toStringAsFixed(e.percentage == e.percentage!.roundToDouble() ? 0 : 1)}%'
                                                ' = ${e.type == 'decrement' ? '−' : '+'}Rs. ${NumberFormat('#,##0').format(e.amount)}',
                                                style: TextStyle(
                                                    color: color,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    fontSize: 12),
                                              ),
                                            ),
                                          Text(
                                            'Rs. ${NumberFormat('#,##0').format(e.previousSalary)} → Rs. ${NumberFormat('#,##0').format(e.newSalary)}',
                                            style: TextStyle(
                                                color: palette.sub,
                                                fontSize: 12),
                                          ),
                                        ],
                                      )
                                    else
                                      Text(
                                        '+ Rs. ${NumberFormat('#,##0').format(e.amount)}',
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w600),
                                      ),
                                    if (e.notes.isNotEmpty)
                                      Text(e.notes,
                                          style: TextStyle(
                                              color: palette.sub,
                                              fontSize: 11,
                                              fontStyle:
                                                  FontStyle.italic)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDeductions =
        employee.advance > 0 || employee.deductions > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: palette.primary.withOpacity(0.1),
          child: Text(
            employee.name.isNotEmpty
                ? employee.name[0].toUpperCase()
                : '?',
            style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(employee.name,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: palette.text,
                fontSize: 15)),
        subtitle: Row(
          children: [
            Text(employee.designation,
                style: TextStyle(color: palette.sub, fontSize: 12)),
            const SizedBox(width: 6),
            if (employee.noIncrement)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: palette.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('No Increment',
                    style: TextStyle(
                        color: palette.danger,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              )
            else if (employee.defaultIncrementRate > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF43A047).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                    '${employee.defaultIncrementRate.toStringAsFixed(employee.defaultIncrementRate == employee.defaultIncrementRate.roundToDouble() ? 0 : 1)}%/yr',
                    style: const TextStyle(
                        color: Color(0xFF43A047),
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs. ${NumberFormat('#,##0').format(employee.netSalary)}',
                  style: TextStyle(
                      color: palette.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                if (hasDeductions)
                  Text(
                    'Base: ${NumberFormat('#,##0').format(employee.baseSalary)}',
                    style: TextStyle(
                        color: palette.sub,
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough),
                  ),
              ],
            ),
            if (canEdit) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit(employee);
                  if (v == 'change') onRecordChange(employee);
                  if (v == 'history') _showHistorySheet(context);
                  if (v == 'delete') onDelete(employee.id, employee.name);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('Edit Details')
                      ])),
                  const PopupMenuItem(
                      value: 'change',
                      child: Row(children: [
                        Icon(Icons.swap_vert,
                            size: 16, color: Color(0xFF43A047)),
                        SizedBox(width: 8),
                        Text('Record Change',
                            style: TextStyle(
                                color: Color(0xFF43A047)))
                      ])),
                  const PopupMenuItem(
                      value: 'history',
                      child: Row(children: [
                        Icon(Icons.history, size: 16),
                        SizedBox(width: 8),
                        Text('View History')
                      ])),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete,
                            size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: Colors.red))
                      ])),
                ],
              ),
            ] else ...[
              // Read-only: still show history
              IconButton(
                icon: Icon(Icons.history, size: 18, color: palette.sub),
                onPressed: () => _showHistorySheet(context),
                tooltip: 'View History',
              ),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (employee.cnic.isNotEmpty)
                  _DetailChip(
                      Icons.badge, 'CNIC', employee.cnic, palette.sub),
                _DetailChip(
                    Icons.calendar_today,
                    'Joined',
                    DateFormat('dd MMM yyyy')
                        .format(employee.joiningDate),
                    palette.sub),
                _DetailChip(
                    Icons.payments,
                    'Base Salary',
                    'Rs. ${NumberFormat('#,##0').format(employee.baseSalary)}',
                    palette.text),
                if (employee.advance > 0)
                  _DetailChip(
                      Icons.money_off,
                      'Advance',
                      '- Rs. ${NumberFormat('#,##0').format(employee.advance)}',
                      palette.danger),
                if (employee.deductions > 0)
                  _DetailChip(
                      Icons.remove_circle_outline,
                      'Deductions',
                      '- Rs. ${NumberFormat('#,##0').format(employee.deductions)}',
                      palette.danger),
                if (employee.notes.isNotEmpty)
                  _DetailChip(
                      Icons.notes, 'Notes', employee.notes, palette.sub),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  EXPENSES TAB
// ─────────────────────────────────────────────

class _ExpensesTab extends StatelessWidget {
  final String branchId;
  final _Palette palette;
  final bool canEdit;
  final VoidCallback onAdd;
  final Function(String, String) onDelete;

  const _ExpensesTab({
    required this.branchId,
    required this.palette,
    required this.canEdit,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('monthly_bills')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child:
                  CircularProgressIndicator(color: palette.primary));
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.receipt_long_outlined,
            label: 'No recurring expenses recorded',
            sub: canEdit ? 'Tap + to add a monthly expense' : '',
            palette: palette,
          );
        }

        final expenses = docs
            .map((d) => OperatingExpense.fromMap(
                d.id, d.data() as Map<String, dynamic>))
            .toList();

        final Map<String, List<OperatingExpense>> grouped = {};
        for (final e in expenses) {
          grouped.putIfAbsent(e.category, () => []).add(e);
        }

        final totalExpenses =
            expenses.fold<double>(0, (s, e) => s + e.amount);
        final isWide = MediaQuery.of(context).size.width > 700;

        return ListView(
          padding: EdgeInsets.all(isWide ? 24 : 12),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: palette.accent.withOpacity(0.3), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long, color: palette.accent),
                  const SizedBox(width: 10),
                  Text('Monthly Recurring Expenses',
                      style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    'Rs. ${NumberFormat('#,##0').format(totalExpenses)}',
                    style: TextStyle(
                        color: palette.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
            ...grouped.entries.map((entry) {
              final cat = entry.key;
              final items = entry.value;
              final catTotal =
                  items.fold<double>(0, (s, e) => s + e.amount);
              final catColor = _categoryColor(cat, palette);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(_categoryIcon(cat),
                              color: catColor, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text(cat,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: palette.text,
                                fontSize: 14)),
                        const Spacer(),
                        Text(
                          'Rs. ${NumberFormat('#,##0').format(catTotal)}',
                          style: TextStyle(
                              color: catColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  ...items.map((exp) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        color: catColor.withOpacity(0.04),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: catColor.withOpacity(0.15),
                              width: 1),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          title: Text(exp.name,
                              style: TextStyle(
                                  color: palette.text,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14)),
                          subtitle: exp.notes.isNotEmpty
                              ? Text(exp.notes,
                                  style: TextStyle(
                                      color: palette.sub,
                                      fontSize: 12))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Rs. ${NumberFormat('#,##0').format(exp.amount)}',
                                style: TextStyle(
                                    color: catColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                              if (canEdit) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () =>
                                      onDelete(exp.id, exp.name),
                                  child: Icon(Icons.delete_outline,
                                      color: palette.danger, size: 20),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 8),
                ],
              );
            }),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  PAYABLES TAB  (NEW)
// ─────────────────────────────────────────────

class _PayablesTab extends StatefulWidget {
  final String branchId;
  final _Palette palette;
  final bool canEdit;

  const _PayablesTab({
    required this.branchId,
    required this.palette,
    required this.canEdit,
  });

  @override
  State<_PayablesTab> createState() => _PayablesTabState();
}

class _PayablesTabState extends State<_PayablesTab> {
  late int _month;
  late int _year;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
  }

  _Palette get p => widget.palette;

  /// Firestore doc-ID friendly key e.g. "2026_03"
  String get _monthKey =>
      '${_year}_${_month.toString().padLeft(2, '0')}';

  String get _monthLabel =>
      DateFormat('MMMM yyyy').format(DateTime(_year, _month));

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month == now.month && _year == now.year;
  }

  bool get _isFutureMonth {
    final now = DateTime.now();
    return DateTime(_year, _month)
        .isAfter(DateTime(now.year, now.month));
  }

  void _prevMonth() => setState(() {
        if (_month == 1) {
          _month = 12;
          _year--;
        } else {
          _month--;
        }
      });

  void _nextMonth() => setState(() {
        if (_month == 12) {
          _month = 1;
          _year++;
        } else {
          _month++;
        }
      });

  // ── Payroll actions ──

  Future<void> _markSalaryPaid(EmployeeSalary emp) async {
    final docId = '${emp.id}_$_monthKey';
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('payroll_records')
        .doc(docId)
        .set({
      'employeeId': emp.id,
      'employeeName': emp.name,
      'month': _month,
      'year': _year,
      'baseSalary': emp.baseSalary,
      'advance': emp.advance,
      'deductions': emp.deductions,
      'netSalary': emp.netSalary,
      'paid': true,
      'paidAt': FieldValue.serverTimestamp(),
      'notes': '',
    });
  }

  Future<void> _markSalaryUnpaid(String empId) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('payroll_records')
        .doc('${empId}_$_monthKey')
        .delete();
  }

  // ── Expense payment actions ──

  Future<void> _markExpensePaid(
      OperatingExpense exp, double actualAmount) async {
    final docId = '${exp.id}_$_monthKey';
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('expense_payment_records')
        .doc(docId)
        .set({
      'expenseId': exp.id,
      'name': exp.name,
      'category': exp.category,
      'baseAmount': exp.amount,
      'actualAmount': actualAmount,
      'month': _month,
      'year': _year,
      'paid': true,
      'paidAt': FieldValue.serverTimestamp(),
      'notes': '',
    });
  }

  Future<void> _markExpenseUnpaid(String expId) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('expense_payment_records')
        .doc('${expId}_$_monthKey')
        .delete();
  }

  // ── Expense pay dialog ──

  void _showExpensePayDialog(OperatingExpense exp) {
    final ctrl =
        TextEditingController(text: exp.amount.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _categoryColor(exp.category, p).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_categoryIcon(exp.category),
                  color: _categoryColor(exp.category, p), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mark as Paid',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: p.text)),
                  Text(exp.name,
                      style: TextStyle(color: p.sub, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Base amount: Rs. ${NumberFormat('#,##0').format(exp.amount)}',
              style: TextStyle(color: p.sub, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Enter the actual amount paid this month:',
              style: TextStyle(color: p.text, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Actual Amount (Rs.)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: p.primary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixText: 'Rs. ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: p.sub)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF43A047),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
            ),
            onPressed: () {
              final amount =
                  double.tryParse(ctrl.text) ?? exp.amount;
              _markExpensePaid(exp, amount);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirm Payment',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Column(
      children: [
        // ── Month navigation header ──
        Container(
          color: p.primary.withOpacity(0.04),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: p.primary),
                onPressed: _prevMonth,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _monthLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: p.text),
                    ),
                    if (_isCurrentMonth)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Current Month',
                            style: TextStyle(
                                color: p.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: _isFutureMonth
                        ? Colors.grey.shade300
                        : p.primary),
                onPressed: _isFutureMonth ? null : _nextMonth,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Streams ──
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('employee_salaries')
                .snapshots(),
            builder: (_, empSnap) =>
                StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('payroll_records')
                  .where('month', isEqualTo: _month)
                  .where('year', isEqualTo: _year)
                  .snapshots(),
              builder: (_, paySnap) =>
                  StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('monthly_bills')
                    .snapshots(),
                builder: (_, expSnap) =>
                    StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('branches')
                      .doc(widget.branchId)
                      .collection('expense_payment_records')
                      .where('month', isEqualTo: _month)
                      .where('year', isEqualTo: _year)
                      .snapshots(),
                  builder: (_, expPaySnap) {
                    if (empSnap.connectionState ==
                        ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(
                              color: p.primary));
                    }

                    // Build employee list + payroll map
                    final employees = (empSnap.data?.docs ?? [])
                        .map((d) => EmployeeSalary.fromMap(d.id,
                            d.data() as Map<String, dynamic>))
                        .toList();

                    final payrollMap = <String, PayrollRecord>{};
                    for (final d in paySnap.data?.docs ?? []) {
                      final rec = PayrollRecord.fromMap(d.id,
                          d.data() as Map<String, dynamic>);
                      payrollMap[rec.employeeId] = rec;
                    }

                    // Build expense list + payment map
                    final expenses = (expSnap.data?.docs ?? [])
                        .map((d) => OperatingExpense.fromMap(d.id,
                            d.data() as Map<String, dynamic>))
                        .toList();

                    final expPayMap =
                        <String, ExpensePaymentRecord>{};
                    for (final d in expPaySnap.data?.docs ?? []) {
                      final rec = ExpensePaymentRecord.fromMap(d.id,
                          d.data() as Map<String, dynamic>);
                      expPayMap[rec.expenseId] = rec;
                    }

                    // Summary numbers
                    final salTotal = employees.fold<double>(
                        0, (s, e) => s + e.netSalary);
                    final salPaid = payrollMap.values
                        .where((r) => r.paid)
                        .fold<double>(0, (s, r) => s + r.netSalary);
                    final salUnpaid = employees
                        .where((e) => payrollMap[e.id] == null)
                        .length;

                    final expTotal = expenses.fold<double>(
                        0, (s, e) => s + e.amount);
                    final expPaid = expPayMap.values
                        .where((r) => r.paid)
                        .fold<double>(
                            0, (s, r) => s + r.actualAmount);
                    final expUnpaid = expenses
                        .where((e) => expPayMap[e.id] == null)
                        .length;

                    return ListView(
                      padding: EdgeInsets.all(isWide ? 20 : 12),
                      children: [
                        // ── Grand total bar ──
                        _GrandTotalBar(
                          palette: p,
                          salTotal: salTotal,
                          salPaid: salPaid,
                          expTotal: expTotal,
                          expPaid: expPaid,
                        ),
                        const SizedBox(height: 20),

                        // ── Fixed payables: Salaries ──
                        _PayableSectionHeader(
                          title: 'Fixed Payables — Salaries',
                          icon: Icons.people,
                          total: salTotal,
                          paid: salPaid,
                          unpaidCount: salUnpaid,
                          palette: p,
                        ),
                        const SizedBox(height: 8),
                        if (employees.isEmpty)
                          _payableEmptyHint(
                              'No employees on record', p)
                        else
                          ...employees.map((emp) =>
                              _SalaryPayableCard(
                                employee: emp,
                                record: payrollMap[emp.id],
                                palette: p,
                                canEdit: widget.canEdit,
                                onMarkPaid: () =>
                                    _markSalaryPaid(emp),
                                onMarkUnpaid: () =>
                                    _markSalaryUnpaid(emp.id),
                              )),
                        const SizedBox(height: 24),

                        // ── Variable payables: Expenses ──
                        _PayableSectionHeader(
                          title: 'Variable Payables — Operating Costs',
                          icon: Icons.receipt_long,
                          total: expTotal,
                          paid: expPaid,
                          unpaidCount: expUnpaid,
                          palette: p,
                        ),
                        const SizedBox(height: 8),
                        if (expenses.isEmpty)
                          _payableEmptyHint(
                              'No recurring expenses on record', p)
                        else
                          ...expenses.map((exp) =>
                              _ExpensePayableCard(
                                expense: exp,
                                record: expPayMap[exp.id],
                                palette: p,
                                canEdit: widget.canEdit,
                                onMarkPaid: () =>
                                    _showExpensePayDialog(exp),
                                onMarkUnpaid: () =>
                                    _markExpenseUnpaid(exp.id),
                              )),
                        const SizedBox(height: 32),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _payableEmptyHint(String msg, _Palette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(msg,
            style: TextStyle(color: p.sub, fontSize: 13)),
      ),
    );
  }
}

// ── Grand total summary bar ──
class _GrandTotalBar extends StatelessWidget {
  final _Palette palette;
  final double salTotal, salPaid, expTotal, expPaid;

  const _GrandTotalBar({
    required this.palette,
    required this.salTotal,
    required this.salPaid,
    required this.expTotal,
    required this.expPaid,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final grandTotal = salTotal + expTotal;
    final grandPaid = salPaid + expPaid;
    final grandPending = grandTotal - grandPaid;
    final paidPct =
        grandTotal > 0 ? (grandPaid / grandTotal).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.primary, p.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: p.primary.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Outflow',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 11)),
                    Text(
                      'Rs. ${NumberFormat('#,##0').format(grandTotal)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20),
                    ),
                  ],
                ),
              ),
              _miniStat('Paid', grandPaid, Colors.greenAccent),
              const SizedBox(width: 16),
              _miniStat('Pending', grandPending, Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: paidPct,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor:
                  const AlwaysStoppedAnimation(Colors.greenAccent),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${(paidPct * 100).toStringAsFixed(0)}% paid',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.65), fontSize: 10)),
        Text(
          'Rs. ${NumberFormat('#,##0').format(value)}',
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13),
        ),
      ],
    );
  }
}

// ── Section header for payables ──
class _PayableSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final double total;
  final double paid;
  final int unpaidCount;
  final _Palette palette;

  const _PayableSectionHeader({
    required this.title,
    required this.icon,
    required this.total,
    required this.paid,
    required this.unpaidCount,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final allPaid = unpaidCount == 0;
    final pending = total - paid;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allPaid
            ? const Color(0xFF43A047).withOpacity(0.06)
            : p.danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: allPaid
              ? const Color(0xFF43A047).withOpacity(0.25)
              : p.danger.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: allPaid
                  ? const Color(0xFF43A047).withOpacity(0.12)
                  : p.danger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: allPaid
                    ? const Color(0xFF43A047)
                    : p.danger,
                size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.text,
                        fontSize: 13)),
                Text(
                  allPaid
                      ? 'All paid ✓'
                      : '$unpaidCount item${unpaidCount > 1 ? 's' : ''} unpaid',
                  style: TextStyle(
                    fontSize: 11,
                    color: allPaid
                        ? const Color(0xFF43A047)
                        : p.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Rs. ${NumberFormat('#,##0').format(total)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: p.text,
                    fontSize: 14),
              ),
              if (paid > 0)
                Text('Paid Rs. ${NumberFormat('#,##0').format(paid)}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF43A047),
                        fontWeight: FontWeight.w600)),
              if (pending > 0)
                Text(
                    'Due Rs. ${NumberFormat('#,##0').format(pending)}',
                    style: TextStyle(
                        fontSize: 10,
                        color: p.danger,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Salary payable card ──
class _SalaryPayableCard extends StatelessWidget {
  final EmployeeSalary employee;
  final PayrollRecord? record;
  final _Palette palette;
  final bool canEdit;
  final VoidCallback onMarkPaid;
  final VoidCallback onMarkUnpaid;

  const _SalaryPayableCard({
    required this.employee,
    required this.record,
    required this.palette,
    required this.canEdit,
    required this.onMarkPaid,
    required this.onMarkUnpaid,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = record?.paid ?? false;
    final p = palette;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isPaid
            ? const Color(0xFF43A047).withOpacity(0.05)
            : p.danger.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPaid
              ? const Color(0xFF43A047).withOpacity(0.3)
              : p.danger.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color:
                    isPaid ? const Color(0xFF43A047) : p.danger,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isPaid
                            ? const Color(0xFF43A047)
                            : p.danger)
                        .withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: p.primary.withOpacity(0.1),
              child: Text(
                employee.name.isNotEmpty
                    ? employee.name[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: p.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p.text,
                          fontSize: 14)),
                  Text(employee.designation,
                      style: TextStyle(
                          color: p.sub, fontSize: 12)),
                  if (isPaid && record?.paidAt != null)
                    Text(
                      'Paid on ${DateFormat('dd MMM yyyy').format(record!.paidAt!)}',
                      style: const TextStyle(
                          color: Color(0xFF43A047),
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    )
                  else if (!isPaid)
                    Text(
                      'Payment pending',
                      style: TextStyle(
                          color: p.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
            // Amount + action
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs. ${NumberFormat('#,##0').format(employee.netSalary)}',
                  style: TextStyle(
                    color: isPaid
                        ? const Color(0xFF43A047)
                        : p.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (employee.advance > 0 ||
                    employee.deductions > 0)
                  Text(
                    'Base: ${NumberFormat('#,##0').format(employee.baseSalary)}',
                    style: TextStyle(
                        color: p.sub,
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough),
                  ),
                const SizedBox(height: 4),
                if (canEdit)
                  isPaid
                      ? GestureDetector(
                          onTap: onMarkUnpaid,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius:
                                  BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.undo,
                                    size: 12,
                                    color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text('Undo',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            Colors.grey.shade600)),
                              ],
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: onMarkPaid,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF43A047),
                              borderRadius:
                                  BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF43A047)
                                      .withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check,
                                    size: 13,
                                    color: Colors.white),
                                SizedBox(width: 4),
                                Text('Pay',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight:
                                            FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Expense payable card ──
class _ExpensePayableCard extends StatelessWidget {
  final OperatingExpense expense;
  final ExpensePaymentRecord? record;
  final _Palette palette;
  final bool canEdit;
  final VoidCallback onMarkPaid;
  final VoidCallback onMarkUnpaid;

  const _ExpensePayableCard({
    required this.expense,
    required this.record,
    required this.palette,
    required this.canEdit,
    required this.onMarkPaid,
    required this.onMarkUnpaid,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = record?.paid ?? false;
    final p = palette;
    final catColor = _categoryColor(expense.category, p);
    final displayAmount =
        isPaid ? (record?.actualAmount ?? expense.amount) : expense.amount;
    final amountChanged =
        isPaid && record != null && record!.actualAmount != record!.baseAmount;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isPaid
            ? const Color(0xFF43A047).withOpacity(0.05)
            : p.danger.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPaid
              ? const Color(0xFF43A047).withOpacity(0.3)
              : p.danger.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color:
                    isPaid ? const Color(0xFF43A047) : p.danger,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isPaid
                            ? const Color(0xFF43A047)
                            : p.danger)
                        .withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            // Category icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_categoryIcon(expense.category),
                  color: catColor, size: 20),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expense.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p.text,
                          fontSize: 14)),
                  Text(expense.category,
                      style: TextStyle(
                          color: p.sub, fontSize: 12)),
                  if (isPaid && record?.paidAt != null)
                    Text(
                      'Paid on ${DateFormat('dd MMM yyyy').format(record!.paidAt!)}',
                      style: const TextStyle(
                          color: Color(0xFF43A047),
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    )
                  else if (!isPaid)
                    Text(
                      'Base: Rs. ${NumberFormat('#,##0').format(expense.amount)} — tap Pay to set actual',
                      style: TextStyle(
                          color: p.sub,
                          fontSize: 11,
                          fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            // Amount + action
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs. ${NumberFormat('#,##0').format(displayAmount)}',
                  style: TextStyle(
                    color: isPaid
                        ? const Color(0xFF43A047)
                        : p.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (amountChanged)
                  Text(
                    'Base: ${NumberFormat('#,##0').format(record!.baseAmount)}',
                    style: TextStyle(
                        color: p.sub,
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough),
                  ),
                const SizedBox(height: 4),
                if (canEdit)
                  isPaid
                      ? GestureDetector(
                          onTap: onMarkUnpaid,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius:
                                  BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.undo,
                                    size: 12,
                                    color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text('Undo',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            Colors.grey.shade600)),
                              ],
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: onMarkPaid,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: catColor,
                              borderRadius:
                                  BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: catColor.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit,
                                    size: 12,
                                    color: Colors.white),
                                SizedBox(width: 4),
                                Text('Pay',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight:
                                            FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  EMPTY STATE
// ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final _Palette palette;

  const _EmptyState({
    required this.icon,
    required this.label,
    required this.sub,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 72,
              color: palette.primary.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(label,
              style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub,
                style: TextStyle(
                    color: palette.sub, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SPEED DIAL FAB
// ─────────────────────────────────────────────

class _SpeedDialFAB extends StatefulWidget {
  final _Palette palette;
  final VoidCallback onAddAsset;
  final VoidCallback onAddEmployee;
  final VoidCallback onAddExpense;

  const _SpeedDialFAB({
    required this.palette,
    required this.onAddAsset,
    required this.onAddEmployee,
    required this.onAddExpense,
  });

  @override
  State<_SpeedDialFAB> createState() => _SpeedDialFABState();
}

class _SpeedDialFABState extends State<_SpeedDialFAB>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  late Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220));
    _expandAnim =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _rotateAnim = Tween<double>(begin: 0, end: 0.375).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  void _trigger(VoidCallback action) {
    setState(() => _open = false);
    _ctrl.reverse();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;

    final items = [
      _DialItem(
        label: 'Add Asset',
        icon: Icons.inventory_2,
        color: p.primary,
        onTap: () => _trigger(widget.onAddAsset),
      ),
      _DialItem(
        label: 'Add Employee',
        icon: Icons.person_add,
        color: const Color(0xFF5C6BC0),
        onTap: () => _trigger(widget.onAddEmployee),
      ),
      _DialItem(
        label: 'Add Expense',
        icon: Icons.add_card,
        color: const Color(0xFF8D6E63),
        onTap: () => _trigger(widget.onAddExpense),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ...items.asMap().entries.map((entry) {
          final delay = entry.key * 0.08;
          final item = entry.value;
          return AnimatedBuilder(
            animation: _expandAnim,
            builder: (_, __) {
              final progress =
                  (_expandAnim.value - delay).clamp(0.0, 1.0);
              return Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - progress)),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedOpacity(
                          opacity: progress,
                          duration: Duration.zero,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withOpacity(0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: item.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: item.onTap,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: item.color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      item.color.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(item.icon,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }).toList().reversed.toList(),
        // Main FAB
        GestureDetector(
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: _rotateAnim,
            builder: (_, child) => Transform.rotate(
              angle: _rotateAnim.value * 2 * 3.14159,
              child: child,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: _open ? Colors.grey.shade700 : p.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_open
                            ? Colors.grey.shade700
                            : p.accent)
                        .withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                _open ? Icons.close : Icons.add,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DialItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DialItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}