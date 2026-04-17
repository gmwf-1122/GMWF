// lib/pages/donations/donations_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../services/donations_local_storage.dart';
import '../../services/local_storage_service.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import 'donations_shared.dart';
import 'donations_dashboard.dart';
import 'credit_ledger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

class DonDS {
  static const headerTop    = Color(0xFF0D1F1F);
  static const headerBot    = Color(0xFF163030);
  static const headerBorder = Color(0xFF1F3D3D);
  static const teal         = Color(0xFF0D9488);
  static const tealLight    = Color(0xFF2DD4BF);
  static const tealMuted    = Color(0x1A0D9488);
  // Keep amber only for currency/financial amounts — NOT for status
  static const amber        = Color(0xFFF59E0B);
  static const amberMuted   = Color(0x1AF59E0B);
  static const onDark       = Color(0xFFFFFFFF);
  static const onDarkSub    = Color(0xFF94B4B4);
  static const onDarkMuted  = Color(0xFF4D7070);
}

// ─────────────────────────────────────────────────────────────────────────────
// USER ROLE
// ─────────────────────────────────────────────────────────────────────────────

enum UserRole { chairman, manager, officeBoy, staff }

extension UserRoleX on UserRole {
  String get displayLabel {
    switch (this) {
      case UserRole.chairman:  return 'Chairman';
      case UserRole.manager:   return 'Manager';
      case UserRole.officeBoy: return 'Office Boy';
      case UserRole.staff:     return 'Staff';
    }
  }
  bool get isOfficeBoy       => this == UserRole.officeBoy;
  bool get isManager         => this == UserRole.manager;
  bool get isChairman        => this == UserRole.chairman;
  bool get canApprove        => this == UserRole.manager || this == UserRole.chairman;
  bool get canSeeAllBranches => this == UserRole.manager || this == UserRole.chairman;
  bool get hasCreditsTab     => this != UserRole.staff;

  Color get roleColor {
    switch (this) {
      case UserRole.chairman:  return const Color(0xFFF59E0B);
      case UserRole.manager:   return const Color(0xFF10B981);
      case UserRole.officeBoy: return const Color(0xFF60A5FA);
      case UserRole.staff:     return const Color(0xFF94A3B8);
    }
  }

