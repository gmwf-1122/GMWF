// lib/pages/chairman_screen.dart
// Chairman Portal — Most Premium Role
// Champagne Gold · Warm Ivory · Staggered animations · Shimmer loading
// Sidebar: Overview, Donations, Branches, Register User, Patients, Users, Download
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
import 'donations/donations_screen.dart';

const _cGoldBorder = Color(0xFFEDD88A);
const _cGreen      = Color(0xFF16A34A);
const _cGreenMuted = Color(0xFFDCFCE7);

class ChairmanScreen extends StatefulWidget {
  final String username;
  const ChairmanScreen({super.key, this.username = 'Chairman'});
  @override
  State<ChairmanScreen> createState() => _ChairmanScreenState();
}

class _ChairmanScreenState extends State<ChairmanScreen>
    with TickerProviderStateMixin {
  final _t = RoleThemeData.of(RoleTheme.chairman);
  int _pageIndex = -2;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 420), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _shimmerCtrl = AnimationController(
        duration: const Duration(milliseconds: 1800), vsync: this)
      ..repeat();
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _go(int idx)    { setState(() => _pageIndex = idx);  _fadeCtrl.forward(from: 0); }
  void _goDashboard()  { setState(() => _pageIndex = -2); _fadeCtrl.forward(from: 0); }
  void _goDonations()  { setState(() => _pageIndex = -1); _fadeCtrl.forward(from: 0); }
  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 820;
    return Scaffold(
      backgroundColor: _t.bg,
      appBar: isMobile ? _appBar() : null,
      drawer: isMobile
          ? Drawer(backgroundColor: _t.bgCard, child: _sidebar())
          : null,
      body: Row(children: [
        if (!isMobile) _sidebar(),
        Expanded(child: FadeTransition(opacity: _fadeAnim, child: _buildBody())),
      ]),
    );
  }

  Widget _buildBody() {
    if (_pageIndex == -2) return _ChairmanDashboard(t: _t, username: widget.username);
    if (_pageIndex == -1) return _AllBranchDonationsView(t: _t, username: widget.username);
    Widget page;
    switch (_pageIndex) {
      case 0:  page = const Branches(); break;
      case 1:  page = const Register(); break;
      case 2:  page = const UsersScreen(isPatientMode: true); break;
      case 3:  page = const UsersScreen(); break;
      case 4:  page = const DownloadScreen(); break;
      default: page = const SizedBox.shrink();
    }
    return RoleThemeScope(
        role: RoleTheme.chairman, child: Container(color: _t.bg, child: page));
  }

  AppBar _appBar() => AppBar(
    backgroundColor: _t.bgCard, elevation: 0, surfaceTintColor: Colors.transparent,
    leading: Builder(builder: (ctx) => IconButton(
        icon: Icon(Icons.menu_rounded, color: _t.textSecondary, size: 22),
        onPressed: () => Scaffold.of(ctx).openDrawer())),
    title: Row(children: [
      Image.asset("assets/logo/gmwf.png", height: 28, width: 28),
      const SizedBox(width: 10),
      Text("CHAIRMAN", style: TextStyle(
          color: _t.accent, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 3)),
    ]),
    actions: [
      if (_pageIndex != -2)
        IconButton(icon: Icon(Icons.home_outlined, color: _t.accentLight, size: 22),
            onPressed: _goDashboard),
      IconButton(icon: Icon(Icons.logout_rounded, color: _t.danger, size: 22),
          onPressed: _logout),
    ],
    bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: _t.bgRule)),
  );

  Widget _sidebar() => Container(
    width: 256,
    decoration: BoxDecoration(
      color: _t.bgCard,
      border: Border(right: BorderSide(color: _t.bgRule)),
    ),
    child: Column(children: [
      const SizedBox(height: 48),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Gold-bordered logo
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _t.accentMuted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cGoldBorder, width: 1.5),
              boxShadow: [BoxShadow(
                  color: _t.accent.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Center(child: Image.asset("assets/logo/gmwf.png", height: 30, width: 30)),
          ),
          const SizedBox(height: 14),
          Text('GMWF', style: TextStyle(
              color: _t.accent, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          Text('Chairman Portal', style: TextStyle(
              color: _t.textTertiary, fontSize: 12, fontStyle: FontStyle.italic)),
        ]),
      ),
      const SizedBox(height: 24),
      Divider(height: 1, color: _t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 12),

      _navTile(Icons.analytics_outlined,           'Overview',     _pageIndex == -2, _goDashboard),
      _navTile(Icons.volunteer_activism_rounded,   'Donations',    _pageIndex == -1, _goDonations,
          accentColor: _cGreen),

      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.only(left: 26, bottom: 8, top: 4),
        child: Text('MANAGEMENT', style: TextStyle(
            color: _t.textTertiary, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 2.5))),

      Expanded(child: ListView(padding: EdgeInsets.zero, children: [
        _navTile(Icons.account_balance_outlined, 'Branches',     _pageIndex == 0, () => _go(0)),
        _navTile(Icons.person_add_outlined,      'Register User', _pageIndex == 1, () => _go(1)),
        _navTile(Icons.favorite_border_rounded,  'Patients',     _pageIndex == 2, () => _go(2)),
        _navTile(Icons.people_outline_rounded,   'Users',        _pageIndex == 3, () => _go(3)),
        _navTile(Icons.download_outlined,        'Download',     _pageIndex == 4, () => _go(4)),
      ])),

      Divider(height: 1, color: _t.bgRule, indent: 24, endIndent: 24),
      const SizedBox(height: 4),
      _navTile(Icons.logout_rounded, 'Sign Out', false, _logout, danger: true),
      const SizedBox(height: 24),
    ]),
  );

  Widget _navTile(IconData icon, String label, bool active, VoidCallback onTap,
      {bool danger = false, Color? accentColor}) {
    final Color c = danger ? _t.danger : active ? (accentColor ?? _t.accent) : _t.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: active ? (accentColor ?? _t.accent).withOpacity(0.10) : Colors.transparent,
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
                  decoration: BoxDecoration(color: accentColor ?? _t.accent, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── All-Branch Donations View ─────────────────────────────────────────────────
class _AllBranchDonationsView extends StatefulWidget {
  final RoleThemeData t;
  final String username;
  const _AllBranchDonationsView({required this.t, required this.username});
  @override
  State<_AllBranchDonationsView> createState() => _AllBranchDonationsViewState();
}

class _AllBranchDonationsViewState extends State<_AllBranchDonationsView>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, String>> _branches = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadBranches(); }

  @override
  void dispose() { _tabController?.dispose(); super.dispose(); }

  Future<void> _loadBranches() async {
    final snap = await FirebaseFirestore.instance.collection('branches').get();
    final list = snap.docs.map((d) {
      final data = d.data();
      return {'id': d.id, 'name': (data['name'] as String?) ?? d.id};
    }).toList()..sort((a, b) => a['name']!.compareTo(b['name']!));
    if (mounted) setState(() {
      _branches = list; _loading = false;
      _tabController = TabController(length: list.length, vsync: this);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_loading) return Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 2.5));
    if (_branches.isEmpty) return Center(child: Text('No branches found.',
        style: TextStyle(color: t.textSecondary)));
    return Column(children: [
      Container(
        decoration: BoxDecoration(color: t.bgCard,
            border: Border(bottom: BorderSide(color: t.bgRule))),
        child: SafeArea(bottom: false, child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _cGreenMuted,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.volunteer_activism_rounded,
                      color: _cGreen, size: 20)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('All-Branch Donations', style: TextStyle(
                    color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                    style: TextStyle(color: t.textTertiary, fontSize: 12)),
              ]),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _cGreen.withOpacity(0.10), borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _cGreen.withOpacity(0.3)),
                ),
                child: Text('CHAIRMAN', style: TextStyle(
                    color: _cGreen, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController, isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: _cGreen, labelColor: _cGreen,
            unselectedLabelColor: t.textTertiary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: _branches.map((b) => Tab(text: b['name'])).toList(),
          ),
        ])),
      ),
      Expanded(child: TabBarView(
        controller: _tabController,
        children: _branches.map((b) => DonationsScreen.embedded(
          branchId: b['id']!, username: widget.username,
          branchName: b['name']!, role: 'chairman',
        )).toList(),
      )),
    ]);
  }
}

