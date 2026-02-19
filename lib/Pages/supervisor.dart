// lib/pages/supervisor.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    final isMobile = MediaQuery.of(context).size.width < 800;
    final pages = [
      _buildHomePage(),
      Branches(branchId: widget.branchId),
      InventoryDocPage(branchId: widget.branchId),
      RequestPage(branchId: widget.branchId),
      AssetsPage(branchId: widget.branchId, isAdmin: false),
    ];

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: const Color(0xFF006D5B),
              leading: null,
              title: Row(
                children: [
                  Image.asset("assets/logo/gmwf.png", height: 36, width: 36),
                  const SizedBox(width: 10),
                  Text(
                    "Supervisor ($_supervisorName)",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: _logout,
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(),
          Expanded(
            child: pages[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
              selectedItemColor: Colors.teal,
              unselectedItemColor: Colors.grey,
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

  Widget _buildHomePage() {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(top: isMobile ? 16.0 : 0.0, left: 24.0, right: 24.0, bottom: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMobile) const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isMobile ? 32.0 : 48.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF006D5B), Color(0xFF009875)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    spreadRadius: 4,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Image.asset("assets/logo/gmwf.png", height: 80, width: 80),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Welcome, $_supervisorName!",
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Manage your branch efficiently with summary, inventory, requests, and assets.",
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Image.asset("assets/logo/gmwf.png", height: 100, width: 100),
                        const SizedBox(width: 24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Welcome, $_supervisorName!",
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "Manage your branch efficiently with summary, inventory, requests, and assets.",
                              style: TextStyle(fontSize: 20, color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 48),
            const Text(
              "Quick Actions",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isMobile ? 1.3 : 1.5,
              children: [
                _bigButton(
                  icon: Icons.dashboard_rounded,
                  label: "Summary",
                  color: Colors.blue.shade700,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                _bigButton(
                  icon: Icons.inventory_2_rounded,
                  label: "Inventory",
                  color: Colors.green.shade700,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
                _bigButton(
                  icon: Icons.request_page_rounded,
                  label: "Requests",
                  color: Colors.orange.shade700,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
                _bigButton(
                  icon: Icons.account_balance_wallet_rounded,
                  label: "Assets",
                  color: Colors.purple.shade700,
                  onTap: () => setState(() => _selectedIndex = 4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigButton({
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
                  style: TextStyle(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: Colors.white),
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

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset("assets/logo/gmwf.png", height: 60, width: 60),
                const SizedBox(height: 8),
                const Text(
                  'Supervisor Dashboard',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '($_supervisorName)',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
          ListTile(
            leading: Icon(Icons.home, color: _selectedIndex == 0 ? Colors.teal : Colors.black54),
            title: Text(
              'Home',
              style: TextStyle(
                color: _selectedIndex == 0 ? Colors.teal : Colors.black54,
                fontWeight: _selectedIndex == 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: _selectedIndex == 0,
            selectedTileColor: Colors.grey[100],
            onTap: () => setState(() => _selectedIndex = 0),
          ),
          ListTile(
            leading: Icon(Icons.dashboard_rounded, color: _selectedIndex == 1 ? Colors.blue : Colors.black54),
            title: Text(
              'Summary',
              style: TextStyle(
                color: _selectedIndex == 1 ? Colors.blue : Colors.black54,
                fontWeight: _selectedIndex == 1 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: _selectedIndex == 1,
            selectedTileColor: Colors.grey[100],
            onTap: () => setState(() => _selectedIndex = 1),
          ),
          ListTile(
            leading: Icon(Icons.inventory_2_rounded, color: _selectedIndex == 2 ? Colors.green : Colors.black54),
            title: Text(
              'Inventory',
              style: TextStyle(
                color: _selectedIndex == 2 ? Colors.green : Colors.black54,
                fontWeight: _selectedIndex == 2 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: _selectedIndex == 2,
            selectedTileColor: Colors.grey[100],
            onTap: () => setState(() => _selectedIndex = 2),
          ),
          ListTile(
            leading: Icon(Icons.request_page_rounded, color: _selectedIndex == 3 ? Colors.orange : Colors.black54),
            title: Text(
              'Requests',
              style: TextStyle(
                color: _selectedIndex == 3 ? Colors.orange : Colors.black54,
                fontWeight: _selectedIndex == 3 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: _selectedIndex == 3,
            selectedTileColor: Colors.grey[100],
            onTap: () => setState(() => _selectedIndex = 3),
          ),
          ListTile(
            leading: Icon(Icons.account_balance_wallet_rounded, color: _selectedIndex == 4 ? Colors.purple : Colors.black54),
            title: Text(
              'Assets',
              style: TextStyle(
                color: _selectedIndex == 4 ? Colors.purple : Colors.black54,
                fontWeight: _selectedIndex == 4 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: _selectedIndex == 4,
            selectedTileColor: Colors.grey[100],
            onTap: () => setState(() => _selectedIndex = 4),
          ),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
            onTap: _logout,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}