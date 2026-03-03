import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart';
import '../../services/donations_local_storage.dart';
import 'donations_shared.dart';
import 'credit_ledger.dart';

// ════════════════════════════════════════════════════════════════════════════════
// USER ROLES
// ════════════════════════════════════════════════════════════════════════════════

enum UserRole { staff, manager, admin, chairman }

extension UserRoleX on UserRole {
  bool get isOfficeBoy  => this == UserRole.staff;
  bool get isManager    => this == UserRole.manager;
  bool get isChairman   => this == UserRole.chairman;
  bool get isPrivileged =>
      this == UserRole.manager ||
      this == UserRole.admin   ||
      this == UserRole.chairman;

  String get creditRole {
    switch (this) {
      case UserRole.chairman: return kRoleChairman;
      case UserRole.manager:  return kRoleManager;
      default:                return kRoleOfficeBoy;
    }
  }

  String get displayLabel {
    switch (this) {
      case UserRole.chairman: return 'Chairman';
      case UserRole.admin:    return 'Admin';
      case UserRole.manager:  return 'Manager';
      case UserRole.staff:    return 'Staff';
    }
  }

  RoleTheme get roleTheme {
    switch (this) {
      case UserRole.chairman: return RoleTheme.chairman;
      case UserRole.manager:  return RoleTheme.manager;
      default:                return RoleTheme.admin;
    }
  }
}

