import 'package:flutter/material.dart';
import 'branches.dart';
import 'register.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const Branches(), // ✅ Branches screen
    const Register(), // ✅ Register User screen
    Center(
      // ✅ Download screen placeholder
      child: Text(
        "Download Section",
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ✅ Sidebar
          Container(
            width: 220,
            color: Colors.green.shade800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                // ✅ GMWF Logo
                Center(
                  child: Image.asset(
                    "assets/logo/gmwf.png",
                    height: 150,
                  ),
                ),

                const SizedBox(height: 10),

                // ✅ Title under logo
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "Admin Dashboard",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(color: Colors.white54),

                // ✅ Navigation buttons
                _buildNavItem(Icons.store, "Branches", 0),
                _buildNavItem(Icons.person_add, "Register User", 1),
                _buildNavItem(Icons.download, "Download", 2),

                const Spacer(),
                _buildNavItem(Icons.logout, "Logout", -1, isLogout: true),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ✅ Main content area
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title, int index,
      {bool isLogout = false}) {
    bool isSelected = _selectedIndex == index;

    return InkWell(
      onTap: () {
        if (isLogout) {
          // ✅ Navigate to login screen
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (Route<dynamic> route) => false,
          );
        } else {
          setState(() {
            _selectedIndex = index;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: isSelected ? Colors.green.shade600 : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