  static UserRole fromString(String raw) {
    final n = raw.toLowerCase().replaceAll(RegExp(r'[\s_\-\.]+'), '');
    if (n == 'chairman')                                             return UserRole.chairman;
    if (n == 'manager' || n == 'branchmanager' || n == 'hqmanager') return UserRole.manager;
    if (n == 'officeboy' || n == 'ob')                              return UserRole.officeBoy;
    if (n == 'staff')                                               return UserRole.staff;
    if (n.contains('chairman'))                                     return UserRole.chairman;
    if (n.contains('manager'))                                      return UserRole.manager;
    if (n.contains('officeboy') || n.contains('office'))            return UserRole.officeBoy;
    debugPrint('[UserRole] Unknown: "$raw" → staff');
    return UserRole.staff;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DONATIONS SCREEN  — persistent tab bar, Credits is a tab (not a pill)
// ─────────────────────────────────────────────────────────────────────────────

class DonationsScreen extends StatefulWidget {
  final String   branchId, username, branchName, userId;
  final UserRole role;
  final List<String> allBranchIds;
  final List<String> allBranchNames;

  const DonationsScreen({
    super.key,
    required this.branchId,
    required this.username,
    required this.branchName,
    required this.userId,
    required this.role,
    this.allBranchIds   = const [],
    this.allBranchNames = const [],
  });

  const DonationsScreen.embedded({
    super.key,
    this.branchId       = '',
    this.username       = '',
    this.branchName     = '',
    this.userId         = '',
    this.role           = UserRole.staff,
    this.allBranchIds   = const [],
    this.allBranchNames = const [],
  });

  factory DonationsScreen.withStringRole({
    Key?   key,
    required String branchId,
    required String username,
    String branchName    = '',
    String userId        = '',
    String role          = 'staff',
    List<String> allBranchIds   = const [],
    List<String> allBranchNames = const [],
  }) => DonationsScreen(
    key: key,
    branchId: branchId, username: username,
    branchName: branchName, userId: userId,
    role: UserRoleX.fromString(role),
    allBranchIds: allBranchIds, allBranchNames: allBranchNames,
  );

  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen>
    with SingleTickerProviderStateMixin {
  DonationCategory _selectedCategory = DonationCategory.jamia;
  late String _viewingBranchId;
  late String _viewingBranchName;
  late TabController _tabController;

  bool get _hasCreditsTab => widget.role.hasCreditsTab;
  int  get _tabCount      => _hasCreditsTab ? 2 : 1;

  @override
  void initState() {
    super.initState();
    _viewingBranchId   = widget.branchId;
    _viewingBranchName = widget.branchName;
    _tabController     = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  CollectionReference get _col => FirebaseFirestore.instance
      .collection('branches')
      .doc(_viewingBranchId)
      .collection('donations');

  Future<String> _nextReceiptNumber() async {
    try { return await LocalStorageService.nextReceiptNumber(_viewingBranchId); }
    catch (_) { return 'TEMP-${DateTime.now().millisecondsSinceEpoch}'; }
  }

  List<({String id, String name})> get _branchOptions {
    final own = (id: widget.branchId, name: widget.branchName);
    final extras = <({String id, String name})>[];
    for (int i = 0; i < widget.allBranchIds.length; i++) {
      final bid   = widget.allBranchIds[i];
      final bname = i < widget.allBranchNames.length
          ? widget.allBranchNames[i] : bid;
      if (bid != widget.branchId) extras.add((id: bid, name: bname));
    }
    return [own, ...extras];
  }

  bool get _canSwitchBranch =>
      widget.role.canSeeAllBranches && _branchOptions.length > 1;

  void _switchBranch(String id, String name) =>
      setState(() { _viewingBranchId = id; _viewingBranchName = name; });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    if (widget.branchId.isEmpty) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.domain_disabled_rounded, size: 48, color: t.textTertiary),
          const SizedBox(height: 12),
          Text('No branch selected',
              style: DS.subheading(color: t.textSecondary)),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(children: [

        // ── Lean header ──────────────────────────────────────────────────
        _Header(
          branchName:      _viewingBranchName,
          username:        widget.username,
          role:            widget.role,
          canSwitchBranch: _canSwitchBranch,
          branchOptions:   _branchOptions,
          currentBranchId: _viewingBranchId,
          onBranchSwitch:  _switchBranch,
        ),

        // ── Persistent tab bar ───────────────────────────────────────────
        if (_hasCreditsTab)
          _TabBar(
            controller:    _tabController,
            branchId:      _viewingBranchId,
            role:          widget.role,
            userId:        widget.userId,
          ),

        // ── Tab content ──────────────────────────────────────────────────
        Expanded(
          child: _hasCreditsTab
              ? TabBarView(
                  controller: _tabController,
                  physics:    const NeverScrollableScrollPhysics(),
                  children: [
                    _donationsTab(),
                    _creditsTab(),
                  ],
                )
              : _donationsTab(),
        ),
      ]),
    );
  }

  Widget _donationsTab() => DashboardTab(
    branchId:          _viewingBranchId,
    username:          widget.username,
    branchName:        _viewingBranchName,
    userId:            widget.userId,
    col:               _col,
    today:             _today,
    role:              widget.role,
    nextReceiptNumber: _nextReceiptNumber,
    selectedCategory:  _selectedCategory,
    onCatChanged:      (c) => setState(() => _selectedCategory = c),
  );

  Widget _creditsTab() {
    if (widget.role.isChairman) {
      return ChairmanCreditApprovalSection(
          branchId: _viewingBranchId,
          branchName: _viewingBranchName,
          username: widget.username);
    }
    if (widget.role.isManager) {
      return ManagerCreditsDashboard(
          branchId: _viewingBranchId,
          username: widget.username,
          branchName: _viewingBranchName,
          userId: widget.userId);
    }
    if (widget.role.isOfficeBoy) {
      return OfficeBoyCreditsView(
          branchId: _viewingBranchId,
          userId: widget.userId);
    }
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER  — compact, 52px, identity left-aligned and minimal
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String   branchName, username, currentBranchId;
  final UserRole role;
  final bool     canSwitchBranch;
  final List<({String id, String name})> branchOptions;
  final void Function(String, String) onBranchSwitch;

  const _Header({
    required this.branchName,
    required this.username,
    required this.currentBranchId,
    required this.role,
    required this.canSwitchBranch,
    required this.branchOptions,
    required this.onBranchSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final rc  = role.roleColor;
    final top = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [DonDS.headerTop, DonDS.headerBot],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: DonDS.headerBorder)),
      ),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [

            // ── Minimal identity: avatar + username only ─────────────────
            _Avatar(username: username, roleColor: rc),
            const SizedBox(width: 8),
            Text(
              username.isNotEmpty ? username : '—',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: DonDS.onDark),
            ),
            const SizedBox(width: 6),
            _RolePill(role: role),

            const Spacer(),

            // ── Branch picker centred on remaining space ─────────────────
            GestureDetector(
              onTap: canSwitchBranch ? () => _showBranchSheet(context) : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.domain_rounded,
                    size: 13, color: DonDS.tealLight.withOpacity(0.75)),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    branchName.isNotEmpty ? branchName : 'All Branches',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: DonDS.onDark),
                  ),
                ),
                if (canSwitchBranch) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.expand_more_rounded,
                      size: 15, color: DonDS.onDarkSub),
                ],
              ]),
            ),

            const Spacer(),

            // ── App label (right-aligned) ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:        DonDS.teal.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border:       Border.all(color: DonDS.teal.withOpacity(0.30)),
              ),
              child: const Text(
                'GMWF',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: DonDS.tealLight,
                    letterSpacing: 1.2),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showBranchSheet(BuildContext context) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _BranchPickerSheet(
        options:         branchOptions,
        currentBranchId: currentBranchId,
        onSelect:        (id, name) {
          Navigator.pop(context);
          onBranchSwitch(id, name);
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String username;
  final Color  roleColor;
  const _Avatar({required this.username, required this.roleColor});

  @override
  Widget build(BuildContext context) => Container(
    width: 30, height: 30,
    decoration: BoxDecoration(
      color:  roleColor.withOpacity(0.22),
      shape:  BoxShape.circle,
      border: Border.all(color: roleColor.withOpacity(0.55), width: 1.5),
    ),
    child: Center(
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: roleColor),
      ),
    ),
  );
}