// ── Chairman Dashboard ────────────────────────────────────────────────────────
class _ChairmanDashboard extends StatefulWidget {
  final RoleThemeData t;
  final String username;
  const _ChairmanDashboard({required this.t, required this.username});
  @override
  State<_ChairmanDashboard> createState() => _ChairmanDashboardState();
}

class _ChairmanDashboardState extends State<_ChairmanDashboard>
    with TickerProviderStateMixin {
  // Staggered entry animations
  late List<AnimationController> _staggerCtrls;
  late List<Animation<double>> _staggerAnims;
  static const _staggerCount = 6;

  @override
  void initState() {
    super.initState();
    _staggerCtrls = List.generate(_staggerCount, (i) => AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this));
    _staggerAnims = _staggerCtrls.map((c) =>
        CurvedAnimation(parent: c, curve: Curves.easeOutCubic)).toList();

    // Stagger each section's entry
    for (int i = 0; i < _staggerCount; i++) {
      Future.delayed(Duration(milliseconds: 80 + i * 110), () {
        if (mounted) _staggerCtrls[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _staggerCtrls) c.dispose();
    super.dispose();
  }

  Widget _stagger(int i, Widget child) => FadeTransition(
    opacity: _staggerAnims[i],
    child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
          .animate(_staggerAnims[i]),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Container(
      color: t.bg,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // 0 — Hero
            _stagger(0, _PremiumHero(t: t, username: widget.username)),
            const SizedBox(height: 28),

            // 1 — KPI tiles + top branch (needs branch data)
            _stagger(1, _BranchStatsSection(t: t)),
            const SizedBox(height: 28),

            // 2 — Today's Numbers heading
            _stagger(2, DashHeading("Today's Numbers", t: t)),
            const SizedBox(height: 16),

            // 3 — Grand totals + donut
            _stagger(3, _AllBranchTotalsSection(t: t)),
            const SizedBox(height: 28),

            // 4 — Donations
            _stagger(4, DashHeading('Donations Collected', t: t)),
            const SizedBox(height: 14),
            _stagger(4, _BranchDonationsFetcher(t: t)),
            const SizedBox(height: 28),

            // 5 — Branch breakdown
            _stagger(5, DashHeading('Branch Summaries', t: t)),
            const SizedBox(height: 14),
            _stagger(5, _BranchCardsList(t: t)),
          ]),
        )),
      ),
    );
  }
}

