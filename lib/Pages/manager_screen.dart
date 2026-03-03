// lib/pages/manager_screen.dart
// Manager Portal — Slate Blue on Soft Warm White
// Same data scope as Admin: all branches, all services
// Sidebar: Overview, Donations, Branches, Register User, Patients, Users, Download, Fix Patients
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

// ── Index semantics ────────────────────────────────────────────────────────
//  -2  → Dashboard
//  -1  → Donations
//   0  → Branches
//   1  → Register User
//   2  → Patients
//   3  → Users
//   4  → Download
//   5  → Fix Patients

class ManagerScreen extends StatefulWidget {
  final String branchId;
  final String username;
  const ManagerScreen({super.key, required this.branchId, this.username = 'Manager'});
  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen>
    with SingleTickerProviderStateMixin {
  int _pageIndex = -2;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 380), vsync: this);
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

  @override
  Widget build(BuildContext context) {
    final t        = RoleThemeScope.dataOf(context);
    final isMobile = MediaQuery.of(context).size.width < 820;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: isMobile ? _appBar(t) : null,
      drawer: isMobile
          ? Drawer(backgroundColor: t.bgCard, child: _sidebar(t))
          : null,
      body: Row(children: [
        if (!isMobile) _sidebar(t),
        Expanded(child: FadeTransition(opacity: _fadeAnim, child: _buildBody(t))),
      ]),
    );
  }

  Widget _buildBody(RoleThemeData t) {
    if (_pageIndex == -2) {
      return _ManagerDashboard(t: t, branchId: widget.branchId, username: widget.username);
    }
    if (_pageIndex == -1) {
      return FadeTransition(opacity: _fadeAnim,
          child: DonationsScreen.embedded(
              branchId: widget.branchId, username: widget.username));
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
      role: RoleTheme.manager,
      child: FadeTransition(opacity: _fadeAnim,
          child: _pageIndex == 1 ? page : Container(color: t.bg, child: page)),
    );
  }

  AppBar _appBar(RoleThemeData t) => AppBar(
    backgroundColor: t.bgCard, elevation: 0, surfaceTintColor: Colors.transparent,
    leading: Builder(builder: (ctx) => IconButton(
        icon: Icon(Icons.menu_rounded, color: t.accent, size: 22),
        onPressed: () => Scaffold.of(ctx).openDrawer())),
    title: Row(children: [
      Image.asset("assets/logo/gmwf.png", height: 28, width: 28),
      const SizedBox(width: 10),
      Text("Manager", style: TextStyle(
          color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
    ]),
    actions: [
      if (_pageIndex != -2)
        IconButton(icon: Icon(Icons.home_outlined, color: t.accent, size: 22),
            onPressed: _goDashboard),
      IconButton(icon: Icon(Icons.logout_outlined, color: t.danger, size: 22),
          onPressed: _logout),
    ],
    bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: t.bgRule)),
  );

  Widget _sidebar(RoleThemeData t) => Container(
    width: 256,
    decoration: BoxDecoration(
        color: t.bgCard, border: Border(right: BorderSide(color: t.bgRule))),
    child: Column(children: [
      const SizedBox(height: 48),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: t.accentMuted,
                  borderRadius: BorderRadius.circular(12)),
              child: Image.asset("assets/logo/gmwf.png", height: 28, width: 28)),
          const SizedBox(height: 14),
          Text('GMWF', style: TextStyle(
              color: t.accent, fontSize: 16,
              fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          Text('Manager Portal', style: TextStyle(color: t.textTertiary, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 24),
      Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 12),

      _navTile(t, Icons.home_outlined,              'Overview',  _pageIndex == -2, _goDashboard),
      _navTile(t, Icons.volunteer_activism_rounded, 'Donations', _pageIndex == -1, _goDonations,
          accentColor: _cDonation),

      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.only(left: 26, bottom: 8, top: 4),
        child: Text('MANAGE', style: TextStyle(
            color: t.textTertiary, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 2))),

      Expanded(child: ListView(padding: EdgeInsets.zero, children: [
        _navTile(t, Icons.account_balance_outlined, 'Branches',      _pageIndex == 0, () => _go(0)),
        _navTile(t, Icons.person_add_outlined,      'Register User',  _pageIndex == 1, () => _go(1)),
        _navTile(t, Icons.favorite_border_rounded,  'Patients',       _pageIndex == 2, () => _go(2)),
        _navTile(t, Icons.people_outline_rounded,   'Users',          _pageIndex == 3, () => _go(3)),
        _navTile(t, Icons.download_outlined,        'Download',       _pageIndex == 4, () => _go(4)),
        _navTile(t, Icons.build_outlined,           'Fix Patients',   _pageIndex == 5, () => _go(5),
            accentColor: t.danger),
      ])),

      Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 4),
      _navTile(t, Icons.logout_outlined, 'Sign Out', false, _logout, danger: true),
      const SizedBox(height: 24),
    ]),
  );

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

// ── Manager Dashboard (same data as Admin — all branches) ─────────────────────
class _ManagerDashboard extends StatelessWidget {
  final RoleThemeData t;
  final String branchId, username;
  const _ManagerDashboard({required this.t, required this.branchId, required this.username});

  @override
  Widget build(BuildContext context) => Container(
    color: t.bg,
    child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hero(),
          const SizedBox(height: 28),
          _kpiSection(),
          const SizedBox(height: 28),
          DashHeading("Today's Summary", t: t),
          const SizedBox(height: 16),
          _grandSummary(),
          const SizedBox(height: 24),
        ]),
      )),
    ),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [t.accent, t.accentLight],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(color: t.accent.withOpacity(0.28),
          blurRadius: 32, offset: const Offset(0, 10))],
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 12),
            const SizedBox(width: 6),
            Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: const TextStyle(color: Colors.white70, fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(height: 16),
        Text("Welcome back,",
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14)),
        const SizedBox(height: 4),
        Text(username, style: const TextStyle(
            color: Colors.white, fontSize: 28,
            fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text("Full access · All branches · All data",
            style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13)),
      ])),
      const SizedBox(width: 20),
      Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Image.asset("assets/logo/gmwf.png", height: 52, width: 52)),
    ]),
  );

  // KPI tiles + top branch — all branches (same as admin)
  Widget _kpiSection() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 140);
      final docs     = snap.data!.docs;
      final ids      = docs.map((d) => d.id).toList();
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

  // Grand totals + donut + service revenue + branch cards — all branches (same as admin)
  Widget _grandSummary() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 300);
      final docs     = snap.data!.docs;
      final ids      = docs.map((d) => d.id).toList();
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

// ── Shared helpers ────────────────────────────────────────────────────────────

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
      return TopBranchBanner(
        t: t, branchName: d['name'] as String,
        revenue: d['revenue'] as int, patients: d['tokens'] as int,
      );
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