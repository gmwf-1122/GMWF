// lib/pages/branch_manager_screen.dart
// Redesigned: compact hero · RevenueHeroCard · OperationsOverviewRow · FinancialSourcesRow

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/scroll_reveal.dart';
import 'donations/donations_screen.dart';
import 'dasterkhwaan/kitchen.dart';
import 'assets.dart';
import 'inventory_doc.dart';
import 'branches.dart';

class BranchManagerScreen extends StatefulWidget {
  final String branchId;
  final String userId;

  const BranchManagerScreen({
    super.key, required this.branchId, required this.userId,
  });

  @override State<BranchManagerScreen> createState() => _BranchManagerScreenState();
}

class _BranchManagerScreenState extends State<BranchManagerScreen> {
  String _userName    = 'Loading...';
  String _branchName  = 'Branch';
  int    _selectedIndex = 0;
  bool   _isLoading   = true;

  static const _role = RoleTheme.supervisor;

  Future<void> _fetchInitialData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId)
          .collection('users').doc(widget.userId).get();

      final branchDoc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).get();

      if (mounted) {
        final name  = userDoc.data()?['username']?.toString().trim();
        final bName = branchDoc.data()?['name']?.toString().trim();
        setState(() {
          _userName   = name?.isNotEmpty  == true ? name!  : 'Manager';
          _branchName = bName?.isNotEmpty == true ? bName! : 'Branch';
          _isLoading  = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  void initState() { super.initState(); _fetchInitialData(); }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return RoleThemeScope(
      role: _role,
      child: _BranchManagerShell(
        branchId: widget.branchId,
        userId: widget.userId,
        userName: _userName,
        branchName: _branchName,
        selectedIndex: _selectedIndex,
        onIndexChanged: (i) => setState(() => _selectedIndex = i),
        onLogout: _logout,
      ),
    );
  }
}

class _BranchManagerShell extends StatelessWidget {
  final String branchId, userId, userName, branchName;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onLogout;

  const _BranchManagerShell({
    required this.branchId, required this.userId,
    required this.userName, required this.branchName,
    required this.selectedIndex, required this.onIndexChanged,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final t       = RoleThemeScope.dataOf(context);
    final isMobile = MediaQuery.of(context).size.width < 800;

    final pages = [
      _buildHomePage(context, t, isMobile),
      Branches(branchId: branchId, showRegisterButton: false),
      InventoryDocPage(branchId: branchId),
      DasterkhwaanKitchen(branchId: branchId, username: userName),
      DonationsScreen.embedded(
        branchId: branchId, username: userName,
        branchName: branchName, userId: userId, role: UserRole.manager,
      ),
      AssetsPage(branchId: branchId, isAdmin: false),
    ];

    return Scaffold(
      backgroundColor: t.bg,
      appBar: isMobile ? AppBar(
        backgroundColor: t.accent,
        title: Row(children: [
          Image.asset('assets/logo/gmwf.png', height: 32, width: 32),
          const SizedBox(width: 10),
          Flexible(child: Text('Manager ($userName)',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: onLogout),
          const SizedBox(width: 8),
        ],
      ) : null,
      body: Row(children: [
        if (!isMobile) _buildSidebar(context, t),
        Expanded(
          child: Column(
            children: [
              if (selectedIndex == 0) GlobalFilterBar(controller: dashboardController, branches: [{'id': branchId, 'name': branchName}]),
              Expanded(child: pages[selectedIndex]),
            ],
          ),
        ),
      ]),
      bottomNavigationBar: isMobile ? BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onIndexChanged,
        selectedItemColor: t.accent,
        unselectedItemColor: t.textTertiary,
        backgroundColor: t.bgCard,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Summary'),
          BottomNavigationBarItem(icon: Icon(Icons.medication_rounded), label: 'Med Stock'),
          BottomNavigationBarItem(icon: Icon(Icons.restaurant_outlined), label: 'Kitchen'),
          BottomNavigationBarItem(icon: Icon(Icons.volunteer_activism_rounded), label: 'Donations'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Assets'),
        ],
      ) : null,
    );
  }

  Widget _buildHomePage(BuildContext context, RoleThemeData t, bool isMobile) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(DS.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hero(),
          const SizedBox(height: DS.s3),

          DashSectionHeader(title: 'Operational Tools', subtitle: 'Quick access to branch modules'),
          _buildActionGrid(context, t, isMobile),
          const SizedBox(height: DS.s4),

          DashSectionHeader(title: 'Performance Overview', subtitle: 'Live metrics for $branchName'),
          _buildKPIOverview(t),
          const SizedBox(height: DS.s4),
        ]),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(DS.s3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF334155)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(DS.r3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Operational Lead,", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 4),
                Text(userName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(branchName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(DS.s2),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(DS.r2)),
            child: const Icon(Icons.location_city_rounded, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildKPIOverview(RoleThemeData t) {
    return FutureBuilder<BranchStats>(
      future: fetchBranchStats(branchId),
      builder: (context, snap) {
        final s = snap.data ?? const BranchStats();
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ActionableKPICard(
                    label: 'Branch Patients',
                    value: fmtNum(s.tokens),
                    icon: Icons.people_alt_rounded,
                    color: DS.blue,
                    isPrimary: true,
                    insight: 'Serving today',
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
                    isPrimary: true,
                    insight: 'Local contribution',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DS.s2),
            Row(
              children: [
                Expanded(child: ActionableKPICard(label: 'Food Issued', value: fmtNum(s.dasterkhwaan), icon: Icons.restaurant_rounded, color: DS.orange, insight: '${s.dasterkhwaanServed} served')),
                const SizedBox(width: DS.s2),
                Expanded(child: ActionableKPICard(label: 'Total Revenue', value: fmtNum(s.totalRevenue), prefix: 'PKR ', icon: Icons.payments_rounded, color: DS.green, insight: 'Today\'s total')),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionGrid(BuildContext context, RoleThemeData t, bool isMobile) {
    final actions = [
      _ActionItem(Icons.dashboard_rounded,           'Summary',     DS.blue,        () => onIndexChanged(1)),
      _ActionItem(Icons.medication_rounded,           'Med Stock',   DS.green,       () => onIndexChanged(2)),
      _ActionItem(Icons.restaurant_outlined,          'Kitchen',     DS.orange,      () => onIndexChanged(3)),
      _ActionItem(Icons.volunteer_activism_rounded,   'Donations',   DS.purple,      () => onIndexChanged(4)),
      _ActionItem(Icons.account_balance_wallet_rounded, 'Assets',   const Color(0xFFB45309), () => onIndexChanged(5)),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : 5,
      crossAxisSpacing: DS.s2,
      mainAxisSpacing: DS.s2,
      childAspectRatio: isMobile ? 1.4 : 1.2,
      children: actions.map((a) => _actionCard(a, t)).toList(),
    );
  }

  Widget _actionCard(_ActionItem item, RoleThemeData t) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(DS.r2),
      elevation: 0,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(DS.r2),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DS.r2),
            border: Border.all(color: item.color.withOpacity(0.25)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(DS.s1 + 4),
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(DS.r1 + 4),
              ),
              child: Icon(item.icon, size: 26, color: item.color),
            ),
            const SizedBox(height: DS.s1),
            Text(item.label, style: TextStyle(color: item.color, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, RoleThemeData t) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: t.bgCard,
        border: Border(right: BorderSide(color: t.bgRule)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Image.asset('assets/logo/gmwf.png', height: 52, width: 52),
            const SizedBox(height: DS.s1),
            Text('Branch Manager', style: TextStyle(
                color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('($userName)', style: TextStyle(color: t.textTertiary, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: DS.s1, vertical: 3),
              decoration: BoxDecoration(
                  color: t.accentMuted, borderRadius: BorderRadius.circular(DS.r2)),
              child: Text(branchName, style: TextStyle(
                  color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        Divider(height: 1, color: t.bgRule),
        const SizedBox(height: DS.s1),
        _sidebarItem(Icons.home_rounded,                  'Home',         0, t.accent,    t),
        _sidebarItem(Icons.dashboard_rounded,             'Summary',      1, DS.blue,      t),
        _sidebarItem(Icons.medication_rounded,            'Med Inventory', 2, DS.green,    t),
        _sidebarItem(Icons.restaurant_outlined,           'Kitchen Ops',  3, DS.orange,    t),
        _sidebarItem(Icons.volunteer_activism_rounded,    'Donations',    4, DS.purple,    t),
        _sidebarItem(Icons.account_balance_wallet_rounded,'Assets',       5, const Color(0xFFB45309), t),
        const Spacer(),
        Divider(height: 1, color: t.bgRule),
        ListTile(
          leading: Icon(Icons.logout_rounded, color: t.danger),
          title: Text('Logout', style: TextStyle(color: t.danger, fontWeight: FontWeight.w600)),
          onTap: onLogout,
        ),
        const SizedBox(height: DS.s2),
      ]),
    );
  }

  Widget _sidebarItem(IconData icon, String label, int index, Color color, RoleThemeData t) {
    final selected = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? color.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          leading: Icon(icon, color: selected ? color : t.textTertiary, size: 20),
          title: Text(label, style: TextStyle(
              color: selected ? color : t.textSecondary,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500, fontSize: 13.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          trailing: selected ? Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))) : null,
          minLeadingWidth: 20,
          visualDensity: VisualDensity.compact,
          onTap: () => onIndexChanged(index),
        ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionItem(this.icon, this.label, this.color, this.onTap);
}
