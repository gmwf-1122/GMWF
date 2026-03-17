// lib/pages/supervisor.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import 'assets.dart';
import 'request.dart';
import 'inventory_doc.dart';
import 'branches.dart';

class SupervisorScreen extends StatefulWidget {
  final String branchId;
  final String supervisorId;

  const SupervisorScreen({
    super.key,
    required this.branchId,
    required this.supervisorId,
  });

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  String _supervisorName = 'Loading...';
  int _selectedIndex = 0;

  // Supervisor always uses the supervisor theme
  static const _role = RoleTheme.supervisor;

  Future<void> _fetchSupervisorName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(widget.supervisorId)
          .get();

      if (mounted) {
        final name = doc.data()?['username']?.toString().trim();
        setState(() {
          _supervisorName = name?.isNotEmpty == true ? name! : 'Supervisor';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _supervisorName = 'Supervisor');
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  void initState() {
    super.initState();
    _fetchSupervisorName();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap the entire supervisor shell in RoleThemeScope so that every
    // descendant (including Branches, InventoryDocPage, AssetsPage, etc.)
    // automatically inherits the supervisor teal/green palette via
    // RoleThemeScope.dataOf(context).
    return RoleThemeScope(
      role: _role,
      child: _SupervisorShell(
        branchId: widget.branchId,
        supervisorId: widget.supervisorId,
        supervisorName: _supervisorName,
        selectedIndex: _selectedIndex,
        onIndexChanged: (i) => setState(() => _selectedIndex = i),
        onLogout: _logout,
      ),
    );
  }
}

// ── Inner shell — reads theme from RoleThemeScope ─────────────────────────────

class _SupervisorShell extends StatelessWidget {
  final String branchId;
  final String supervisorId;
  final String supervisorName;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onLogout;

  const _SupervisorShell({
    required this.branchId,
    required this.supervisorId,
    required this.supervisorName,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final t        = RoleThemeScope.dataOf(context);
    final isMobile = MediaQuery.of(context).size.width < 800;

    // Branches is used for the Summary tab — it reads RoleThemeScope so it
    // will automatically render in supervisor teal/green colours.
    final pages = [
      _buildHomePage(context, t, isMobile),
      Branches(branchId: branchId, showRegisterButton: false),
      InventoryDocPage(branchId: branchId),
      RequestPage(branchId: branchId),
      AssetsPage(branchId: branchId, isAdmin: false),
    ];

    return Scaffold(
      backgroundColor: t.bg,
      appBar: isMobile
          ? AppBar(
              backgroundColor: t.accent,
              leading: null,
              title: Row(children: [
                Image.asset("assets/logo/gmwf.png", height: 36, width: 36),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    "Supervisor ($supervisorName)",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ]),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: onLogout,
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: Row(children: [
        if (!isMobile) _buildSidebar(context, t),
        Expanded(child: pages[selectedIndex]),
      ]),
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: onIndexChanged,
              selectedItemColor: t.accent,
              unselectedItemColor: t.textTertiary,
              backgroundColor: t.bgCard,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Summary'),
                BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded), label: 'Inventory'),
                BottomNavigationBarItem(icon: Icon(Icons.request_page_rounded), label: 'Requests'),
                BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Assets'),
              ],
            )
          : null,
    );
  }

  // ── Home page ──────────────────────────────────────────────────────────────

  Widget _buildHomePage(BuildContext context, RoleThemeData t, bool isMobile) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          top: isMobile ? 16.0 : 0.0,
          left: 24.0,
          right: 24.0,
          bottom: 24.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMobile) const SizedBox(height: 24),
            // ── Hero banner ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isMobile ? 32.0 : 48.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.accent, t.accentLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: t.accent.withOpacity(0.25),
                    spreadRadius: 4,
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: Image.asset("assets/logo/gmwf.png", height: 80, width: 80)),
                        const SizedBox(height: 16),
                        Text(
                          "Welcome, $supervisorName!",
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Manage your branch efficiently with summary, inventory, requests, and assets.",
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    )
                  : Row(children: [
                      Image.asset("assets/logo/gmwf.png", height: 100, width: 100),
                      const SizedBox(width: 24),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          "Welcome, $supervisorName!",
                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Manage your branch efficiently with summary, inventory, requests, and assets.",
                          style: TextStyle(fontSize: 20, color: Colors.white70),
                        ),
                      ]),
                    ]),
            ),
            const SizedBox(height: 48),
            Text("Quick Actions",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: t.textPrimary)),
            const SizedBox(height: 24),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isMobile ? 1.3 : 1.5,
              children: [
                _bigButton(context, t,
                    icon: Icons.dashboard_rounded,
                    label: "Summary",
                    color: t.accent,
                    onTap: () => onIndexChanged(1)),
                _bigButton(context, t,
                    icon: Icons.inventory_2_rounded,
                    label: "Inventory",
                    color: t.zakat,
                    onTap: () => onIndexChanged(2)),
                _bigButton(context, t,
                    icon: Icons.request_page_rounded,
                    label: "Requests",
                    color: t.gmwf,
                    onTap: () => onIndexChanged(3)),
                _bigButton(context, t,
                    icon: Icons.account_balance_wallet_rounded,
                    label: "Assets",
                    color: t.nonZakat,
                    onTap: () => onIndexChanged(4)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigButton(
    BuildContext context,
    RoleThemeData t, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return Card(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.8), color],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: isMobile ? 40 : 48, color: Colors.white),
                SizedBox(height: isMobile ? 8 : 16),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: isMobile ? 18 : 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────────────

  Widget _buildSidebar(BuildContext context, RoleThemeData t) {
    return Container(
      width: 260,
      color: t.bgCard,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset("assets/logo/gmwf.png", height: 60, width: 60),
              const SizedBox(height: 8),
              Text('Supervisor Dashboard',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  )),
              const SizedBox(height: 4),
              Text('($supervisorName)',
                  style: TextStyle(color: t.textTertiary, fontSize: 14)),
            ],
          ),
        ),
        Divider(height: 1, color: t.bgRule),
        _sidebarItem(context, t, icon: Icons.home,                       label: 'Home',      index: 0, color: t.accent),
        _sidebarItem(context, t, icon: Icons.dashboard_rounded,           label: 'Summary',   index: 1, color: t.accent),
        _sidebarItem(context, t, icon: Icons.inventory_2_rounded,         label: 'Inventory', index: 2, color: t.zakat),
        _sidebarItem(context, t, icon: Icons.request_page_rounded,        label: 'Requests',  index: 3, color: t.gmwf),
        _sidebarItem(context, t, icon: Icons.account_balance_wallet_rounded, label: 'Assets', index: 4, color: t.nonZakat),
        const Spacer(),
        ListTile(
          leading: Icon(Icons.logout, color: t.danger),
          title: Text("Logout", style: TextStyle(color: t.danger)),
          onTap: onLogout,
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _sidebarItem(
    BuildContext context,
    RoleThemeData t, {
    required IconData icon,
    required String label,
    required int index,
    required Color color,
  }) {
    final selected = selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: selected ? color : t.textTertiary),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? color : t.textSecondary,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedTileColor: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => onIndexChanged(index),
    );
  }
}