UserRole _parseRole(String? s) {
  switch (s?.toLowerCase()) {
    case 'chairman': return UserRole.chairman;
    case 'admin':    return UserRole.admin;
    case 'manager':  return UserRole.manager;
    default:         return UserRole.staff;
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// RECEIPT NUMBER GENERATOR
// ════════════════════════════════════════════════════════════════════════════════

Future<String> _nextReceiptNumber(String branchId) async {
  try {
    final dateKey = DateFormat('ddMMyy').format(DateTime.now());
    final seq     = await DonationsLocalStorage.nextReceiptSeq(
        branchId: branchId, dateKey: dateKey);
    return buildReceiptNumber(branchId, seq);
  } catch (e) {
    // Fallback: use timestamp-based sequence if Firestore transaction fails
    debugPrint('[ReceiptNo] Firestore seq failed, using timestamp fallback: $e');
    final now     = DateTime.now();
    final dateKey = DateFormat('ddMMyy').format(now);
    final seq     = now.millisecondsSinceEpoch % 9999;
    return buildReceiptNumber(branchId, seq);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// DONATIONS SCREEN
// ════════════════════════════════════════════════════════════════════════════════

class DonationsScreen extends StatefulWidget {
  static const String routeName = '/donations';

  static Widget embedded({
    required String branchId,
    required String username,
    String branchName = '',
    String role       = 'staff',
    String userId     = '',
  }) =>
      _EmbeddedDonations(
        branchId:   branchId,
        username:   username,
        branchName: branchName,
        role:       _parseRole(role),
        userId:     userId,
      );

  const DonationsScreen({super.key});

  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen> {
  String?  _branchId;
  String   _username    = 'User';
  String   _branchName  = '';
  String   _userId      = '';
  UserRole _role        = UserRole.staff;
  bool     _loadingUser = true;
  String?  _loadError;

  final _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingUser = false);
      return;
    }
    _userId = user.uid;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _username   = data['username']   as String? ?? user.email?.split('@').first ?? 'User';
        _role       = _parseRole(data['role'] as String?);
        _branchId   = data['branchId']   as String?;
        _branchName = data['branchName'] as String? ?? '';
        if (_branchId != null && _branchId!.isNotEmpty) {
          if (mounted) setState(() => _loadingUser = false);
          return;
        }
      }

      final branches = await FirebaseFirestore.instance.collection('branches').get();
      for (final b in branches.docs) {
        final ud = await b.reference.collection('users').doc(user.uid).get();
        if (ud.exists) {
          final data  = ud.data()!;
          _username   = data['username'] as String? ?? user.email?.split('@').first ?? 'User';
          _role       = _parseRole(data['role'] as String?);
          _branchId   = b.id;
          _branchName = b.data()['name'] as String? ?? '';
          break;
        }
      }
    } catch (e) {
      debugPrint('DonationsScreen _loadUser: $e');
      if (mounted) setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  CollectionReference get _col => FirebaseFirestore.instance
      .collection('branches')
      .doc(_branchId!)
      .collection('donations');

  @override
  Widget build(BuildContext context) {
    return RoleThemeScope(
      role: _role.roleTheme,
      child: Builder(builder: (ctx) {
        final t = RoleThemeScope.dataOf(ctx);
        return Scaffold(
          backgroundColor: t.bg,
          body: _loadingUser
              ? const _LoadingSkeleton()
              : _loadError != null
                  ? _ErrorState(message: _loadError!, onRetry: _loadUser)
                  : _branchId == null
                      ? const _NoBranchState()
                      : _DonationsBody(
                          branchId:          _branchId!,
                          username:          _username,
                          branchName:        _branchName,
                          userId:            _userId,
                          col:               _col,
                          today:             _today,
                          role:              _role,
                          nextReceiptNumber: () => _nextReceiptNumber(_branchId!),
                          showBackButton:    Navigator.canPop(ctx),
                        ),
        );
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// EMBEDDED VARIANT
// ════════════════════════════════════════════════════════════════════════════════

class _EmbeddedDonations extends StatelessWidget {
  final String   branchId, username, branchName, userId;
  final UserRole role;

  const _EmbeddedDonations({
    required this.branchId,   required this.username,
    required this.branchName, required this.role,
    required this.userId,
  });

  CollectionReference get _col => FirebaseFirestore.instance
      .collection('branches')
      .doc(branchId)
      .collection('donations');

  @override
  Widget build(BuildContext context) => RoleThemeScope(
        role: role.roleTheme,
        child: _DonationsBody(
          branchId:          branchId,
          username:          username,
          branchName:        branchName,
          userId:            userId,
          col:               _col,
          today:             DateFormat('yyyy-MM-dd').format(DateTime.now()),
          role:              role,
          nextReceiptNumber: () => _nextReceiptNumber(branchId),
          showBackButton:    false,
        ),
      );
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();
  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Center(
        child: CircularProgressIndicator(color: t.accent, strokeWidth: 2));
  }
}

class _NoBranchState extends StatelessWidget {
  const _NoBranchState();
  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.domain_disabled_rounded, size: 52, color: t.textTertiary),
          const SizedBox(height: 16),
          Text('Branch Not Found', style: DS.heading(color: t.textPrimary)),
          const SizedBox(height: 8),
          Text('Your account is not linked to any branch.',
              textAlign: TextAlign.center,
              style: DS.body(color: t.textSecondary)),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_off_rounded, size: 52, color: DS.statusRejected),
          const SizedBox(height: 16),
          Text('Could not load your account',
              style: DS.heading(color: t.textPrimary)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: DS.caption(color: t.textTertiary)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DS.rMd)),
                elevation: 0),
            onPressed: onRetry,
            icon:  const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// DONATIONS BODY
// ════════════════════════════════════════════════════════════════════════════════

class _DonationsBody extends StatefulWidget {
  final String              branchId, username, branchName, userId;
  final CollectionReference col;
  final String              today;
  final UserRole            role;
  final Future<String> Function() nextReceiptNumber;
  final bool                showBackButton;

  const _DonationsBody({
    required this.branchId,           required this.username,
    required this.branchName,         required this.userId,
    required this.col,                required this.today,
    required this.role,               required this.nextReceiptNumber,
    required this.showBackButton,
  });

  @override
  State<_DonationsBody> createState() => _DonationsBodyState();
}

class _DonationsBodyState extends State<_DonationsBody>
    with SingleTickerProviderStateMixin {
  DonationCategory _selectedCategory = DonationCategory.jamia;
  late TabController _tabController;

  bool get _showCreditTab =>
      widget.role.isManager || widget.role.isChairman;

  int get _tabCount => _showCreditTab ? 2 : 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
  }

  @override
  void didUpdateWidget(_DonationsBody old) {
    super.didUpdateWidget(old);
    if (old.role != widget.role && _tabCount != _tabController.length) {
      _tabController.dispose();
      _tabController = TabController(length: _tabCount, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role.isChairman) {
      return _ChairmanLayout(
        branchId:          widget.branchId,
        branchName:        widget.branchName,
        username:          widget.username,
        userId:            widget.userId,
        col:               widget.col,
        today:             widget.today,
        nextReceiptNumber: widget.nextReceiptNumber,
        showBackButton:    widget.showBackButton,
        selectedCategory:  _selectedCategory,
        onCatChanged:      (c) => setState(() => _selectedCategory = c),
      );
    }

    return Column(children: [
      _AppHeader(
        username:       widget.username,
        branchName:     widget.branchName,
        role:           widget.role,
        branchId:       widget.branchId,
        today:          widget.today,
        showBackButton: widget.showBackButton,
        showCreditTab:  _showCreditTab,
        tabController:  _tabController,
      ),
      Expanded(
        child: _showCreditTab
            ? TabBarView(controller: _tabController, children: [
                _DashboardTab(
                  branchId:          widget.branchId,
                  username:          widget.username,
                  branchName:        widget.branchName,
                  userId:            widget.userId,
                  col:               widget.col,
                  today:             widget.today,
                  role:              widget.role,
                  nextReceiptNumber: widget.nextReceiptNumber,
                  selectedCategory:  _selectedCategory,
                  onCatChanged:      (c) => setState(() => _selectedCategory = c),
                ),
                SingleChildScrollView(
                  child: ManagerCreditsDashboard(
                    branchId:   widget.branchId,
                    branchName: widget.branchName,
                    userId:     widget.userId,
                    username:   widget.username,
                  ),
                ),
              ])
            : _DashboardTab(
                branchId:          widget.branchId,
                username:          widget.username,
                branchName:        widget.branchName,
                userId:            widget.userId,
                col:               widget.col,
                today:             widget.today,
                role:              widget.role,
                nextReceiptNumber: widget.nextReceiptNumber,
                selectedCategory:  _selectedCategory,
                onCatChanged:      (c) => setState(() => _selectedCategory = c),
              ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CHAIRMAN LAYOUT
// ════════════════════════════════════════════════════════════════════════════════

class _ChairmanLayout extends StatefulWidget {
  final String              branchId, branchName, username, userId, today;
  final CollectionReference col;
  final Future<String> Function() nextReceiptNumber;
  final bool                showBackButton;
  final DonationCategory    selectedCategory;
  final ValueChanged<DonationCategory> onCatChanged;

  const _ChairmanLayout({
    required this.branchId,          required this.branchName,
    required this.username,          required this.userId,
    required this.col,               required this.today,
    required this.nextReceiptNumber, required this.showBackButton,
    required this.selectedCategory,  required this.onCatChanged,
  });

  @override
  State<_ChairmanLayout> createState() => _ChairmanLayoutState();
}

class _ChairmanLayoutState extends State<_ChairmanLayout>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _ChairmanHeader(
        username:       widget.username,
        branchName:     widget.branchName,
        branchId:       widget.branchId,
        showBackButton: widget.showBackButton,
        tabController:  _tabController,
      ),
      Expanded(
        child: TabBarView(controller: _tabController, children: [
          _DashboardTab(
            branchId:          widget.branchId,
            username:          widget.username,
            branchName:        widget.branchName,
            userId:            widget.userId,
            col:               widget.col,
            today:             widget.today,
            role:              UserRole.chairman,
            nextReceiptNumber: widget.nextReceiptNumber,
            selectedCategory:  widget.selectedCategory,
            onCatChanged:      widget.onCatChanged,
          ),
          SingleChildScrollView(
            child: ChairmanCreditApprovalSection(
              branchId:         widget.branchId,
              chairmanUsername: widget.username,
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// HEADERS  — no KPI strip; just title + tab bar
// ════════════════════════════════════════════════════════════════════════════════

class _ChairmanHeader extends StatelessWidget {
  final String        username, branchName, branchId;
  final bool          showBackButton;
  final TabController tabController;

  const _ChairmanHeader({
    required this.username,       required this.branchName,
    required this.branchId,       required this.showBackButton,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      color: t.bg,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              if (showBackButton) ...[
                _backBtn(context, t),
                const SizedBox(width: 12),
              ],
              Expanded(child: _titleBlock(t)),
              // Chairman approval badge
              _ChairmanPendingBadge(branchId: branchId),
            ]),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildTabBar(t),
          ),
          const SizedBox(height: 1),
        ]),
      ),
    );
  }

  Widget _buildTabBar(RoleThemeData t) => TabBar(
        controller:           tabController,
        labelColor:           t.textPrimary,
        unselectedLabelColor: t.textTertiary,
        labelStyle:           const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
        indicatorColor:       t.accentLight,
        indicatorWeight:      2.5,
        indicatorSize:        TabBarIndicatorSize.label,
        dividerColor:         t.bgRule,
        tabs: const [Tab(text: 'Donations'), Tab(text: 'Approvals')],
      );

  Widget _titleBlock(RoleThemeData t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GMWF Donation System',
              style: DS.label(color: t.textTertiary)
                  .copyWith(letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(branchName.isNotEmpty ? branchName : username,
              style: DS.heading(color: t.textPrimary)),
        ]);
}

/// Small badge showing pending chairman approvals count
class _ChairmanPendingBadge extends StatelessWidget {
  final String branchId;
  const _ChairmanPendingBadge({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final t   = RoleThemeScope.dataOf(context);
    final svc = CreditLedgerService(branchId);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: svc.managerToChairmanPending(),
      builder: (_, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:        DS.statusPending.withOpacity(0.12),
            borderRadius: BorderRadius.circular(DS.rMd),
            border:       Border.all(color: DS.statusPending.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.pending_actions_rounded, size: 13, color: DS.statusPending),
            const SizedBox(width: 5),
            Text('$count pending',
                style: DS.label(color: DS.statusPending).copyWith(fontSize: 10)),
          ]),
        );
      },
    );
  }
}

class _AppHeader extends StatelessWidget {
  final String        username, branchName, branchId, today;
  final UserRole      role;
  final bool          showBackButton, showCreditTab;
  final TabController tabController;

  const _AppHeader({
    required this.username,       required this.branchName,
    required this.branchId,       required this.today,
    required this.role,           required this.showBackButton,
    required this.showCreditTab,  required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      color: t.bg,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              if (showBackButton) ...[
                _backBtn(context, t),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('GMWF DONATION SYSTEM',
                      style: DS.label(color: t.textTertiary)
                          .copyWith(letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(branchName.isNotEmpty ? branchName : username,
                      style: DS.heading(color: t.textPrimary)),
                ]),
              ),
              // Role badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:        t.accentMuted.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(DS.rMd),
                  border:       Border.all(color: t.bgRule),
                ),
                child: Text(role.displayLabel,
                    style: DS.label(color: t.accent).copyWith(fontSize: 10)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (showCreditTab) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TabBar(
                controller:           tabController,
                labelColor:           t.textPrimary,
                unselectedLabelColor: t.textTertiary,
                labelStyle:   const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
                indicatorColor:  t.accentLight,
                indicatorWeight: 2.5,
                indicatorSize:   TabBarIndicatorSize.label,
                dividerColor:    t.bgRule,
                tabs: [
                  const Tab(text: 'Donations'),
                  Tab(text: role.isChairman ? 'Approvals' : 'Credits'),
                ],
              ),
            ),
            const SizedBox(height: 1),
          ] else
            const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

Widget _backBtn(BuildContext context, RoleThemeData t) => GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        padding:    const EdgeInsets.all(9),
        decoration: BoxDecoration(
            color:        t.accentMuted.withOpacity(0.5),
            borderRadius: BorderRadius.circular(DS.rMd)),
        child:
            Icon(Icons.arrow_back_rounded, size: 18, color: t.textPrimary),
      ));

// ════════════════════════════════════════════════════════════════════════════════
// MINI KPI ROW  — compact summary shown above the form only
// ════════════════════════════════════════════════════════════════════════════════

class _MiniKpiRow extends StatelessWidget {
  final String   branchId, today;
  final UserRole role;

  const _MiniKpiRow({
    required this.branchId,
    required this.today,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('donations')
          .where('date', isEqualTo: today)
          .snapshots(),
      builder: (_, snap) {
        final docs = (snap.data?.docs ?? [])
            .where((d) => d.id != 'credit_ledger')
            .toList();
        final count = docs.length;
        final total = docs.fold<double>(0, (s, d) {
          final data = d.data() as Map<String, dynamic>;
          return s + ((data['amount'] as num?)?.toDouble() ?? 0.0);
        });

        String fmtTotal(double v) {
          if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
          if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
          return v.toStringAsFixed(0);
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color:        t.bgCard,
              borderRadius: BorderRadius.circular(DS.rLg),
              border:       Border.all(color: t.bgRule),
              boxShadow:    DS.shadowSm),
          child: Row(
            children: [
              _miniTile(t, 'Transactions', '$count',
                  Icons.receipt_rounded, DS.emerald500),
              _divider(t),
              _miniTile(t, 'Total Collected', 'PKR ${fmtTotal(total)}',
                  Icons.payments_rounded, t.accentLight),
              _divider(t),
              _miniTile(t, 'Today',
                  DateFormat('dd MMM').format(DateTime.now()),
                  Icons.calendar_today_rounded,
                  const Color(0xFFFB923C)),
            ],
          ),
        );
      },
    );
  }

  Widget _divider(RoleThemeData t) => Container(
      width: 1, height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: t.bgRule);

  Widget _miniTile(RoleThemeData t, String label, String value,
      IconData icon, Color accent) =>
      Expanded(
        child: Column(children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(height: 5),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DS.mono(color: t.textPrimary,
                  size: value.length > 7 ? 12 : 15)),
          const SizedBox(height: 3),
          Text(label,
              textAlign: TextAlign.center,
              style: DS.label(color: t.textTertiary)
                  .copyWith(fontSize: 9, letterSpacing: 0.3)),
        ]),
      );
}

// ════════════════════════════════════════════════════════════════════════════════
// DASHBOARD TAB
// ════════════════════════════════════════════════════════════════════════════════

class _DashboardTab extends StatefulWidget {
  final String              branchId, username, branchName, userId, today;
  final CollectionReference col;
  final UserRole            role;
  final Future<String> Function() nextReceiptNumber;
  final DonationCategory    selectedCategory;
  final ValueChanged<DonationCategory> onCatChanged;

  const _DashboardTab({
    required this.branchId,           required this.username,
    required this.branchName,         required this.userId,
    required this.col,                required this.today,
    required this.role,               required this.nextReceiptNumber,
    required this.selectedCategory,   required this.onCatChanged,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  late String _fromDate;
  late String _toDate;
  QuerySnapshot? _lastSnapshot;
  DonationCategory? _filterCategory;

  late Stream<QuerySnapshot> _donationsStream;

  void _rebuildStream() {
    Query q = widget.col;
    if (_fromDate.isNotEmpty) {
      q = q.where('date', isGreaterThanOrEqualTo: _fromDate);
    }
    if (_toDate.isNotEmpty) {
      q = q.where('date', isLessThanOrEqualTo: _toDate);
    }
    _donationsStream = q.snapshots();
  }

  @override
  void initState() {
    super.initState();
    _fromDate = '';
    _toDate   = '';
    _rebuildStream();
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = DateTime.tryParse(isFrom ? _fromDate : _toDate) ?? DateTime.now();
    final picked  = await showDatePicker(
      context:     context,
      initialDate: initial,
      firstDate:   DateTime(2020),
      lastDate:    DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    final str = DateFormat('yyyy-MM-dd').format(picked);
    setState(() {
      if (isFrom) {
        _fromDate = str;
        if (_fromDate.compareTo(_toDate) > 0) _toDate = str;
      } else {
        _toDate = str;
        if (_toDate.compareTo(_fromDate) < 0) _fromDate = str;
      }
      _lastSnapshot = null;
      _rebuildStream();
    });
  }

  void _resetAll() {
    setState(() {
      _fromDate     = '';
      _toDate       = '';
      _lastSnapshot = null;
      _rebuildStream();
    });
  }

  void _onFilterChanged(DonationCategory? cat) {
    setState(() => _filterCategory = cat);
    if (cat != null) widget.onCatChanged(cat);
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return StreamBuilder<QuerySnapshot>(
      stream: _donationsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off_rounded,
                    size: 48, color: DS.statusRejected.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text('Could not load donations',
                    style: DS.subheading(color: t.textSecondary)),
                const SizedBox(height: 6),
                Text('${snap.error}',
                    textAlign: TextAlign.center,
                    style: DS.caption(color: t.textTertiary)),
              ]),
            ),
          );
        }

        if (snap.hasData) _lastSnapshot = snap.data;
        final rawDocs = (_lastSnapshot?.docs ?? [])
            .where((d) => d.id != 'credit_ledger')
            .toList();

        final roleFiltered = widget.role.isOfficeBoy
            ? rawDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final recorder = (data['recordedBy'] as String? ?? '').toLowerCase();
                return recorder == widget.username.toLowerCase();
              }).toList()
            : rawDocs;

        final dateFiltered = (_fromDate.isEmpty && _toDate.isEmpty)
            ? roleFiltered
            : roleFiltered.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final date = (data['date'] as String? ?? '');
                if (_fromDate.isNotEmpty && date.compareTo(_fromDate) < 0) return false;
                if (_toDate.isNotEmpty   && date.compareTo(_toDate)   > 0) return false;
                return true;
              }).toList();

        final catFiltered = _filterCategory == null
            ? dateFiltered
            : dateFiltered.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['categoryId'] as String?) == _filterCategory!.name;
              }).toList();

        final sorted = [...catFiltered]..sort((a, b) {
            final at = (a.data() as Map)['receiptNo'] as String? ?? '';
            final bt = (b.data() as Map)['receiptNo'] as String? ?? '';
            return bt.compareTo(at);
          });

        final typedDocs = sorted.cast<QueryDocumentSnapshot>();
        final donations = typedDocs.map((d) => d.data() as Map<String, dynamic>).toList();

        final addForm = _AddDonationForm(
          category:          widget.selectedCategory,
          onCatChanged:      widget.onCatChanged,
          col:               widget.col,
          today:             widget.today,
          username:          widget.username,
          branchId:          widget.branchId,
          branchName:        widget.branchName,
          userId:            widget.userId,
          role:              widget.role,
          nextReceiptNumber: widget.nextReceiptNumber,
        );

        return Container(
          color: t.bg,
          child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth >= 700) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: constraints.maxWidth * 0.42,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 28),
                    child: Column(children: [
                      _MiniKpiRow(
                        branchId: widget.branchId,
                        today:    widget.today,
                        role:     widget.role,
                      ),
                      const SizedBox(height: 14),
                      addForm,
                    ]),
                  ),
                ),
                Expanded(
                  child: _ListPanel(
                    donations:       donations,
                    typedDocs:       typedDocs,
                    activeCategory:  widget.selectedCategory,
                    filterCategory:  _filterCategory,
                    onFilterChanged: _onFilterChanged,
                    col:             widget.col,
                    fromDate:        _fromDate,
                    toDate:          _toDate,
                    today:           widget.today,
                    onPickFrom:      () => _pickDate(true),
                    onPickTo:        () => _pickDate(false),
                    onReset:         _resetAll,
                    listPadding:     const EdgeInsets.fromLTRB(8, 0, 20, 28),
                    topPad:          20,
                    isWide:          true,
                    branchName:      widget.branchName,
                  ),
                ),
              ]);
            }

            // Narrow layout
            return _ListPanel(
              donations:       donations,
              typedDocs:       typedDocs,
              activeCategory:  widget.selectedCategory,
              filterCategory:  _filterCategory,
              onFilterChanged: _onFilterChanged,
              col:             widget.col,
              fromDate:        _fromDate,
              toDate:          _toDate,
              today:           widget.today,
              onPickFrom:      () => _pickDate(true),
              onPickTo:        () => _pickDate(false),
              onReset:         _resetAll,
              listPadding:     const EdgeInsets.fromLTRB(16, 0, 16, 32),
              topPad:          0,
              isWide:          false,
              branchName:      widget.branchName,
              headerSliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Column(children: [
                    _MiniKpiRow(
                      branchId: widget.branchId,
                      today:    widget.today,
                      role:     widget.role,
                    ),
                    const SizedBox(height: 14),
                    addForm,
                  ]),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// LIST PANEL
// ════════════════════════════════════════════════════════════════════════════════

class _ListPanel extends StatelessWidget {
  final List<Map<String, dynamic>>      donations;
  final List<QueryDocumentSnapshot>     typedDocs;
  final DonationCategory                activeCategory;
  final DonationCategory?               filterCategory;
  final ValueChanged<DonationCategory?> onFilterChanged;
  final CollectionReference             col;
  final String                          fromDate, toDate, today, branchName;
  final VoidCallback                    onPickFrom, onPickTo, onReset;
  final EdgeInsets                      listPadding;
  final double                          topPad;
  final bool                            isWide;
  final Widget?                         headerSliver;

  const _ListPanel({
    required this.donations,       required this.typedDocs,
    required this.activeCategory,  required this.filterCategory,
    required this.onFilterChanged, required this.col,
    required this.fromDate,        required this.toDate,
    required this.today,           required this.onPickFrom,
    required this.onPickTo,        required this.onReset,
    required this.listPadding,     required this.topPad,
    required this.isWide,          required this.branchName,
    this.headerSliver,
  });

  double get _hPad => listPadding.left;

  String _prettyDate(String d) {
    try { return DateFormat('dd MMM yy').format(DateTime.parse(d)); }
    catch (_) { return d; }
  }

  @override
  Widget build(BuildContext context) {
    final t          = RoleThemeScope.dataOf(context);
    final effectiveCat = filterCategory ?? activeCategory;

    final summaryBlock = _StickyBlock(
      donations:      donations,
      effectiveCat:   effectiveCat,
      filterCategory: filterCategory,
      onFilterChange: onFilterChanged,
      hPad:           _hPad,
      rPad:           listPadding.right,
    );

    return CustomScrollView(
      slivers: [
        if (headerSliver != null) headerSliver!,

        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                _hPad, topPad, listPadding.right, 12),
            child: _DateRangeBar(
              fromDate:   fromDate,
              toDate:     toDate,
              today:      today,
              onPickFrom: onPickFrom,
              onPickTo:   onPickTo,
              onReset:    onReset,
            ),
          ),
        ),

        if (isWide)
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyBlockDelegate(
              bgColor: t.bg,
              child:   summaryBlock,
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(_hPad, 0, listPadding.right, 0),
              child: summaryBlock,
            ),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(_hPad, 14, listPadding.right, 10),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Transactions',
                    style: DS.heading(color: t.textPrimary)),
                Text(
                  fromDate.isEmpty && toDate.isEmpty
                      ? 'All time'
                      : fromDate == toDate
                          ? fromDate == today
                              ? 'Today'
                              : _prettyDate(fromDate)
                          : '${_prettyDate(fromDate)} – ${_prettyDate(toDate)}',
                  style: DS.caption(color: t.textTertiary),
                ),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color:        effectiveCat.color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(DS.rSm),
                    border:       Border.all(
                        color: effectiveCat.color.withOpacity(0.25))),
                child: Text('${donations.length} records',
                    style: DS.label(color: effectiveCat.color)
                        .copyWith(letterSpacing: 0.3)),
              ),
            ]),
          ),
        ),

        if (donations.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _hPad),
              child: _EmptyTransactions(category: effectiveCat),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                _hPad, 0, listPadding.right, listPadding.bottom),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final itemCatId = donations[i]['categoryId'] as String?;
                  final itemCat   = DonationCategory.values
                          .firstWhereOrNull((c) => c.name == itemCatId) ??
                      activeCategory;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DonationTile(
                      data:       donations[i],
                      doc:        typedDocs[i],
                      col:        col,
                      category:   itemCat,
                      branchName: branchName,
                    ),
                  );
                },
                childCount: donations.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// STICKY BLOCK
