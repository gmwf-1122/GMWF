// lib/pages/donations/donations_screen.dart
//
// FIX: Manager can now see all branches just like Chairman
// Design: warm slate header (dark teal gradient) + teal accent
// No tab duplication — Credits is a bottom sheet, not a second tab
// Tab controller is fully isolated via DefaultTabController

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
  
  // FIX: Manager can now see all branches
  bool get canSeeAllBranches => this == UserRole.manager || this == UserRole.chairman;

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
    if (n == 'chairman')                                       return UserRole.chairman;
    if (n == 'manager')                                        return UserRole.manager;
    if (n == 'officeboy' || n == 'ob')                         return UserRole.officeBoy;
    if (n == 'staff')                                          return UserRole.staff;
    if (n.contains('chairman'))                                return UserRole.chairman;
    if (n.contains('manager'))                                 return UserRole.manager;
    if (n.contains('officeboy') || n.contains('office'))       return UserRole.officeBoy;
    debugPrint('[UserRole] Unknown: "$raw" → staff');
    return UserRole.staff;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DONATIONS SCREEN
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

class _DonationsScreenState extends State<DonationsScreen> {
  DonationCategory _selectedCategory = DonationCategory.jamia;
  late String _viewingBranchId;
  late String _viewingBranchName;

  @override
  void initState() {
    super.initState();
    _viewingBranchId   = widget.branchId;
    _viewingBranchName = widget.branchName;
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

  void _openCredits(BuildContext ctx) {
    showModalBottomSheet(
      context:            ctx,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      useSafeArea:        true,
      builder: (_) => _CreditsSheet(
        branchId:   _viewingBranchId,
        username:   widget.username,
        branchName: _viewingBranchName,
        userId:     widget.userId,
        role:       widget.role,
      ),
    );
  }

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
        _Header(
          branchName:      _viewingBranchName,
          username:        widget.username,
          role:            widget.role,
          canSwitchBranch: _canSwitchBranch,
          branchOptions:   _branchOptions,
          currentBranchId: _viewingBranchId,
          onBranchSwitch:  _switchBranch,
          onCreditsTap:    () => _openCredits(context),
        ),
        Expanded(
          child: DashboardTab(
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
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String   branchName, username, currentBranchId;
  final UserRole role;
  final bool     canSwitchBranch;
  final List<({String id, String name})> branchOptions;
  final void Function(String, String) onBranchSwitch;
  final VoidCallback onCreditsTap;

  const _Header({
    required this.branchName,     required this.username,
    required this.currentBranchId, required this.role,
    required this.canSwitchBranch, required this.branchOptions,
    required this.onBranchSwitch,  required this.onCreditsTap,
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
        height: 62,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [

            // Avatar + name + badge
            _Avatar(username: username, role: role, roleColor: rc),
            const SizedBox(width: 10),
            _UserInfo(username: username, role: role, roleColor: rc),

            // Centre branch picker
            Expanded(
              child: GestureDetector(
                onTap: canSwitchBranch ? () => _showBranchSheet(context) : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('GMWF DONATIONS',
                        style: TextStyle(
                            fontSize: 7, fontWeight: FontWeight.w700,
                            color: DonDS.tealLight.withOpacity(0.65),
                            letterSpacing: 2)),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                              branchName.isNotEmpty ? branchName : 'All Branches',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w700,
                                  color: DonDS.onDark)),
                        ),
                        if (canSwitchBranch) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.expand_more_rounded,
                              size: 16, color: DonDS.onDarkSub),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Credits pill button
            GestureDetector(
              onTap: onCreditsTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color:        DonDS.amber.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(
                      color: DonDS.amber.withOpacity(0.38)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.account_balance_wallet_rounded,
                      size: 14, color: DonDS.amber),
                  SizedBox(width: 5),
                  Text('Credits',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700,
                          color: DonDS.amber)),
                ]),
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
  final UserRole role;
  final Color roleColor;
  const _Avatar({required this.username, required this.role,
      required this.roleColor});

  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        roleColor.withOpacity(0.35), roleColor.withOpacity(0.12)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      shape:  BoxShape.circle,
      border: Border.all(color: roleColor.withOpacity(0.65), width: 1.5),
    ),
    child: Center(
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
            color: roleColor),
      ),
    ),
  );
}

