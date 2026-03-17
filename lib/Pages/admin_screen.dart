// lib/pages/admin_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import 'branches.dart';
import 'register.dart';
import 'download_screen.dart';
import 'users.dart';
import 'fix_patients.dart';
import 'donations/donations_screen.dart';

const _cDonation = Color(0xFF6A1B9A);

class AdminScreen extends StatefulWidget {
  final String branchId;
  final String username;
  const AdminScreen({super.key, required this.branchId, this.username = 'Admin'});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  int _pageIndex = -2;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(duration: const Duration(milliseconds: 380), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  void _go(int idx)   { setState(() => _pageIndex = idx);  _fadeCtrl.forward(from: 0); }
  void _goDashboard() { setState(() => _pageIndex = -2); _fadeCtrl.forward(from: 0); }
  void _goDonations() { setState(() => _pageIndex = -1); _fadeCtrl.forward(from: 0); }

  static const _mobileNavItems = [
    {'icon': Icons.home_outlined,              'activeIcon': Icons.home_rounded,              'label': 'Home',      'idx': -2},
    {'icon': Icons.volunteer_activism_outlined,'activeIcon': Icons.volunteer_activism_rounded,'label': 'Donations', 'idx': -1},
    {'icon': Icons.favorite_border_rounded,    'activeIcon': Icons.favorite_rounded,          'label': 'Patients',  'idx': 2},
    {'icon': Icons.people_outline_rounded,     'activeIcon': Icons.people_rounded,            'label': 'Users',     'idx': 3},
    {'icon': Icons.more_horiz_rounded,         'activeIcon': Icons.more_horiz_rounded,        'label': 'More',      'idx': 99},
  ];

  @override
  Widget build(BuildContext context) {
    final t      = RoleThemeScope.dataOf(context);
    final isWide = MediaQuery.of(context).size.width >= 820;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: isWide ? null : _mobileAppBar(t),
      drawer: isWide ? null : Drawer(backgroundColor: t.bgCard, child: _sidebarContent(t)),
      body: Row(children: [
        if (isWide) _desktopSidebar(t),
        Expanded(
          child: ClipRect(
            child: FadeTransition(opacity: _fadeAnim, child: _buildBody(t, isWide)),
          ),
        ),
      ]),
      bottomNavigationBar: isWide ? null : _mobileBottomNav(t),
    );
  }

  Widget _buildBody(RoleThemeData t, bool isWide) {
    if (_pageIndex == -2) {
      return _AdminDashboard(t: t, branchId: widget.branchId, username: widget.username);
    }
    if (_pageIndex == -1) {
      return Material(
        color: t.bg,
        child: DonationsScreen.embedded(
          branchId: widget.branchId,
          username: widget.username,
        ),
      );
    }
    Widget page;
    switch (_pageIndex) {
      case 0:  page = const Branches(); break;
      case 1:  page = const Register(); break;
      case 2:  page = const UsersScreen(isPatientMode: true); break;
      case 3:  page = const UsersScreen(); break;
      case 4:  page = const DownloadScreen(); break;
      case 5:  page = FixPatientsScreen(branchId: widget.branchId); break;
      default: page = const SizedBox.shrink();
    }
    return RoleThemeScope(
      role: RoleTheme.admin,
      child: _pageIndex == 1 ? page : Container(color: t.bg, child: page),
    );
  }