// ════════════════════════════════════════════════════════════════════════════════

class _StickyBlock extends StatelessWidget {
  final List<Map<String, dynamic>>      donations;
  final DonationCategory                effectiveCat;
  final DonationCategory?               filterCategory;
  final ValueChanged<DonationCategory?> onFilterChange;
  final double                          hPad, rPad;

  const _StickyBlock({
    required this.donations,      required this.effectiveCat,
    required this.filterCategory, required this.onFilterChange,
    required this.hPad,           required this.rPad,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      color: t.bg,
      padding: EdgeInsets.fromLTRB(hPad, 10, rPad, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CategoryFilterChips(
            filterCategory: filterCategory,
            onChanged:      onFilterChange,
          ),
          const SizedBox(height: 10),
          _SummaryStatsCard(
            donations: donations,
            category:  effectiveCat,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// SLIVER PERSISTENT HEADER DELEGATE
// ════════════════════════════════════════════════════════════════════════════════

class _StickyBlockDelegate extends SliverPersistentHeaderDelegate {
  final Color  bgColor;
  final Widget child;

  const _StickyBlockDelegate({
    required this.bgColor,
    required this.child,
  });

  @override double get minExtent => 120;
  @override double get maxExtent => 260;

  @override
  Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) {
    return OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      alignment: Alignment.topCenter,
      child: Container(
        color: bgColor,
        child: IntrinsicHeight(child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyBlockDelegate old) =>
      old.child   != child   ||
      old.bgColor != bgColor;
}

// ════════════════════════════════════════════════════════════════════════════════
// CATEGORY FILTER CHIPS
// ════════════════════════════════════════════════════════════════════════════════

class _CategoryFilterChips extends StatelessWidget {
  final DonationCategory?               filterCategory;
  final ValueChanged<DonationCategory?> onChanged;

  const _CategoryFilterChips({
    required this.filterCategory,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _FilterChip(
          label:      'All',
          icon:       Icons.grid_view_rounded,
          color:      t.accent,
          isSelected: filterCategory == null,
          onTap:      () => onChanged(null),
        ),
        const SizedBox(width: 8),
        ...DonationCategory.values.map((cat) {
          final isSel = filterCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _FilterChip(
              label:      cat.label,
              icon:       cat.icon,
              color:      cat.color,
              isSelected: isSel,
              onTap:      () => onChanged(isSel ? null : cat),
            ),
          );
        }),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final Color        color;
  final bool         isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,      required this.icon,
    required this.color,      required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve:    Curves.easeOut,
        padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:        isSelected ? color : t.bgCard,
          borderRadius: BorderRadius.circular(DS.rXl),
          border: Border.all(
            color: isSelected ? color : t.bgRule,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected ? DS.shadowSm : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: isSelected ? Colors.white : color),
          const SizedBox(width: 6),
          Text(
            label,
            style: DS.label(color: isSelected ? Colors.white : color)
                .copyWith(
                  fontSize:   12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// ADD DONATION FORM  — fixed save crash (no local storage fallback needed,
// saves directly to Firestore via widget.col.add())
// ════════════════════════════════════════════════════════════════════════════════

class _AddDonationForm extends StatefulWidget {
  final DonationCategory               category;
  final ValueChanged<DonationCategory> onCatChanged;
  final CollectionReference            col;
  final String today, username, branchId, branchName, userId;
  final UserRole                       role;
  final Future<String> Function()      nextReceiptNumber;

  const _AddDonationForm({
    required this.category,           required this.onCatChanged,
    required this.col,                required this.today,
    required this.username,           required this.branchId,
    required this.branchName,         required this.userId,
    required this.role,               required this.nextReceiptNumber,
  });

  @override
  State<_AddDonationForm> createState() => _AddDonationFormState();
}

class _AddDonationFormState extends State<_AddDonationForm> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _amtCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _itemCtrl  = TextEditingController();
  final _qtyCtrl   = TextEditingController();
  final _probCtrl  = TextEditingController();

  late DonationSubtype _selectedSubtype;
  String        _unit          = 'kg';
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool          _saving        = false;

  @override
  void initState() {
    super.initState();
    _selectedSubtype = _defaultSubtype(widget.category);
  }

  @override
  void didUpdateWidget(_AddDonationForm old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) {
      _selectedSubtype = _defaultSubtype(widget.category);
      _amtCtrl.clear();
      _itemCtrl.clear();
      _qtyCtrl.clear();
      _probCtrl.clear();
      // keep _paymentMethod — user likely wants same method
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _amtCtrl.dispose();
    _notesCtrl.dispose(); _itemCtrl.dispose(); _qtyCtrl.dispose();
    _probCtrl.dispose();
    super.dispose();
  }

  DonationSubtype _defaultSubtype(DonationCategory c) {
    final subs = c.subtypes;
    return subs.isNotEmpty ? subs.first : DonationSubtype.general;
  }

  bool get _isOfficeBoy => widget.role.isOfficeBoy;

  void _clearForm() {
    _nameCtrl.clear();
    _phoneCtrl.clear();
    _amtCtrl.clear();
    _notesCtrl.clear();
    _itemCtrl.clear();
    _qtyCtrl.clear();
    _probCtrl.clear();
  }

  Future<void> _submit() async {
    // Guard: ensure form key is attached
    if (_formKey.currentState == null) return;

    // Validate form first
    if (!_formKey.currentState!.validate()) return;

    final isGoods = widget.category.isGoods;

    if (isGoods && _itemCtrl.text.trim().isEmpty) {
      _snack('Item name is required', DS.statusRejected);
      return;
    }

    if (!mounted) return;
    setState(() => _saving = true);

    try {
      final receiptNo = await widget.nextReceiptNumber();
      if (!mounted) return;

      final amountText = isGoods ? _qtyCtrl.text.trim() : _amtCtrl.text.trim();
      final amount     = double.tryParse(amountText) ?? 0.0;

      final data = <String, dynamic>{
        'categoryId':    widget.category.name,
        'categoryLabel': widget.category.label,
        'subtypeId':     isGoods ? null : _selectedSubtype.name,
        'subtypeLabel':  isGoods ? null : _selectedSubtype.label,
        'goodsItem':     isGoods ? _itemCtrl.text.trim() : null,
        'donorName':     _nameCtrl.text.trim(),
        'phone':         _phoneCtrl.text.trim(),
        'amount':        amount,
        'unit':          isGoods ? _unit : 'PKR',
        'notes':         _notesCtrl.text.trim(),
        'date':          widget.today,
        'timestamp':     DateTime.now().toIso8601String(),
        'receiptNo':     receiptNo,
        'recordedBy':    widget.username,
        'collectorRole': widget.role.displayLabel,
        'branchId':      widget.branchId,
        'branchName':    widget.branchName,
        'status':        isGoods ? kStatusApproved : kStatusPending,
        'creditApplied': false,
        'paymentMethod': _paymentMethod.label,
      };

      if (isGoods && _probCtrl.text.trim().isNotEmpty) {
        data['probableAmount'] =
            double.tryParse(_probCtrl.text.trim()) ?? 0.0;
      }

      // Strip null values — Firestore rejects null map entries on some SDK versions
      data.removeWhere((key, value) => value == null);

      // Save to Firestore
      await widget.col.add(data);

      // Auto-credit for office boy cash donations
      if (!isGoods && _isOfficeBoy && widget.userId.isNotEmpty) {
        try {
          await CreditLedgerService(widget.branchId).officeBoyAutoCredit(
            fromUserId:   widget.userId,
            fromUsername: widget.username,
            amount:       amount,
            categoryId:   widget.category.name,
            subtypeId:    _selectedSubtype.name,
            branchName:   widget.branchName,
            receiptNo:    receiptNo,
            notes:        _notesCtrl.text.trim(),
          );
        } catch (e) {
          debugPrint('[AutoCredit] $e');
        }
      }

      if (mounted) {
        setState(() => _saving = false);
        _clearForm();
        _snack(
          'Receipt $receiptNo saved'
          '${_isOfficeBoy && !isGoods ? "  ·  Credit forwarded to Manager" : ""}',
          DS.statusApproved,
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('[SaveDonation] FirebaseException: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() => _saving = false);
        _snack('Save failed: ${e.message ?? e.code}', DS.statusRejected);
      }
    } catch (e, st) {
      debugPrint('[SaveDonation] Error: $e\n$st');
      if (mounted) {
        setState(() => _saving = false);
        _snack('Save failed: ${e.toString()}', DS.statusRejected);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior:        SnackBarBehavior.floating,
      margin:          const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rMd)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t   = RoleThemeScope.dataOf(context);
    final cat = widget.category;

    return Container(
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rXl),
          border:       Border.all(color: t.bgRule),
          boxShadow:    DS.shadowMd),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Gradient top accent bar
        Container(
          height: 4,
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: cat.gradient)),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Header row
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color:        cat.color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(DS.rMd),
                      border:       Border.all(
                          color: cat.color.withOpacity(0.2))),
                  child: Icon(cat.icon, color: cat.color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Record Donation',
                        style: DS.heading(color: t.textPrimary)),
                    if (_isOfficeBoy)
                      Row(children: [
                        Icon(Icons.bolt_rounded,
                            size: 11, color: DS.emerald600),
                        const SizedBox(width: 3),
                        Text('Auto-credit to Manager',
                            style: DS.caption(color: DS.emerald600)
                                .copyWith(fontWeight: FontWeight.w600)),
                      ]),
                  ]),
                ),
              ]),

              const SizedBox(height: 20),

              // Category
              Text('CATEGORY', style: DS.label(color: t.textTertiary)),
              const SizedBox(height: 8),
              _CategorySelector(
                  selected: cat, onChanged: widget.onCatChanged),
              const SizedBox(height: 20),

              // Donor name
              DSField(
                controller:        _nameCtrl,
                label:             'Donor Name',
                hint:              'Full name',
                icon:              Icons.person_outline_rounded,
                accentColor:       cat.color,
                keyboardType:      TextInputType.name,
                textCapitalization: TextCapitalization.words,
                textInputAction:   TextInputAction.next,
                validator:         (v) =>
                    v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 14),

              // Phone
              DSField(
                controller:        _phoneCtrl,
                label:             'Phone Number (optional)',
                hint:              '03XX-XXXXXXX',
                icon:              Icons.phone_outlined,
                accentColor:       cat.color,
                keyboardType:      TextInputType.phone,
                textCapitalization: TextCapitalization.none,
                textInputAction:   TextInputAction.next,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (v.trim().length != 11) return 'Must be 11 digits';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              if (cat.isGoods) ...[
                DSField(
                  controller:        _itemCtrl,
                  label:             'Item Name',
                  hint:              'e.g. Rice, Cooking Oil, Wheat',
                  icon:              Icons.inventory_2_outlined,
                  accentColor:       cat.color,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction:   TextInputAction.next,
                ),
                const SizedBox(height: 14),
                Text('QUANTITY', style: DS.label(color: t.textTertiary)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DSField(
                      controller:        _qtyCtrl,
                      label:             '',
                      hint:              'Amount',
                      icon:              Icons.scale_outlined,
                      accentColor:       cat.color,
                      keyboardType:      const TextInputType.numberWithOptions(
                          decimal: true),
                      textCapitalization: TextCapitalization.none,
                      textInputAction:   TextInputAction.next,
                      validator: (v) =>
                          v?.trim().isEmpty ?? true ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _UnitPicker(
                      value:     _unit,
                      onChanged: (v) =>
                          setState(() => _unit = v ?? _unit),
                      color:     cat.color),
                ]),
                const SizedBox(height: 14),
                DSField(
                  controller:        _probCtrl,
                  label:             'Estimated Value PKR (optional)',
                  hint:              'e.g. 5000',
                  icon:              Icons.payments_outlined,
                  accentColor:       cat.color,
                  keyboardType:      TextInputType.number,
                  textCapitalization: TextCapitalization.none,
                  textInputAction:   TextInputAction.next,
                  formatters:        [FilteringTextInputFormatter.digitsOnly],
                ),
              ]
              else ...[
                Text('TYPE', style: DS.label(color: t.textTertiary)),
                const SizedBox(height: 8),
                DSSubtypeSelector(
                  subtypes:  cat.subtypes,
                  selected:  _selectedSubtype,
                  onChanged: (st) =>
                      setState(() => _selectedSubtype = st),
                ),
                const SizedBox(height: 14),
                DSField(
                  controller:        _amtCtrl,
                  label:             'Amount (PKR)',
                  hint:              'Enter amount in Rupees',
                  icon:              Icons.payments_rounded,
                  accentColor:       cat.color,
                  keyboardType:      TextInputType.number,
                  textCapitalization: TextCapitalization.none,
                  textInputAction:   TextInputAction.next,
                  formatters:        [FilteringTextInputFormatter.digitsOnly],
                  validator:         (v) =>
                      v?.trim().isEmpty ?? true ? 'Required' : null,
                ),
              ],

              const SizedBox(height: 14),
              Text('PAYMENT METHOD', style: DS.label(color: t.textTertiary)),
              const SizedBox(height: 8),
              DSPaymentMethodSelector(
                selected:    _paymentMethod,
                onChanged:   (pm) => setState(() => _paymentMethod = pm),
                accentColor: cat.color,
              ),
              const SizedBox(height: 14),
              DSField(
                controller:        _notesCtrl,
                label:             'Notes (optional)',
                hint:              'Any remarks or additional info',
                icon:              Icons.notes_rounded,
                accentColor:       cat.color,
                textCapitalization: TextCapitalization.sentences,
                textInputAction:   TextInputAction.done,
              ),

              const SizedBox(height: 22),
              SizedBox(
                width:  double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cat.color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DS.rMd)),
                      elevation: 0),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_circle_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Save Donation',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// DATE RANGE BAR
// ════════════════════════════════════════════════════════════════════════════════

class _DateRangeBar extends StatelessWidget {
  final String     fromDate, toDate, today;
  final VoidCallback onPickFrom, onPickTo, onReset;

  const _DateRangeBar({
    required this.fromDate, required this.toDate,
    required this.today,    required this.onPickFrom,
    required this.onPickTo, required this.onReset,
  });

  String _pretty(String d) {
    if (d.isEmpty) return 'All';
    try { return DateFormat('dd MMM').format(DateTime.parse(d)); }
    catch (_) { return d; }
  }

  bool get _isAll => fromDate.isEmpty && toDate.isEmpty;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rMd),
          border:       Border.all(color: t.bgRule),
          boxShadow:    DS.shadowSm),
      child: Row(children: [
        Icon(Icons.date_range_rounded, size: 15, color: t.accent),
        const SizedBox(width: 8),
        _datePill(context, t, 'From', fromDate, onPickFrom),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward_rounded, size: 12, color: t.textTertiary),
        ),
        _datePill(context, t, 'To', toDate, onPickTo),
        const Spacer(),
        if (!_isAll)
          GestureDetector(
            onTap: onReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color:        t.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(DS.rSm),
                  border:       Border.all(color: t.accent.withOpacity(0.25))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.clear_rounded, size: 11, color: t.accent),
                const SizedBox(width: 4),
                Text('Show All',
                    style: DS.label(color: t.accent).copyWith(fontSize: 10)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _datePill(BuildContext context, RoleThemeData t,
      String label, String date, VoidCallback onTap) {
    final isEmpty = date.isEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color:        t.bgCardAlt,
            borderRadius: BorderRadius.circular(DS.rSm),
            border:       Border.all(color: t.bgRule)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ',
              style: DS.label(color: t.textTertiary).copyWith(fontSize: 9)),
          Text(isEmpty ? 'All' : _pretty(date),
              style: DS.label(
                      color: isEmpty ? t.textTertiary : t.textPrimary)
                  .copyWith(
                      fontSize:  11,
                      fontStyle: isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 12, color: t.accent),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// SUMMARY STATS CARD
// ════════════════════════════════════════════════════════════════════════════════

class _SummaryStatsCard extends StatelessWidget {
  final List<Map<String, dynamic>> donations;
  final DonationCategory           category;

  const _SummaryStatsCard({required this.donations, required this.category});

  @override
  Widget build(BuildContext context) {
    final t   = RoleThemeScope.dataOf(context);
    final cat = category;

    double total = 0, approved = 0, pending = 0, goods = 0;
    int    cashCount = 0, goodsCount = 0;

    for (final d in donations) {
      final amt    = (d['amount'] as num?)?.toDouble() ?? 0;
      final unit   = d['unit']   as String? ?? 'PKR';
      final status = d['status'] as String? ?? kStatusPending;
      if (unit == 'PKR' || unit.isEmpty) {
        total += amt;
        cashCount++;
        if (status == kStatusApproved) approved += amt;
        else if (status == kStatusPending) pending += amt;
      } else {
        goods += amt;
        goodsCount++;
      }
    }

    final pct = total > 0 ? (approved / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin:  const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: cat.color.withOpacity(0.2)),
          boxShadow:    DS.shadowSm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding:    const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color:        cat.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(DS.rSm)),
            child: Icon(Icons.analytics_rounded, color: cat.color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Summary', style: DS.subheading(color: t.textPrimary)),
            Text(
              '${donations.length} donation${donations.length != 1 ? "s" : ""}'
              ' in selected range',
              style: DS.caption(color: t.textTertiary),
            ),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('PKR ${fmtNum(total)}',
                style: DS.mono(color: cat.color, size: 17)),
            Text('Total Collected',
                style: DS.caption(color: t.textTertiary)),
          ]),
        ]),

        if (cashCount > 0) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Approval Status',
                style: DS.label(color: t.textTertiary)),
            Text('${(pct * 100).round()}%',
                style: DS.label(color: DS.statusApproved)
                    .copyWith(fontSize: 11)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           pct,
              minHeight:       7,
              backgroundColor: DS.statusPending.withOpacity(0.15),
              valueColor:      AlwaysStoppedAnimation(DS.statusApproved),
            ),
          ),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: _StatChip(
              label: 'Approved',
              value: 'PKR ${fmtNum(approved)}',
              color: DS.statusApproved,
            )),
            const SizedBox(width: 8),
            Expanded(child: _StatChip(
              label: 'Pending',
              value: 'PKR ${fmtNum(pending)}',
              color: DS.statusPending,
            )),
            if (goodsCount > 0) ...[
              const SizedBox(width: 8),
              Expanded(child: _StatChip(
                label: 'Goods ($goodsCount)',
                value: '${goods.toStringAsFixed(0)} items',
                color: DS.plum500,
              )),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color:        color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(DS.rSm),
          border:       Border.all(color: color.withOpacity(0.20))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: DS.label(color: color).copyWith(fontSize: 9)),
        const SizedBox(height: 3),
        Text(value,
            style: DS.mono(color: color, size: 12),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// EMPTY TRANSACTIONS STATE
// ════════════════════════════════════════════════════════════════════════════════

class _EmptyTransactions extends StatelessWidget {
  final DonationCategory category;
  const _EmptyTransactions({required this.category});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: t.bgRule)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding:    const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: category.color.withOpacity(0.08),
              shape: BoxShape.circle),
          child: Icon(Icons.receipt_long_rounded,
              size:  28,
              color: category.color.withOpacity(0.45)),
        ),
        const SizedBox(height: 14),
        Text('No Transactions',
            style: DS.subheading(color: t.textTertiary)),
        const SizedBox(height: 4),
        Text('No records found for the selected date range',
            style: DS.caption(color: t.textTertiary)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// DONATION TILE
// ════════════════════════════════════════════════════════════════════════════════

class _DonationTile extends StatefulWidget {
  final Map<String, dynamic>  data;
  final QueryDocumentSnapshot doc;
  final CollectionReference   col;
  final DonationCategory      category;
  final String                branchName;

  const _DonationTile({
    required this.data,       required this.doc,
    required this.col,        required this.category,
    required this.branchName,
  });

  @override
  State<_DonationTile> createState() => _DonationTileState();
}

class _DonationTileState extends State<_DonationTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t             = RoleThemeScope.dataOf(context);
    final cat           = widget.category;
    final d             = widget.data;
    final amt           = (d['amount']         as num?)?.toDouble() ?? 0;
    final prob          = (d['probableAmount'] as num?)?.toDouble();
    final isGoods       = cat.isGoods;
    final receiptNo     = d['receiptNo']     as String? ?? '';
    final donor         = d['donorName']     as String? ?? '-';
    final phone         = d['phone']         as String? ?? '';
    final subId         = d['subtypeId']     as String?;
    final goodsItem     = d['goodsItem']     as String? ?? '';
    final notes         = d['notes']         as String? ?? '';
    final status        = d['status']        as String? ?? kStatusPending;
    final unit          = d['unit']          as String? ?? '';
    final recorder      = d['recordedBy']    as String? ?? '';
    final collectorRole = d['collectorRole'] as String? ?? '';
    final hasPhone      = phone.isNotEmpty;

    final subtype = subId != null
        ? DonationSubtype.values.firstWhereOrNull((s) => s.name == subId)
        : null;

    final amtDisplay = isGoods
        ? (prob != null
            ? 'PKR ${fmtNum(prob)}'
            : '${amt % 1 == 0 ? amt.toInt() : amt} $unit')
        : 'PKR ${fmtNum(amt)}';

    final collectorLabel = collectorRole.isNotEmpty && recorder.isNotEmpty
        ? 'Collected by $collectorRole: $recorder'
        : recorder.isNotEmpty
            ? 'Recorded by $recorder'
            : null;

    return Container(
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: t.bgRule),
          boxShadow:    DS.shadowSm),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 3,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: cat.gradient))),

        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 4,
              color: cat.color.withOpacity(0.55),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 14, 0),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Receipt badge
                  Container(
                    constraints: const BoxConstraints(minWidth: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    decoration: BoxDecoration(
                        color:        cat.color.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(DS.rMd),
                        border:       Border.all(
                            color: cat.color.withOpacity(0.2))),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text('RECEIPT',
                          style: DS.label(color: cat.color)
                              .copyWith(fontSize: 7)),
                      const SizedBox(height: 2),
                      Text(receiptNo.isNotEmpty
                              ? receiptNo.split('-').last
                              : '-',
                          style: DS.mono(color: cat.color, size: 13)
                              .copyWith(height: 1.2)),
                    ]),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(donor,
                          style: DS.subheading(color: t.textPrimary)),
                      const SizedBox(height: 3),
                      if (receiptNo.isNotEmpty)
                        Text(receiptNo,
                            style: DS.caption(color: t.textTertiary)
                                .copyWith(fontWeight: FontWeight.w700,
                                    fontSize: 10)),
                      if (collectorLabel != null) ...[
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.badge_outlined,
                              size: 10, color: t.textTertiary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(collectorLabel,
                                style: DS.caption(color: t.textTertiary)
                                    .copyWith(fontSize: 10),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        _CategoryBadge(category: cat),
                        if (phone.isNotEmpty)
                          _MetaPill(
                              icon:  Icons.phone_outlined,
                              label: phone,
                              color: t.textTertiary),
                        if ((d['paymentMethod'] as String? ?? 'Cash') != 'Cash')
                          _MetaPill(
                              icon:  Icons.credit_card_rounded,
                              label: d['paymentMethod'] as String,
                              color: t.accent),
                        if (subtype != null)
                          DSSubtypeBadge(subtype: subtype),
                        if (goodsItem.isNotEmpty)
                          _MetaPill(
                              icon:  Icons.inventory_2_outlined,
                              label: goodsItem,
                              color: cat.color),
                      ]),
                    ]),
                  ),

                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(amtDisplay,
                        style: DS.mono(color: cat.color, size: 16)),
                    if (!isGoods) ...[
                      const SizedBox(height: 5),
                      DSStatusBadge(status: status),
                    ],
                  ]),
                ]),
              ),
            ),
          ]),
        ),

        if (notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 14, 0),
            child: Container(
              width:   double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                  color:        t.bgCardAlt,
                  borderRadius: BorderRadius.circular(DS.rSm),
                  border:       Border.all(color: t.bgRule)),
              child: Text(notes,
                  style: DS.caption(color: t.textSecondary)
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 14, 12),
          child: Row(children: [
            DSActionButton(
              icon:  Icons.print_rounded,
              label: 'Print',
              color: cat.color,
              onTap: () => printReceiptPdf(d, receiptNo),
            ),
            const SizedBox(width: 7),
            DSActionButton(
              assetImage: 'assets/icons/WA.png',
              label:      'WhatsApp',
              color:      const Color(0xFF25D366),
              disabled:   !hasPhone,
              onTap: () => shareReceiptWhatsApp(
                  d, receiptNo, phone, widget.branchName),
            ),
            const SizedBox(width: 7),
            DSActionButton(
              icon:     Icons.sms_rounded,
              label:    'SMS',
              color:    cat.color,
              disabled: !hasPhone,
              onTap: () => sendSmsThankYou(
                phone, donor, cat, amt,
                unit.isEmpty ? 'PKR' : unit,
                receiptNo, widget.branchName,
                subtype:       subtype,
                paymentMethod: d['paymentMethod'] as String? ?? 'Cash',
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color:        t.bgCardAlt,
                    borderRadius: BorderRadius.circular(DS.rSm)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_expanded ? 'Less' : 'Details',
                      style: DS.label(color: t.textTertiary)
                          .copyWith(letterSpacing: 0.3, fontSize: 11)),
                  const SizedBox(width: 3),
                  Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 14, color: t.textTertiary),
                ]),
              ),
            ),
            const SizedBox(width: 7),
            GestureDetector(
              onTap: () => _confirmDelete(context),
              child: Container(
                padding:    const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color:        DS.statusRejected.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(DS.rSm),
                    border:       Border.all(
                        color: DS.statusRejected.withOpacity(0.25))),
                child: Icon(Icons.delete_outline_rounded,
                    size: 16, color: DS.statusRejected),
              ),
            ),
          ]),
        ),

        if (_expanded)
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
            decoration: BoxDecoration(
                color:  t.bgCardAlt,
                border: Border(top: BorderSide(color: t.bgRule))),
            child: Wrap(spacing: 24, runSpacing: 10, children: [
              _DetailCell(label: 'Receipt No', value: receiptNo.isNotEmpty ? receiptNo : '-'),
              _DetailCell(label: 'Category', value: cat.label),
              if (subtype != null)
                _DetailCell(label: 'Type', value: subtype.label),
              _DetailCell(
                  label: 'Recorded By',
                  value: recorder.isNotEmpty ? recorder : '-'),
              if (collectorRole.isNotEmpty)
                _DetailCell(
                    label: 'Collector Role', value: collectorRole),
              _DetailCell(
                  label: 'Date', value: d['date'] as String? ?? '-'),
              if (d['paymentMethod'] != null)
                _DetailCell(
                    label: 'Payment',
                    value: d['paymentMethod'] as String),
              if (!isGoods)
                _DetailCell(
                    label: 'Status',
                    value: status[0].toUpperCase() + status.substring(1)),
              if (isGoods && prob != null)
                _DetailCell(
                    label: 'Est. Value',
                    value: 'PKR ${fmtNum(prob)}'),
              if (!hasPhone)
                _DetailCell(
                    label: 'Phone',
                    value: 'Not provided',
                    muted: true),
            ]),
          ),
      ]),
    );
  }

  void _confirmDelete(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rXl)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color:        t.bgCard,
              borderRadius: BorderRadius.circular(DS.rXl),
              border:       Border.all(color: t.bgRule)),
          child: Column(
              mainAxisSize:       MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remove Transaction',
                    style: DS.heading(color: t.textPrimary)),
                const SizedBox(height: 10),
                Text(
                    'This will permanently delete this donation record.',
                    style: DS.body(color: t.textSecondary)),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: t.textSecondary,
                          side: BorderSide(color: t.bgRule),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(DS.rMd)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12)),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: DS.statusRejected,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(DS.rMd)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          elevation: 0),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await widget.col.doc(widget.doc.id).delete();
                        } catch (e) {
                          debugPrint('[Delete] $e');
                        }
                      },
                      child: const Text('Delete',
                          style:
                              TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// SMALL SHARED WIDGETS
// ════════════════════════════════════════════════════════════════════════════════

class _CategoryBadge extends StatelessWidget {
  final DonationCategory category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:        category.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: category.color.withOpacity(0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(category.icon, size: 9, color: category.color),
        const SizedBox(width: 4),
        Text(
          category.label,
          style: TextStyle(
            fontSize:      9,
            fontWeight:    FontWeight.w700,
            color:         category.color,
            letterSpacing: 0.3,
          ),
        ),
      ]),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   color;

  const _MetaPill({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final c = color ?? t.textTertiary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: c),
      const SizedBox(width: 4),
      Text(label, style: DS.caption(color: c)),
    ]);
  }
}

