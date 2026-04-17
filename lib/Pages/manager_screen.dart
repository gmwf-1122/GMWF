import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/scroll_reveal.dart';
import 'branches.dart';
import 'register.dart';
import 'download_screen.dart';
import 'users.dart';
import 'donations/donations_screen.dart';
import 'dasterkhwaan/kitchen.dart';
import 'dispensary/receptionist/patient_register.dart';

const _cDonation = Color(0xFF6A1B9A);

class ManagerScreen extends StatefulWidget {
  final String branchId;
  final String username;
  const ManagerScreen(
      {super.key, required this.branchId, this.username = 'Manager'});
  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen>
    with SingleTickerProviderStateMixin {
  int _pageIndex = -2;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 380), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  void _go(int idx) {
    setState(() => _pageIndex = idx);
    _fadeCtrl.forward(from: 0);
  }

  void _goDashboard() {
    setState(() => _pageIndex = -2);
    _fadeCtrl.forward(from: 0);
  }

  void _goDonations() {
    setState(() => _pageIndex = -1);
    _fadeCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isMobile = MediaQuery.of(context).size.width < 820;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: isMobile ? _appBar(t) : null,
      drawer:
          isMobile ? Drawer(backgroundColor: t.bgCard, child: _sidebar(t)) : null,
      body: Row(
        children: [
          if (!isMobile) _sidebar(t),
          // FIX: ClipRect + Material isolate the inner DonationsScreen so
          // its TabBar/TabController cannot escape into the sidebar.
          Expanded(
            child: ClipRect(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _buildBody(t),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(RoleThemeData t) {
    switch (_pageIndex) {
      case -2:
        return _ManagerDashboard(
          t: t,
          branchId: widget.branchId,
          username: widget.username,
          onGo: _go,
          onGoDonations: _goDonations,
        );
      case -1:
        // FIX: Wrap in Material to break the DefaultTabController.of(context)
        // lookup chain. DonationsScreen's internal TabController stays
        // inside this Material boundary and never resolves upward.
        return Material(
          color: t.bg,
          child: DonationsScreen.embedded(
            branchId: widget.branchId,
            username: widget.username,
          ),
        );
      case 0:
        // isManager: true — enables the Revert button on frequent-patient cards
        return RoleThemeScope(
            role: RoleTheme.manager,
            child: const Branches(isManager: true));
      case 1:
        return RoleThemeScope(role: RoleTheme.manager, child: const Register());
      case 2:
        return RoleThemeScope(
            role: RoleTheme.manager,
            child: Container(
                color: t.bg,
                child: const UsersScreen(isPatientMode: true)));
      case 3:
        return RoleThemeScope(
            role: RoleTheme.manager,
            child: Container(color: t.bg, child: const UsersScreen()));
      case 4:
        return RoleThemeScope(
            role: RoleTheme.manager,
            child: Container(color: t.bg, child: const DownloadScreen()));
      case 6:
        return RoleThemeScope(
          role: RoleTheme.manager,
          child: PatientRegisterPage(
            branchId: widget.branchId,
            receptionistId: 'manager_${widget.username}',
          ),
        );
      case 7:
        return RoleThemeScope(
          role: RoleTheme.manager,
          child: DasterkhwaanKitchen(
            branchId: widget.branchId,
            username: widget.username,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  AppBar _appBar(RoleThemeData t) => AppBar(
        backgroundColor: t.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu_rounded, color: t.accent, size: 22),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(children: [
          Image.asset("assets/logo/gmwf.png", height: 28, width: 28),
          const SizedBox(width: 10),
          Text("Manager",
              style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
        ]),
        actions: [
          if (_pageIndex != -2)
            IconButton(
                icon: Icon(Icons.home_outlined, color: t.accent, size: 22),
                onPressed: _goDashboard),
          IconButton(
              icon: Icon(Icons.logout_outlined, color: t.danger, size: 22),
              onPressed: _logout),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: t.bgRule)),
      );

  Widget _sidebar(RoleThemeData t) => Container(
        width: 256,
        decoration: BoxDecoration(
            color: t.bgCard,
            border: Border(right: BorderSide(color: t.bgRule))),
        child: Column(children: [
          const SizedBox(height: 48),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: t.accentMuted,
                      borderRadius: BorderRadius.circular(12)),
                  child:
                      Image.asset("assets/logo/gmwf.png", height: 28, width: 28)),
              const SizedBox(height: 14),
              Text('GMWF',
                  style: TextStyle(
                      color: t.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
              Text('HQ Manager Portal',
                  style: TextStyle(color: t.textTertiary, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
          const SizedBox(height: 12),
          _navTile(
              t, Icons.home_outlined, 'Overview', _pageIndex == -2, _goDashboard),
          _navTile(
              t,
              Icons.volunteer_activism_rounded,
              'Donations',
              _pageIndex == -1,
              _goDonations,
              accentColor: _cDonation),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 8, top: 4),
            child: Text('MANAGE',
                style: TextStyle(
                    color: t.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              _navTile(t, Icons.account_balance_outlined, 'Branches',
                  _pageIndex == 0, () => _go(0)),
              _navTile(t, Icons.person_add_outlined, 'Register User',
                  _pageIndex == 1, () => _go(1)),
              _navTile(t, Icons.favorite_border_rounded, 'Patients',
                  _pageIndex == 2, () => _go(2)),
              _navTile(t, Icons.people_outline_rounded, 'Users',
                  _pageIndex == 3, () => _go(3)),
              _navTile(t, Icons.download_outlined, 'Download',
                  _pageIndex == 4, () => _go(4)),
              _navTile(t, Icons.person_add_alt_1_outlined, 'Register Patient',
                  _pageIndex == 6, () => _go(6)),
              _navTile(t, Icons.restaurant_outlined, 'Kitchen Ops',
                  _pageIndex == 7, () => _go(7)),
            ]),
          ),
          Divider(height: 1, color: t.bgRule, indent: 24, endIndent: 24),
          const SizedBox(height: 4),
          _navTile(t, Icons.logout_outlined, 'Sign Out', false, _logout,
              danger: true),
          const SizedBox(height: 24),
        ]),
      );

  Widget _navTile(
    RoleThemeData t,
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap, {
    bool danger = false,
    Color? accentColor,
  }) {
    final Color c =
        danger ? t.danger : active ? (accentColor ?? t.accent) : t.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: active
            ? (accentColor ?? t.accent).withOpacity(0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: c,
                        fontSize: 14.5,
                        fontWeight: active
                            ? FontWeight.w800
                            : FontWeight.w500)),
              ),
              if (active)
                Container(
                    width: 6,
                    height: 18,
                    decoration:
                        BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MANAGER DASHBOARD
// (unchanged from original)
// ════════════════════════════════════════════════════════════════════════════

class _ManagerDashboard extends StatelessWidget {
  final RoleThemeData t;
  final String branchId, username;
  final void Function(int) onGo;
  final VoidCallback onGoDonations;

  const _ManagerDashboard({
    required this.t,
    required this.branchId,
    required this.username,
    required this.onGo,
    required this.onGoDonations,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.bg,
      child: ValueListenableBuilder<DashboardFilter>(
        valueListenable: dashboardController,
        builder: (context, filter, child) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('branches').snapshots(),
            builder: (context, branchSnap) {
              final branches = branchSnap.hasData
                  ? branchSnap.data!.docs.map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return <String, dynamic>{'id': d.id, 'name': data['name'] as String? ?? d.id};
                    }).toList()
                  : <Map<String, dynamic>>[];

              return Column(
                children: [
                  GlobalFilterBar(controller: dashboardController, branches: branches),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.all(DS.s3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _hero(),
                            const SizedBox(height: DS.s3),

                            ExecutiveTopBranchFetcher(t: t, branches: branches),
                            const SizedBox(height: DS.s4),

                            DashSectionHeader(title: 'Quick Access', subtitle: 'Primary operational tools'),
                            _buildQuickLinks(context),
                            const SizedBox(height: DS.s4),

                            DashSectionHeader(title: 'High-Level Metrics', subtitle: 'Consolidated performance data'),
                            _buildKPIOverview(branches, filter),
                            const SizedBox(height: DS.s4),

                            DashSectionHeader(
                              title: 'Branch Performance Breakdown',
                              subtitle: 'Real-time efficiency tracking',
                            ),
                            const SizedBox(height: DS.s2),
                            BranchPerformanceTable(t: t, branches: branches),
                            const SizedBox(height: DS.s4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(DS.s3),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [t.accent, t.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(DS.r3),
      boxShadow: [BoxShadow(color: t.accent.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8))],
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Welcome back,", style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13)),
              const SizedBox(height: 4),
              Text(username, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: const Text("MANAGER AUTHORITY • ACTIVE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(DS.s2),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(DS.r2)),
          child: Image.asset("assets/logo/gmwf.png", height: 48, width: 48),
        ),
      ],
    ),
  );

  Widget _buildQuickLinks(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _actionBtn(context, Icons.volunteer_activism_rounded, 'Donations', DS.purple, onGoDonations)),
            const SizedBox(width: DS.s2),
            Expanded(child: _actionBtn(context, Icons.account_balance_outlined, 'Branches', DS.blue, () => onGo(0))),
            const SizedBox(width: DS.s2),
            Expanded(child: _actionBtn(context, Icons.person_add_alt_1_rounded, 'Registration', DS.blue, () => onGo(6))),
          ],
        ),
        const SizedBox(height: DS.s2),
        Row(
          children: [
            Expanded(child: _actionBtn(context, Icons.restaurant_rounded, 'Kitchen Ops', DS.orange, () => onGo(7))),
            const SizedBox(width: DS.s2),
            Expanded(child: _actionBtn(context, Icons.download_rounded, 'Reports', DS.neutral, () => onGo(4))),
          ],
        ),
      ],
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DS.r2),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: DS.s2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(DS.r2),
          border: Border.all(color: DS.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIOverview(List<Map<String, dynamic>> branches, DashboardFilter filter) {
    return StreamBuilder<BranchStats>(
      stream: streamAllBranchesStats(branches.map((b) => b['id'] as String).toList(), filter: filter),
      builder: (context, snap) {
        final s = snap.data ?? const BranchStats();
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ActionableKPICard(
                    label: 'Total Revenue',
                    value: fmtNum(s.totalRevenue),
                    prefix: 'PKR ',
                    icon: Icons.payments_rounded,
                    color: DS.green,
                    isPrimary: true,
                    insight: 'Operational income',
                  ),
                ),
                const SizedBox(width: DS.s2),
                Expanded(
                  child: ActionableKPICard(
                    label: 'Total Patients',
                    value: fmtNum(s.tokens),
                    icon: Icons.personal_injury_rounded,
                    color: DS.blue,
                    isPrimary: true,
                    insight: 'Patients across nodes',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DS.s2),
            Row(
              children: [
                Expanded(child: ActionableKPICard(label: 'Tokens Served', value: fmtNum(s.dasterkhwaanServed), icon: Icons.restaurant_rounded, color: DS.orange, insight: '${s.dasterkhwaan} tokens issued')),
                const SizedBox(width: DS.s2),
                Expanded(child: ActionableKPICard(label: 'Donations', value: fmtNum(s.donations), prefix: 'PKR ', icon: Icons.volunteer_activism_rounded, color: DS.purple, insight: 'Today\'s intake')),
              ],
            ),
          ],
        );
      },
    );
  }
}


class _BranchDonationsFetcher extends StatelessWidget {
  final RoleThemeData t;
  final List<Map<String, dynamic>> branches;
  const _BranchDonationsFetcher({required this.t, required this.branches});

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchDonations(),
        builder: (_, snap) {
          if (!snap.hasData) return DashLoadingCard(t: t, height: 80);
          final data = snap.data!;
          final total =
              data.fold<int>(0, (s, b) => s + (b['donations'] as int));
          return DonationsSummaryCard(
              t: t, branches: data, totalDonations: total);
        },
      );

  Future<List<Map<String, dynamic>>> _fetchDonations() async {
    final results = <Map<String, dynamic>>[];
    for (final b in branches) {
      final stats = await fetchBranchStats(b['id'] as String);
      results.add(
          {'id': b['id'], 'name': b['name'], 'donations': stats.donations});
    }
    return results;
  }
}