  PreferredSizeWidget _mobileAppBar(RoleThemeData t) {
    final pageTitle = _getPageTitle();
    return AppBar(
      backgroundColor: t.bgCard,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: Builder(builder: (ctx) => IconButton(
          icon: Icon(Icons.menu_rounded, color: t.accent, size: 22),
          onPressed: () => Scaffold.of(ctx).openDrawer())),
      title: Row(children: [
        Image.asset("assets/logo/gmwf.png", height: 26, width: 26),
        const SizedBox(width: 10),
        Text(pageTitle, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 17),
            overflow: TextOverflow.ellipsis),
      ]),
      actions: [
        if (_pageIndex != -2)
          IconButton(icon: Icon(Icons.home_outlined, color: t.accent, size: 22), onPressed: _goDashboard),
        IconButton(icon: Icon(Icons.logout_outlined, color: t.danger, size: 20), onPressed: _logout),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.bgRule)),
    );
  }

  String _getPageTitle() {
    switch (_pageIndex) {
      case -1: return 'Donations';
      case 0:  return 'Branches';
      case 1:  return 'Register User';
      case 2:  return 'Patients';
      case 3:  return 'Users';
      case 4:  return 'Download';
      case 5:  return 'Fix Patients';
      default: return 'Admin Panel';
    }
  }

  Widget _mobileBottomNav(RoleThemeData t) {
    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        border: Border(top: BorderSide(color: t.bgRule)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _mobileNavItems.map((item) {
              final idx    = item['idx'] as int;
              final active = _pageIndex == idx;
              return GestureDetector(
                onTap: () {
                  if (idx == 99)       { _showMoreSheet(t); }
                  else if (idx == -2)  { _goDashboard(); }
                  else if (idx == -1)  { _goDonations(); }
                  else                 { _go(idx); }
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? t.accent.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(active ? item['activeIcon'] as IconData : item['icon'] as IconData,
                        color: active ? t.accent : t.textTertiary, size: 22),
                    const SizedBox(height: 3),
                    Text(item['label'] as String,
                        style: TextStyle(fontSize: 10, color: active ? t.accent : t.textTertiary,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showMoreSheet(RoleThemeData t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: t.bgRule, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('More Options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.textPrimary)),
          const SizedBox(height: 16),
          _sheetTile(ctx, t, Icons.account_balance_outlined, 'Branches', 0),
          _sheetTile(ctx, t, Icons.person_add_outlined, 'Register User', 1),
          _sheetTile(ctx, t, Icons.download_outlined, 'Download', 4),
          _sheetTile(ctx, t, Icons.build_outlined, 'Fix Patients', 5, danger: true),
          const SizedBox(height: 8),
          Divider(color: t.bgRule),
          _sheetTile(ctx, t, Icons.logout_outlined, 'Sign Out', -999, danger: true),
        ]),
      ),
    );
  }

  Widget _sheetTile(BuildContext ctx, RoleThemeData t, IconData icon, String label, int idx, {bool danger = false}) {
    final color = danger ? t.danger : t.accent;
    return ListTile(
      leading: Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20)),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: danger ? t.danger : t.textPrimary)),
      onTap: () {
        Navigator.pop(ctx);
        if (idx == -999) { _logout(); }
        else { _go(idx); }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _desktopSidebar(RoleThemeData t) {
    return Container(
      width: 256,
      decoration: BoxDecoration(color: t.bgCard, border: Border(right: BorderSide(color: t.bgRule))),
      child: _sidebarContent(t),
    );
  }

  Widget _sidebarContent(RoleThemeData t) {
    return Column(children: [
      const SizedBox(height: 48),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: t.accentMuted, borderRadius: BorderRadius.circular(12)),
              child: Image.asset("assets/logo/gmwf.png", height: 28, width: 28)),
          const SizedBox(height: 14),
          Text('GMWF', style: TextStyle(color: t.accent, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          Text('Admin Panel', style: TextStyle(color: t.textTertiary, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 24),
      Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 12),
      _navTile(t, Icons.home_outlined,              'Overview',      _pageIndex == -2, _goDashboard),
      _navTile(t, Icons.volunteer_activism_rounded, 'Donations',     _pageIndex == -1, _goDonations, accentColor: _cDonation),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.only(left: 26, bottom: 8, top: 4),
        child: Text('MANAGE', style: TextStyle(color: t.textTertiary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2))),
      Expanded(child: ListView(padding: EdgeInsets.zero, children: [
        _navTile(t, Icons.account_balance_outlined, 'Branches',     _pageIndex == 0, () => _go(0)),
        _navTile(t, Icons.person_add_outlined,      'Register User', _pageIndex == 1, () => _go(1)),
        _navTile(t, Icons.favorite_border_rounded,  'Patients',     _pageIndex == 2, () => _go(2)),
        _navTile(t, Icons.people_outline_rounded,   'Users',        _pageIndex == 3, () => _go(3)),
        _navTile(t, Icons.download_outlined,        'Download',     _pageIndex == 4, () => _go(4)),
        _navTile(t, Icons.build_outlined,           'Fix Patients', _pageIndex == 5, () => _go(5), accentColor: t.danger),
      ])),
      Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 4),
      _navTile(t, Icons.logout_outlined, 'Sign Out', false, _logout, danger: true),
      const SizedBox(height: 24),
    ]);
  }

  Widget _navTile(RoleThemeData t, IconData icon, String label, bool active,
      VoidCallback onTap, {bool danger = false, Color? accentColor}) {
    final Color c = danger ? t.danger : active ? (accentColor ?? t.accent) : t.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: active ? (accentColor ?? t.accent).withOpacity(0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10), onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 19, color: active ? c : t.textTertiary),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(
                  color: active ? c : t.textSecondary, fontSize: 14.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
              if (active) Container(width: 6, height: 6,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Admin Dashboard ───────────────────────────────────────────────────────────
class _AdminDashboard extends StatelessWidget {
  final RoleThemeData t;
  final String branchId, username;
  const _AdminDashboard({required this.t, required this.branchId, required this.username});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      color: t.bg,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: SafeArea(child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hero(context, isMobile),
            const SizedBox(height: 24),
            _kpiSection(),
            const SizedBox(height: 24),
            DashHeading("Today's Summary", t: t),
            const SizedBox(height: 14),
            _grandSummary(),
            const SizedBox(height: 24),
          ]),
        )),
      ),
    );
  }

  Widget _hero(BuildContext context, bool isMobile) => Container(
    padding: EdgeInsets.all(isMobile ? 20 : 28),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [t.accent, t.accentLight],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(isMobile ? 18 : 22),
      boxShadow: [BoxShadow(color: t.accent.withOpacity(0.28), blurRadius: 32, offset: const Offset(0, 10))],
    ),
    child: isMobile
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 10),
                  const SizedBox(width: 5),
                  Text(DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              ),
              const Spacer(),
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.25))),
                  child: Image.asset("assets/logo/gmwf.png", height: 28, width: 28)),
            ]),
            const SizedBox(height: 14),
            Text("Welcome back,", style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13)),
            const SizedBox(height: 3),
            Text(username, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text("Full access · All branches", style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12)),
          ])
        : Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 12),
                  const SizedBox(width: 6),
                  Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(height: 16),
              Text("Welcome back,", style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14)),
              const SizedBox(height: 4),
              Text(username, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text("Full access · All branches · All data", style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13)),
            ])),
            const SizedBox(width: 20),
            Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.25))),
                child: Image.asset("assets/logo/gmwf.png", height: 52, width: 52)),
          ]),
  );

  Widget _kpiSection() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 140);
      final docs = snap.data!.docs;
      final ids  = docs.map((d) => d.id).toList();
      final branches = docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, 'name': data['name'] as String? ?? d.id};
      }).toList();
      return FutureBuilder<BranchStats>(
        future: fetchAllBranchesStats(ids),
        builder: (_, snap) {
          if (!snap.hasData) return DashLoadingCard(t: t, height: 140);
          final s = snap.data!;
          return Column(children: [
            KpiTilesRow(t: t, s: s, branchCount: branches.length),
            const SizedBox(height: 12),
            _TopBranchFetcher(t: t, branches: branches),
          ]);
        },
      );
    },
  );

  Widget _grandSummary() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 300);
      final docs = snap.data!.docs;
      final ids  = docs.map((d) => d.id).toList();
      final branches = docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, 'name': data['name'] as String? ?? d.id};
      }).toList()..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      return FutureBuilder<BranchStats>(
        future: fetchAllBranchesStats(ids),
        builder: (_, snap) {
          if (!snap.hasData) return DashLoadingCard(t: t, height: 300);
          final totals = snap.data!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GrandTotalsCard(t: t, s: totals),
            const SizedBox(height: 12),
            PatientDistributionCard(t: t, s: totals),
            const SizedBox(height: 12),
            ServiceRevenueCard(t: t, s: totals),
            const SizedBox(height: 28),
            DashHeading('Branch Performance', t: t), const SizedBox(height: 14),
            _BranchDonationsFetcher(t: t, branches: branches),
            const SizedBox(height: 16),
            ...branches.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: BranchSummaryCard(t: t, branchId: b['id']!, branchName: b['name']!),
            )),
          ]);
        },
      );
    },
  );
}