class _DetailCell extends StatelessWidget {
  final String label, value;
  final bool   muted;
  const _DetailCell(
      {required this.label, required this.value, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: DS.label(color: t.textTertiary)),
      const SizedBox(height: 3),
      Text(value,
          style: DS.subheading(
              color: muted ? t.textTertiary : t.textPrimary)),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CATEGORY SELECTOR
// ════════════════════════════════════════════════════════════════════════════════

class _CategorySelector extends StatelessWidget {
  final DonationCategory               selected;
  final ValueChanged<DonationCategory> onChanged;

  const _CategorySelector(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: DonationCategory.values.map((cat) {
          final isSel  = cat == selected;
          final isLast = cat == DonationCategory.goods;
          final t      = RoleThemeScope.dataOf(context);
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(cat),
              child: AnimatedContainer(
                duration:   const Duration(milliseconds: 160),
                curve:      Curves.easeOut,
                margin:     EdgeInsets.only(right: isLast ? 0 : 8),
                padding:    const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color:        isSel ? cat.color : t.bgCardAlt,
                    borderRadius: BorderRadius.circular(DS.rMd),
                    border:       Border.all(
                        color: isSel ? cat.color : t.bgRule,
                        width: isSel ? 0 : 1)),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(cat.icon,
                      size:  20,
                      color: isSel ? Colors.white : t.textTertiary),
                  const SizedBox(height: 5),
                  Text(cat.shortLabel,
                      style: DS.label(
                              color: isSel
                                  ? Colors.white
                                  : t.textTertiary)
                          .copyWith(letterSpacing: 0.3, fontSize: 11)),
                ]),
              ),
            ),
          );
        }).toList(),
      );
}

// ════════════════════════════════════════════════════════════════════════════════
// UNIT PICKER
// ════════════════════════════════════════════════════════════════════════════════

class _UnitPicker extends StatelessWidget {
  final String                value;
  final ValueChanged<String?> onChanged;
  final Color                 color;

  const _UnitPicker(
      {required this.value, required this.onChanged, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
          color:        t.bgCardAlt,
          borderRadius: BorderRadius.circular(DS.rMd),
          border:       Border.all(color: t.bgRule)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value:         value,
          isExpanded:    false,
          style: DS.body(color: t.textPrimary)
              .copyWith(fontWeight: FontWeight.w500),
          dropdownColor: t.bgCard,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: color),
          items: kUnits
              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}