// lib/pages/admin_screen.dart
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
      return _AdminDashboard(
        t: t,
        branchId: widget.branchId,
        username: widget.username,
        onGo: _go,
        onGoDonations: _goDonations,
      );
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
        color: active ? (accentColor ?? t.accent).withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10), onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(
                  color: c, fontSize: 14.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500))),
              if (active) Container(width: 6, height: 18,
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
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
  final void Function(int) onGo;
  final VoidCallback onGoDonations;

  const _AdminDashboard({
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
                            _hero(context, branches),
                            const SizedBox(height: DS.s3),

                            ExecutiveTopBranchFetcher(t: t, branches: branches),
                            const SizedBox(height: DS.s4),

                            DashSectionHeader(title: 'Quick Actions', subtitle: 'Common management tasks'),
                            _buildQuickActions(context),
                            const SizedBox(height: DS.s4),

                            DashSectionHeader(title: 'Operational Overview', subtitle: 'Live metrics across all nodes'),
                            _buildKPIOverview(branches, filter),
                            const SizedBox(height: DS.s4),

                            DashSectionHeader(
                              title: 'Branch Performance Table',
                              subtitle: 'Comparative analysis of branch output',
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

  Widget _hero(BuildContext context, List<Map<String, dynamic>> branches) {
    return Container(
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
                Text("Welcome back,", style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14)),
                const SizedBox(height: 4),
                Text(username, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Colors.amber, size: 16),
                    const SizedBox(width: 6),
                    Text("Admin Access Control Active", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(DS.s2),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(DS.r2)),
            child: Image.asset("assets/logo/gmwf.png", height: 50, width: 50),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _actionTile(context, Icons.account_balance_outlined, 'Branches', DS.blue, () => onGo(0)),
          _actionTile(context, Icons.volunteer_activism_rounded, 'Donations', DS.purple, onGoDonations),
          _actionTile(context, Icons.person_add_rounded, 'Add User', DS.green, () => onGo(1)),
          _actionTile(context, Icons.file_download_rounded, 'Reports', DS.orange, () => onGo(4)),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: DS.s2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.r2),
        child: Container(
          width: 120,
          padding: const EdgeInsets.all(DS.s2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(DS.r2),
            border: Border.all(color: DS.border),
          ),
          child: Column(
            children: [
              Container(padding: const EdgeInsets.all(DS.s1), decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
              const SizedBox(height: DS.s1),
              Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
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
                    insight: 'Aggregated from all branches',
                  ),
                ),
                const SizedBox(width: DS.s2),
                Expanded(
                  child: ActionableKPICard(
                    label: 'Total Patients',
                    value: fmtNum(s.tokens),
                    icon: Icons.people_alt_rounded,
                    color: DS.blue,
                    isPrimary: true,
                    insight: '${branches.length} active branches',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DS.s2),
            Row(
              children: [
                Expanded(
                  child: ActionableKPICard(
                    label: 'Tokens Served',
                    value: fmtNum(s.dasterkhwaanServed),
                    icon: Icons.restaurant_rounded,
                    color: DS.orange,
                    insight: '${s.dasterkhwaan} tokens issued',
                  ),
                ),
                const SizedBox(width: DS.s2),
                Expanded(
                  child: ActionableKPICard(
                    label: 'Donations',
                    value: fmtNum(s.donations),
                    prefix: 'PKR ',
                    icon: Icons.volunteer_activism_rounded,
                    color: DS.purple,
                    insight: 'Today\'s contributions',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DS.s2),
            PatientDistributionCard(t: t, s: s),
          ],
        );
      },
    );
  }
}