class _RolePill extends StatelessWidget {
  final UserRole role;
  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color:        role.roleColor.withOpacity(0.15),
      borderRadius: BorderRadius.circular(99),
      border:       Border.all(color: role.roleColor.withOpacity(0.35)),
    ),
    child: Text(
      role.displayLabel.toUpperCase(),
      style: TextStyle(
          fontSize: 7.5, fontWeight: FontWeight.w800,
          color: role.roleColor, letterSpacing: 0.8),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PERSISTENT TAB BAR  — Credits tab shows live pending badge count
// ─────────────────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  final TabController controller;
  final String        branchId, userId;
  final UserRole      role;

  const _TabBar({
    required this.controller,
    required this.branchId,
    required this.userId,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      color:  t.bg,
      height: 44,
      child: TabBar(
        controller:           controller,
        labelColor:           DonDS.teal,
        unselectedLabelColor: t.textTertiary,
        indicatorColor:       DonDS.teal,
        indicatorWeight:      2,
        indicatorSize:        TabBarIndicatorSize.tab,
        labelStyle:    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        dividerColor: t.bgRule,
        tabs: [
          const Tab(text: 'Donations'),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Credits'),
              const SizedBox(width: 6),
              _PendingBadge(branchId: branchId, role: role, userId: userId),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Live badge showing pending credit count — red pill, always visible.
class _PendingBadge extends StatelessWidget {
  final String   branchId, userId;
  final UserRole role;
  const _PendingBadge({
    required this.branchId, required this.userId, required this.role,
  });

  String get _toRole =>
      role.isChairman ? 'Chairman' : role.isManager ? 'Manager' : '';

  @override
  Widget build(BuildContext context) {
    if (_toRole.isEmpty && !role.isOfficeBoy) return const SizedBox.shrink();
    final stream = role.isOfficeBoy
        ? LocalStorageService.streamCredits(branchId: branchId, fromUserId: userId)
        : LocalStorageService.streamCredits(branchId: branchId, toRole: _toRole);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (ctx, snap) {
        final count = (snap.data ?? [])
            .where((d) => (d['status'] as String? ?? '') == kStatusPending)
            .length;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(minWidth: 18),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color:        DS.statusRejected,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BRANCH PICKER SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _BranchPickerSheet extends StatelessWidget {
  final List<({String id, String name})>      options;
  final String                                currentBranchId;
  final void Function(String id, String name) onSelect;

  const _BranchPickerSheet({
    required this.options,
    required this.currentBranchId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      decoration: BoxDecoration(
        color:        t.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: t.bgRule, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: DonDS.tealMuted,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.domain_rounded,
                  size: 18, color: DonDS.teal),
            ),
            const SizedBox(width: 12),
            Text('Switch Branch', style: DS.heading(color: t.textPrimary)),
          ]),
        ),
        const SizedBox(height: 12),
        ...options.map((opt) {
          final isSel = opt.id == currentBranchId;
          return InkWell(
            onTap: () => onSelect(opt.id, opt.name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                  color: isSel ? DonDS.tealMuted : null,
                  border: Border(bottom: BorderSide(color: t.bgRule, width: 0.5))),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: isSel ? DonDS.teal.withOpacity(0.15) : t.bgCardAlt,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isSel ? DonDS.teal.withOpacity(0.4) : t.bgRule),
                  ),
                  child: Center(
                    child: Text(
                      opt.name.isNotEmpty ? opt.name[0].toUpperCase() : 'B',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: isSel ? DonDS.teal : t.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(opt.name, style: DS.subheading(color: t.textPrimary)),
                  Text(opt.id, style: DS.caption(color: t.textTertiary)
                      .copyWith(fontSize: 10)),
                ])),
                if (isSel) const Icon(Icons.check_circle_rounded,
                    color: DonDS.teal, size: 20),
              ]),
            ),
          );
        }),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ]),
    );
  }
}