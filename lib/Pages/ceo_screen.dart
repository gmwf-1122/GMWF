// lib/pages/ceo_screen.dart
// CEO Portal — Midnight Navy on Crisp White
// Sidebar: Overview + Branches ONLY — no donations visible
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import 'branches.dart';

class CeoScreen extends StatefulWidget {
  final String username;
  const CeoScreen({super.key, this.username = 'CEO'});
  @override
  State<CeoScreen> createState() => _CeoScreenState();
}

class _CeoScreenState extends State<CeoScreen>
    with SingleTickerProviderStateMixin {
  int _pageIndex = -1;
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
  void _goDashboard() { setState(() => _pageIndex = -1); _fadeCtrl.forward(from: 0); }

  @override
  Widget build(BuildContext context) {
    final t       = RoleThemeScope.dataOf(context);
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
    if (_pageIndex == -1) return _CeoDashboard(t: t, username: widget.username);
    return RoleThemeScope(
        role: RoleTheme.ceo, child: Container(color: t.bg, child: const Branches()));
  }

  AppBar _appBar(RoleThemeData t) => AppBar(
    backgroundColor: t.bgCard, elevation: 0, surfaceTintColor: Colors.transparent,
    leading: Builder(builder: (ctx) => IconButton(
        icon: Icon(Icons.menu_rounded, color: t.textSecondary, size: 22),
        onPressed: () => Scaffold.of(ctx).openDrawer())),
    title: Row(children: [
      Image.asset("assets/logo/gmwf.png", height: 28, width: 28),
      const SizedBox(width: 10),
      Text("CEO View", style: TextStyle(
          color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
    ]),
    actions: [
      if (_pageIndex != -1)
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
        color: t.bgCard,
        border: Border(right: BorderSide(color: t.bgRule))),
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
          Text('CEO Dashboard', style: TextStyle(color: t.textTertiary, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 24),
      Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 12),
      _navTile(t, Icons.dashboard_outlined,       'Overview', _pageIndex == -1, _goDashboard),
      _navTile(t, Icons.account_balance_outlined, 'Branches', _pageIndex ==  0, () => _go(0)),
      const Spacer(),
      Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 4),
      _navTile(t, Icons.logout_outlined, 'Sign Out', false, _logout, danger: true),
      const SizedBox(height: 24),
    ]),
  );

  Widget _navTile(RoleThemeData t, IconData icon, String label, bool active,
      VoidCallback onTap, {bool danger = false}) {
    final Color c = danger ? t.danger : active ? t.accent : t.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: active ? t.accent.withOpacity(0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10), onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(
                  color: c, fontSize: 14.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
              if (active) Container(width: 6, height: 6,
                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── CEO Dashboard ─────────────────────────────────────────────────────────────
class _CeoDashboard extends StatelessWidget {
  final RoleThemeData t;
  final String username;
  const _CeoDashboard({required this.t, required this.username});

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
          DashHeading("Today's Performance", t: t),
          const SizedBox(height: 16),
          _totalsSection(),
          const SizedBox(height: 28),
          DashHeading('Branch Breakdown', t: t),
          const SizedBox(height: 14),
          _branchCards(),
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
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.business_outlined, color: Colors.white70, size: 12),
            const SizedBox(width: 6),
            Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: const TextStyle(color: Colors.white70, fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(height: 16),
        Text("Good day,", style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14)),
        const SizedBox(height: 4),
        Text(username, style: const TextStyle(
            color: Colors.white, fontSize: 28,
            fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text("Executive overview · All branches",
            style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13)),
      ])),
      const SizedBox(width: 20),
      Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Image.asset("assets/logo/gmwf.png", height: 52, width: 52)),
    ]),
  );

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

  Widget _totalsSection() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 300);
      final ids = snap.data!.docs.map((d) => d.id).toList();
      return FutureBuilder<BranchStats>(
        future: fetchAllBranchesStats(ids),
        builder: (_, snap) {
          if (!snap.hasData) return DashLoadingCard(t: t, height: 300);
          final s = snap.data!;
          return Column(children: [
            GrandTotalsCard(t: t, s: s),
            const SizedBox(height: 12),
            PatientDistributionCard(t: t, s: s),
            const SizedBox(height: 12),
            // CEO sees service revenue but NO donations card
            _ServiceOnlyCard(t: t, s: s),
          ]);
        },
      );
    },
  );

  Widget _branchCards() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 200);
      final branches = snap.data!.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, 'name': data['name'] as String? ?? d.id};
      }).toList()..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      return Column(children: branches.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: BranchSummaryCard(t: t, branchId: b['id']!, branchName: b['name']!),
      )).toList());
    },
  );
}

// ── Service-only card (CEO: no donation row) ──────────────────────────────────
class _ServiceOnlyCard extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  const _ServiceOnlyCard({required this.t, required this.s});

  @override
  Widget build(BuildContext context) {
    const dasColor = Color(0xFF0891B2);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.bgRule),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Dasterkhwaan Service', style: TextStyle(
            color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: dasColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.restaurant_outlined, color: dasColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dasterkhwaan Food Tokens', style: TextStyle(
                color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${s.dasterkhwaan} tokens · × PKR 10',
                style: TextStyle(color: t.textTertiary, fontSize: 11)),
          ])),
          Text(fmtPKR(s.dasterkhwaanRevenue),
              style: const TextStyle(color: dasColor, fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }
}

// ── Top Branch Fetcher ────────────────────────────────────────────────────────
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