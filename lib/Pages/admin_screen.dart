// lib/pages/admin_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'branches.dart';
import 'register.dart';
import 'download_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = -1; // -1 means dashboard
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final List<Map<String, dynamic>> _menuItems = [
    {
      'title': 'Branches',
      'icon': Icons.store,
      'color': Colors.green.shade700,
      'gradient': [Colors.green.shade400, Colors.green.shade700],
      'page': const Branches(),
    },
    {
      'title': 'Register User',
      'icon': Icons.person_add,
      'color': Colors.blue.shade700,
      'gradient': [Colors.blue.shade400, Colors.blue.shade700],
      'page': const Register(),
      'transparent': true, // Special flag
    },
    {
      'title': 'Download',
      'icon': Icons.download,
      'color': Colors.orange.shade700,
      'gradient': [Colors.orange.shade400, Colors.orange.shade700],
      'page': const DownloadScreen(),
    },
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _animationController.forward(from: 0.0);
  }

  void _goBackToDashboard() {
    setState(() {
      _selectedIndex = -1;
    });
    _animationController.reverse();
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade800,
        leading: _selectedIndex != -1 && isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : null,
        title: Row(
          children: [
            Image.asset("assets/logo/gmwf.png",
                height: 36, width: 36), // Bigger logo
            const SizedBox(width: 10),
            const Text(
              "Admin Dashboard",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          if (_selectedIndex != -1 && !isMobile)
            TextButton.icon(
              onPressed: _goBackToDashboard,
              icon: const Icon(Icons.home, color: Colors.white),
              label: const Text("Home", style: TextStyle(color: Colors.white)),
            ),
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isMobile && _selectedIndex != -1 ? _buildMobileDrawer() : null,
      body: Row(
        children: [
          // Sidebar (only on desktop when a page is selected)
          if (_selectedIndex != -1 && !isMobile) _buildSidebar(),

          // Main Content
          Expanded(
            child:
                _selectedIndex == -1 ? _buildDashboard() : _buildPageContent(),
          ),
        ],
      ),
    );
  }

  // Dashboard with beautiful buttons
  Widget _buildDashboard() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/images/1.jpg"),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Welcome back!",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Select a module to manage.",
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.of(context).size.width > 1000 ? 3 : 2,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _menuItems.length,
                  itemBuilder: (context, index) {
                    final item = _menuItems[index];
                    return _buildDashboardCard(
                      title: item['title'],
                      icon: item['icon'],
                      gradient: item['gradient'],
                      onTap: () => _selectPage(index),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Sidebar
  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: Colors.grey.shade900,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
            decoration: BoxDecoration(
              color: _menuItems[_selectedIndex]['color'],
            ),
            child: Row(
              children: [
                Icon(_menuItems[_selectedIndex]['icon'],
                    color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Text(
                  _menuItems[_selectedIndex]['title'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.home, color: Colors.white70),
            title: const Text("Dashboard Home",
                style: TextStyle(color: Colors.white70)),
            onTap: _goBackToDashboard,
          ),
          const Divider(height: 1),
          ..._menuItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = _selectedIndex == index;
            return ListTile(
              leading: Icon(item['icon'],
                  color: isSelected ? Colors.white : Colors.white70),
              title: Text(
                item['title'],
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedTileColor: Colors.white.withOpacity(0.1),
              onTap: () => _selectPage(index),
            );
          }).toList(),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title:
                const Text("Logout", style: TextStyle(color: Colors.redAccent)),
            onTap: _logout,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Mobile Drawer
  Drawer _buildMobileDrawer() {
    return Drawer(
      child: _buildSidebar(),
    );
  }

  // Page Content with Animation
  Widget _buildPageContent() {
    final bool isTransparent =
        _menuItems[_selectedIndex].containsKey('transparent') &&
            _menuItems[_selectedIndex]['transparent'] == true;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: isTransparent
                ? _menuItems[_selectedIndex]['page'] // Transparent background
                : Container(
                    color: Colors.white,
                    child: _menuItems[_selectedIndex]['page'],
                  ),
          ),
        );
      },
    );
  }
}
