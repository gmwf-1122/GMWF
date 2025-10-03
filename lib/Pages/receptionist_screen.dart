// lib/pages/receptionist_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'patient_register.dart';
import 'token_screen.dart';

class ReceptionistScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;

  const ReceptionistScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
  });

  @override
  State<ReceptionistScreen> createState() => _ReceptionistScreenState();
}

class _ReceptionistScreenState extends State<ReceptionistScreen> {
  int _selectedIndex = 0;

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pages for sidebar navigation
    final List<Widget> _pages = [
      PatientRegisterPage(
        branchId: widget.branchId,
        receptionistId: widget.receptionistId,
      ),
      TokenScreen(
        branchId: widget.branchId,
        receptionistId: widget.receptionistId,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Row(
          children: [
            Image.asset("assets/logo/gmwf.png", height: 40, width: 40),
            const SizedBox(width: 10),
            const Text(
              "Receptionist Dashboard",
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                "Logout",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: TextButton.styleFrom(backgroundColor: Colors.red),
            ),
          ),
        ],
      ),

      // Sidebar Drawer
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.green),
              child: Row(
                children: [
                  Image.asset("assets/logo/gmwf.png", height: 50, width: 50),
                  const SizedBox(width: 12),
                  const Text(
                    "Receptionist",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.green),
              title: const Text("Register Patient"),
              selected: _selectedIndex == 0,
              onTap: () {
                setState(() => _selectedIndex = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.green),
              title: const Text("Token Screen"),
              selected: _selectedIndex == 1,
              onTap: () {
                setState(() => _selectedIndex = 1);
                Navigator.pop(context);
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout"),
              onTap: _logout,
            ),
          ],
        ),
      ),

      // Body shows the selected page
      body: _pages[_selectedIndex],
    );
  }
}