class _UserInfo extends StatelessWidget {
  final String   username;
  final UserRole role;
  final Color    roleColor;
  const _UserInfo({required this.username, required this.role,
      required this.roleColor});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (username.isNotEmpty)
        Text(username,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: DonDS.onDark)),
      const SizedBox(height: 3),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color:        roleColor.withOpacity(0.20),
          borderRadius: BorderRadius.circular(99),
          border:       Border.all(color: roleColor.withOpacity(0.45)),
        ),
        child: Text(role.displayLabel.toUpperCase(),
            style: TextStyle(
                fontSize: 7.5, fontWeight: FontWeight.w800,
                color: roleColor, letterSpacing: 1)),
      ),
    ],
  );
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                  color: isSel ? DonDS.tealMuted : null,
                  border: Border(bottom: BorderSide(
                      color: t.bgRule, width: 0.5))),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: isSel
                        ? DonDS.teal.withOpacity(0.15) : t.bgCardAlt,
                    shape:  BoxShape.circle,
                    border: Border.all(
                        color: isSel
                            ? DonDS.teal.withOpacity(0.4) : t.bgRule),
                  ),
                  child: Center(
                    child: Text(
                      opt.name.isNotEmpty
                          ? opt.name[0].toUpperCase() : 'B',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: isSel ? DonDS.teal : t.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(opt.name,
                      style: DS.subheading(color: t.textPrimary)),
                  Text(opt.id,
                      style: DS.caption(color: t.textTertiary)
                          .copyWith(fontSize: 10)),
                ])),
                if (isSel)
                  const Icon(Icons.check_circle_rounded,
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

// ─────────────────────────────────────────────────────────────────────────────
// CREDITS SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _CreditsSheet extends StatelessWidget {
  final String   branchId, username, branchName, userId;
  final UserRole role;

  const _CreditsSheet({
    required this.branchId,   required this.username,
    required this.branchName, required this.userId,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final t      = RoleThemeScope.dataOf(context);
    final height = MediaQuery.of(context).size.height * 0.88;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color:        t.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: t.bgRule, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: DonDS.amberMuted,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  size: 20, color: DonDS.amber),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Credits', style: DS.heading(color: t.textPrimary)),
              Text(branchName.isNotEmpty ? branchName : 'All Branches',
                  style: DS.caption(color: t.textTertiary)),
            ])),
            IconButton(
              icon: Icon(Icons.close_rounded,
                  color: t.textTertiary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        Divider(height: 1, color: t.bgRule),
        Expanded(child: _creditsBody(t)),
      ]),
    );
  }

  Widget _creditsBody(RoleThemeData t) {
    if (role.isChairman) {
      return ChairmanCreditApprovalSection(
          branchId: branchId, branchName: branchName, username: username);
    }
    if (role.isManager) {
      return ManagerCreditsDashboard(
          branchId: branchId, username: username,
          branchName: branchName, userId: userId);
    }
    if (role.isOfficeBoy) {
      return OfficeBoyCreditsView(branchId: branchId, userId: userId);
    }
    return _ReadOnlyCreditsView(branchId: branchId, username: username);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// READ-ONLY CREDITS (staff)
// ─────────────────────────────────────────────────────────────────────────────

class _ReadOnlyCreditsView extends StatelessWidget {
  final String branchId, username;
  const _ReadOnlyCreditsView(
      {required this.branchId, required this.username});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DonationsLocalStorage.streamCreditEntries(branchId: branchId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error loading credits',
              style: DS.body(color: t.textSecondary)));
        }
        final all  = snap.data ?? [];
        final mine = all.where((d) =>
            (d['fromUsername'] as String? ?? '').toLowerCase() ==
            username.toLowerCase()).toList();

        if (mine.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                  color: DonDS.amberMuted, shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  size: 36, color: DonDS.amber),
            ),
            const SizedBox(height: 16),
            Text('No credits yet',
                style: DS.subheading(color: t.textTertiary)),
            const SizedBox(height: 4),
            Text('Credits will appear here once recorded',
                style: DS.caption(color: t.textTertiary)),
          ]));
        }

        return ListView.separated(
          padding:          const EdgeInsets.all(16),
          itemCount:        mine.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder:      (context, i) {
            final d       = mine[i];
            final amt     = (d['amount'] as num?)?.toDouble() ?? 0.0;
            final stat    = d['status']     as String? ?? kStatusPending;
            final catId   = d['categoryId'] as String? ?? '';
            final catE    = DonationCategory.values
                    .firstWhereOrNull((c) => c.name == catId) ??
                DonationCategory.jamia;
            final dateRaw = d['date'] as String? ?? '';
            String dl = dateRaw;
            try {
              dl = DateFormat('dd MMM yyyy').format(DateTime.parse(dateRaw));
            } catch (_) {}
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: t.bgCard, borderRadius: BorderRadius.circular(DS.rMd),
                  border: Border.all(color: t.bgRule), boxShadow: DS.shadowSm),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: catE.lightColor, shape: BoxShape.circle),
                  child: Icon(catE.icon, color: catE.color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(catE.label,
                      style: DS.subheading(color: t.textPrimary)
                          .copyWith(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(dl, style: DS.caption(color: t.textTertiary)
                      .copyWith(fontSize: 10)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('PKR ${fmtNum(amt)}',
                      style: DS.mono(color: catE.color, size: 13)),
                  const SizedBox(height: 4),
                  DSStatusBadge(status: stat),
                ]),
              ]),
            );
          },
        );
      },
    );
  }
}