// ── Premium Gold Hero ─────────────────────────────────────────────────────────
class _PremiumHero extends StatelessWidget {
  final RoleThemeData t;
  final String username;
  const _PremiumHero({required this.t, required this.username});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      // Warm ivory card — not a gradient so text reads beautifully
      color: t.bgCard,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _cGoldBorder, width: 1.5),
      boxShadow: [
        BoxShadow(color: t.accent.withOpacity(0.12), blurRadius: 32, offset: const Offset(0, 8)),
        BoxShadow(color: t.accent.withOpacity(0.06), blurRadius: 8,  offset: const Offset(0, 2)),
      ],
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Role badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: t.accentMuted,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _cGoldBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.workspace_premium_rounded, color: t.accent, size: 13),
            const SizedBox(width: 6),
            Text('CHAIRMAN', style: TextStyle(
                color: t.accent, fontSize: 11,
                fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ]),
        ),
        const SizedBox(height: 14),
        Text('Welcome back,', style: TextStyle(color: t.textSecondary, fontSize: 14)),
        const SizedBox(height: 4),
        Text(username, style: TextStyle(
            color: t.textPrimary, fontSize: 30,
            fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
        const SizedBox(height: 10),
        // Gold divider line
        Container(height: 1.5, width: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [t.accent, t.accent.withOpacity(0)]),
              borderRadius: BorderRadius.circular(1),
            )),
        const SizedBox(height: 10),
        Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: TextStyle(color: t.textTertiary, fontSize: 13)),
      ])),
      const SizedBox(width: 20),
      // Glowing logo box
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.accentMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _cGoldBorder, width: 1.5),
          boxShadow: [BoxShadow(
              color: t.accent.withOpacity(0.20), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Image.asset("assets/logo/gmwf.png", height: 54, width: 54),
      ),
    ]),
  );
}

// ── KPI + Top Branch section ──────────────────────────────────────────────────
class _BranchStatsSection extends StatelessWidget {
  final RoleThemeData t;
  const _BranchStatsSection({required this.t});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
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
          final totals = snap.data!;
          return Column(children: [
            KpiTilesRow(t: t, s: totals, branchCount: branches.length),
            const SizedBox(height: 12),
            _TopBranchFetcher(t: t, branches: branches),
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
      return TopBranchBanner(
        t: t,
        branchName: d['name'] as String,
        revenue:    d['revenue'] as int,
        patients:   d['tokens'] as int,
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

// ── All-branch totals section (grand totals + donut) ─────────────────────────
class _AllBranchTotalsSection extends StatelessWidget {
  final RoleThemeData t;
  const _AllBranchTotalsSection({required this.t});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
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
            ServiceRevenueCard(t: t, s: s),
          ]);
        },
      );
    },
  );
}

// ── Donations fetcher ─────────────────────────────────────────────────────────
class _BranchDonationsFetcher extends StatelessWidget {
  final RoleThemeData t;
  const _BranchDonationsFetcher({required this.t});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('branches').snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) return DashLoadingCard(t: t, height: 80);
      final branches = snap.data!.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, 'name': data['name'] as String? ?? d.id};
      }).toList();
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchDonations(branches),
        builder: (_, snap) {
          if (!snap.hasData) return DashLoadingCard(t: t, height: 80);
          final data  = snap.data!;
          final total = data.fold<int>(0, (s, b) => s + (b['donations'] as int));
          return DonationsSummaryCard(t: t, branches: data, totalDonations: total);
        },
      );
    },
  );

  Future<List<Map<String, dynamic>>> _fetchDonations(
      List<Map<String, dynamic>> branches) async {
    final results = <Map<String, dynamic>>[];
    for (final b in branches) {
      final stats = await fetchBranchStats(b['id'] as String);
      results.add({'id': b['id'], 'name': b['name'], 'donations': stats.donations});
    }
    return results;
  }
}

// ── Branch cards list ─────────────────────────────────────────────────────────
class _BranchCardsList extends StatelessWidget {
  final RoleThemeData t;
  const _BranchCardsList({required this.t});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
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