class _TopBranchFetcher extends StatelessWidget {
  final RoleThemeData t;
  final List<Map<String, dynamic>> branches;
  const _TopBranchFetcher({required this.t, required this.branches});

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _findTop(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 88);
      final d = snap.data!;
      if ((d['tokens'] as int) == 0) return const SizedBox.shrink();
      return TopBranchBanner(t: t, branchName: d['name'] as String,
          revenue: d['revenue'] as int, patients: d['tokens'] as int);
    },
  );

  Future<Map<String, dynamic>> _findTop() async {
    Map<String, dynamic> best = {'name': '', 'tokens': 0, 'revenue': 0};
    for (final b in branches) {
      final s = await fetchBranchStats(b['id'] as String);
      if (s.tokens > (best['tokens'] as int)) {
        best = {'name': b['name'], 'tokens': s.tokens, 'revenue': s.totalRevenue};
      }
    }
    return best;
  }
}

class _BranchDonationsFetcher extends StatelessWidget {
  final RoleThemeData t;
  final List<Map<String, dynamic>> branches;
  const _BranchDonationsFetcher({required this.t, required this.branches});

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _fetchDonations(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 80);
      final data  = snap.data!;
      final total = data.fold<int>(0, (s, b) => s + (b['donations'] as int));
      return DonationsSummaryCard(t: t, branches: data, totalDonations: total);
    },
  );

  Future<List<Map<String, dynamic>>> _fetchDonations() async {
    final results = <Map<String, dynamic>>[];
    for (final b in branches) {
      final stats = await fetchBranchStats(b['id'] as String);
      results.add({'id': b['id'], 'name': b['name'], 'donations': stats.donations});
    }
    return results;
  }
}