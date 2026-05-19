// lib/pages/donations/donations_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../services/local_storage_service.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import 'donations_shared.dart';
import 'donations_dashboard.dart';
import 'donors_registry.dart';
import 'widgets/add_donation_wizard.dart';
import '../../models/donation_models.dart';
import '../../constants/colors.dart';


const String kStatusPending = 'pending';

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

// UserRole moved to donations_shared.dart

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

class _DonationsScreenState extends State<DonationsScreen> with TickerProviderStateMixin {
  late TabController _mobileTabController;
  DonationCategory _selectedCategory = DonationCategory.all;
  late String _viewingBranchId;
  late String _viewingBranchName;

  // Auto-fetched branch list for HQ Manager / Chairman
  List<({String id, String name})> _fetchedBranches = [];
  bool _fetchingBranches = false;

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 2, vsync: this);

    final isGlobal = widget.branchId.isEmpty ||
        widget.branchId == 'global';

    // Handle global / consolidated view for high-level roles
    if (widget.branchId == 'all' || (isGlobal && widget.role.canSeeAllBranches)) {
      _viewingBranchId = 'all';
      _viewingBranchName = 'All Branches (Consolidated)';
    } else if (isGlobal && widget.allBranchIds.isNotEmpty) {
      _viewingBranchId   = widget.allBranchIds.first;
      _viewingBranchName = widget.allBranchNames.isNotEmpty
          ? widget.allBranchNames.first
          : _viewingBranchId;
    } else if (!isGlobal) {
      _viewingBranchId   = widget.branchId;
      _viewingBranchName = widget.branchName;
    } else {
      // Global role with no pre-passed branches — we will fetch them below
      _viewingBranchId   = '';
      _viewingBranchName = 'Loading...';
    }

    // For global roles (HQ Manager, Chairman) fetch all branches from Firestore
    if (widget.role.canSeeAllBranches) {
      _loadAllBranches();
    }
  }

  Future<void> _loadAllBranches() async {
    if (_fetchingBranches) return;
    setState(() => _fetchingBranches = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('branches').get();
      final branches = snap.docs.map((d) {
        final name = (d.data()['name'] as String? ?? d.id);
        return (id: d.id, name: name);
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _fetchedBranches = branches;
        // If we had no valid branch selected yet, pick the first one
        if (_viewingBranchId.isEmpty || _viewingBranchId == 'global') {
          if (widget.role.canSeeAllBranches) {
            _viewingBranchId = 'all';
            _viewingBranchName = 'All Branches (Consolidated)';
          } else if (branches.isNotEmpty) {
            _viewingBranchId   = branches.first.id;
            _viewingBranchName = branches.first.name;
          }
        } else if (_viewingBranchId == 'all') {
          _viewingBranchName = 'All Branches (Consolidated)';
        }
      });
    } catch (e) {
      debugPrint('DonationsScreen: Failed to load branches: $e');
    } finally {
      if (mounted) setState(() => _fetchingBranches = false);
    }
  }

  @override
  void dispose() {
    _mobileTabController.dispose();
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



  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

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

    if (isMobile) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: t.bg,
          appBar: AppBar(
            backgroundColor: DonDS.headerTop,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Image.asset('assets/logo/gmwf-1.png', fit: BoxFit.contain),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_viewingBranchName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      Text(widget.username, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),

            bottom: TabBar(
              controller: _mobileTabController,
              labelColor: DonDS.tealLight,
              unselectedLabelColor: Colors.white60,
              indicatorColor: DonDS.tealLight,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              tabs: const [
                Tab(text: "Donations"),
                Tab(text: "Donors"),
              ],
            ),
          ),
          body: TabBarView(
            controller: _mobileTabController,
            children: [
              _donationsTab(),
              DonorRegistryWidget(
                branchId: _viewingBranchId,
                branchName: _viewingBranchName,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: DonDS.teal,
            onPressed: _onAddTap,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(children: [
        // ── Primary Header ────────────────────────────────────────────────
        _Header(
          branchName:      _viewingBranchName,
          username:        widget.username,
          role:            widget.role,
        ),

        // ── Main Content Area ───────────────────────────────────────────
        Expanded(
          child: _donationsTab(),
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
    onAddTap:          _onAddTap,
  );

  Future<void> _onAddTap() async {
    final result = await showDialog<DonationRecord>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AddDonationWizard(
        branchId: widget.branchId,
        branchName: widget.branchName,
        currentUsername: widget.username,
        userId: widget.userId,
        currentUserRole: widget.role,
      ),
    );

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Donation recorded: ${cleanReceiptNumber(result.receiptNo)}'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Donation Saved!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.gray900),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.gray50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.gray100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RECEIPT DETAILS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.gray400, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Receipt No: ${cleanReceiptNumber(result.receiptNo)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gray900, fontFamily: 'DMMono'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Donor: ${result.donorName}',
                        style: const TextStyle(fontSize: 13, color: AppColors.gray700, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.isGoods
                            ? 'Goods: ${result.goodsItem ?? 'Donation'}'
                            : 'Amount: PKR ${NumberFormat('#,##0').format(result.amount)}',
                        style: const TextStyle(fontSize: 13, color: AppColors.gray900, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Would you like to print the receipt or share it with the donor?',
                  style: TextStyle(fontSize: 13, color: AppColors.gray600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CLOSE', style: TextStyle(color: AppColors.gray500, fontWeight: FontWeight.w700)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  showReceiptShareSheet(context, result.toMap());
                },
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('PRINT & SHARE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                ),
              ),
            ],
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PREMIUM HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String   branchName, username;
  final UserRole role;

  const _Header({
    required this.branchName,
    required this.username,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final rc = role.roleColor;

    final bool showRolePill = username.toLowerCase().trim() != role.displayLabel.toLowerCase().trim();

    return Container(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 16),
      decoration: BoxDecoration(
        color: t.bgCard,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: Image.asset('assets/logo/gmwf-1.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.textTertiary, letterSpacing: 0.2),
                ),
                const SizedBox(height: 2),
                Text(
                  username,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.textPrimary, letterSpacing: -0.3),
                ),
              ],
            ),
          ),
          if (showRolePill) ...[
            const SizedBox(width: 12),
            _RolePill(role: role),
          ],
        ],
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
    width: 44, height: 44,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [roleColor, roleColor.withValues(alpha: 0.7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: roleColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3)),
      ],
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Center(
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
      ),
    ),
  );
}

class _RolePill extends StatelessWidget {
  final UserRole role;
  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: role.roleColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: role.roleColor.withValues(alpha: 0.15)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5, height: 5,
          decoration: BoxDecoration(color: role.roleColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          role.displayLabel.toUpperCase(),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: role.roleColor, letterSpacing: 0.8),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BRANCH PICKER SHEET
// ─────────────────────────────────────────────────────────────────────────────
