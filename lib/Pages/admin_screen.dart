// lib/pages/admin_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'branches.dart';
import 'register.dart';
import 'download_screen.dart';
import 'users.dart';
import 'fix_patients.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminScreen extends StatefulWidget {
  final String branchId;

  const AdminScreen({super.key, required this.branchId});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = -1;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  late final List<Map<String, dynamic>> _dashboardItems;
  late final List<Map<String, dynamic>> _sidebarItems;

  @override
  void initState() {
    super.initState();

    _dashboardItems = [
      {
        'title': 'Branches',
        'icon': Icons.store,
        'color': const Color(0xFF006D5B),
        'page': const Branches(),
        'size': 'large',
      },
      {
        'title': 'Register User',
        'icon': Icons.person_add,
        'color': const Color(0xFF009875),
        'page': const Register(),
        'transparent': true,
        'size': 'large',
      },
      {
        'title': 'Patients',
        'icon': Icons.local_hospital,
        'color': const Color(0xFFFFA000),
        'page': const UsersScreen(isPatientMode: true),
        'size': 'large',
      },
      {
        'title': 'Users',
        'icon': Icons.group,
        'color': const Color(0xFF2196F3),
        'page': const UsersScreen(),
        'size': 'large',
      },
      {
        'title': 'Download',
        'icon': Icons.download,
        'color': const Color(0xFFF57C00),
        'page': const DownloadScreen(),
        'size': 'large',
      },
      {
        'title': 'Fix Patients Data',
        'icon': Icons.healing,
        'color': const Color(0xFFE91E63),
        'page': FixPatientsScreen(branchId: widget.branchId),
        'size': 'large',
      },
    ];

    _sidebarItems = [
      {
        'title': 'Home',
        'icon': Icons.home,
        'color': const Color(0xFF607D8B),
        'page': null,
      },
      {
        'title': 'Branches',
        'icon': Icons.store,
        'color': const Color(0xFF006D5B),
        'page': const Branches(),
      },
      {
        'title': 'Register User',
        'icon': Icons.person_add,
        'color': const Color(0xFF009875),
        'page': const Register(),
        'transparent': true,
      },
      {
        'title': 'Patients',
        'icon': Icons.local_hospital,
        'color': const Color(0xFFFFA000),
        'page': const UsersScreen(isPatientMode: true),
      },
      {
        'title': 'Users',
        'icon': Icons.group,
        'color': const Color(0xFF2196F3),
        'page': const UsersScreen(),
      },
      {
        'title': 'Download',
        'icon': Icons.download,
        'color': const Color(0xFFF57C00),
        'page': const DownloadScreen(),
      },
      {
        'title': 'Fix Patients Data',
        'icon': Icons.healing,
        'color': const Color(0xFFE91E63),
        'page': FixPatientsScreen(branchId: widget.branchId),
      },
    ];

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
      appBar: isMobile
          ? AppBar(
              backgroundColor: const Color(0xFF006D5B),
              leading: IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
              title: Row(
                children: [
                  Image.asset("assets/logo/gmwf.png", height: 36, width: 36),
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
                if (_selectedIndex != -1)
                  IconButton(
                    icon: const Icon(Icons.home, color: Colors.white),
                    onPressed: _goBackToDashboard,
                  ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: _logout,
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      drawer: isMobile ? _buildMobileDrawer() : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(),
          Expanded(
            child: _selectedIndex == -1 ? _buildDashboard() : _buildPageContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      color: Colors.grey[50],
      child: SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Section
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isMobile ? 24.0 : 48.0),
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
                  child: Row(
                    children: [
                      Image.asset("assets/logo/gmwf.png", height: isMobile ? 60 : 100, width: isMobile ? 60 : 100),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Welcome to Admin Dashboard!",
                              style: TextStyle(
                                fontSize: isMobile ? 24 : 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Efficiently manage branches, users, patients, and data downloads.",
                              style: TextStyle(fontSize: isMobile ? 14 : 20, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                const Text(
                  "Quick Access",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossCount = width < 600 ? 1 : width < 900 ? 2 : 3;
                    final aspectRatio = crossCount == 1 ? 2.5 : 1.5;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: aspectRatio,
                      ),
                      itemCount: _dashboardItems.length,
                      itemBuilder: (context, index) {
                        final item = _dashboardItems[index];
                        return _buildQuickAccessCard(
                          title: item['title'],
                          icon: item['icon'],
                          color: item['color'],
                          onTap: () => _selectPage(index),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 48),
                const Text(
                  "Branch Summaries",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('branches').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final branches = snapshot.data!.docs
                        .map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return {
                            'id': doc.id,
                            'name': data['name'] as String? ?? doc.id,
                          };
                        })
                        .toList()
                      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: branches.length,
                      itemBuilder: (context, index) {
                        final branchMap = branches[index];
                        final branchName = branchMap['name'] as String;
                        final branchId = branchMap['id'] as String;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: FutureBuilder<Map<String, int>>(
                            future: _fetchBranchSummary(branchId, 'today'),
                            builder: (context, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return Container(
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Center(child: CircularProgressIndicator()),
                                );
                              }
                              if (snap.hasError || !snap.hasData) {
                                return Container(
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(child: Text('Error or No data')),
                                );
                              }
                              final d = snap.data!;
                              final totalPatients = d['totalPatients'] ?? 0;
                              final completed = d['completed'] ?? 0;
                              final progress = totalPatients > 0 ? completed / totalPatients : 0.0;
                              Color progressColor = Colors.green;
                              if (progress < 0.5) progressColor = Colors.red;
                              else if (progress < 0.8) progressColor = Colors.orange;

                              return Card(
                                elevation: 0,
                                color: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                shadowColor: Colors.black.withOpacity(0.05),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          branchName,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            LinearProgressIndicator(
                                              value: progress,
                                              backgroundColor: Colors.grey[200],
                                              color: progressColor,
                                              minHeight: 6,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${(progress * 100).round()}%',
                                              style: TextStyle(fontSize: 18, color: progressColor, fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              '$completed / $totalPatients Patients Processed',
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAccessCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.8), color],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 20 : 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF006D5B), Color(0xFF009875)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            child: Row(
              children: [
                Image.asset("assets/logo/gmwf.png", height: 40, width: 40),
                const SizedBox(width: 12),
                const Text(
                  'Admin Panel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white70),
          Expanded(
            child: ListView(
              children: <Widget>[
                ..._sidebarItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isSelected = (index == 0 && _selectedIndex == -1) || (index > 0 && _selectedIndex == index - 1);
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
                    onTap: () {
                      if (index == 0) {
                        _goBackToDashboard();
                      } else {
                        _selectPage(index - 1);
                      }
                      if (MediaQuery.of(context).size.width < 800) {
                        Navigator.pop(context);
                      }
                    },
                  );
                }).toList(),
                const Divider(height: 1, color: Colors.white70),
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.redAccent),
                  title: Text('Logout', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    if (MediaQuery.of(context).size.width < 800) {
                      Navigator.pop(context);
                    }
                    _logout();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Drawer _buildMobileDrawer() {
    return Drawer(
      child: _buildSidebar(),
    );
  }

  Widget _buildPageContent() {
    if (_selectedIndex == -1) {
      return const SizedBox.shrink();
    }
    final selectedItem = _sidebarItems[_selectedIndex + 1];
    final page = selectedItem['page'];
    final bool isTransparent = selectedItem.containsKey('transparent') &&
        selectedItem['transparent'] == true;
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: isTransparent
                ? page
                : Container(
                    color: Colors.white,
                    child: page,
                  ),
          ),
        );
      },
    );
  }

  Future<Map<String, int>> _fetchBranchSummary(
    String branchId,
    String period,
  ) async {
    try {
      final df = DateFormat('ddMMyy');
      final start = _startForPeriod(period);
      final end = _endForPeriod(period);
      int totalPatients = 0;
      int completed = 0;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        final ds = df.format(d);
        final base = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(ds);
        final countFutures = ['zakat', 'non-zakat', 'gmwf'].map((coll) => base.collection(coll).count().get());
        final countSnaps = await Future.wait(countFutures);
        for (final countSnap in countSnaps) {
          totalPatients += countSnap.count ?? 0;
        }
        final collRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('dispensary')
            .doc(ds)
            .collection(ds);
        final dispCountSnap = await collRef.count().get();
        completed += dispCountSnap.count ?? 0;
      }
      return {
        'totalPatients': totalPatients,
        'completed': completed,
      };
    } catch (e) {
      return {
        'totalPatients': 0,
        'completed': 0,
      };
    }
  }

  DateTime _startForPeriod(String p) {
    final now = DateTime.now();
    if (p == 'today') {
      return DateTime(now.year, now.month, now.day);
    } else if (p == 'week') {
      return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    } else {
      return DateTime(now.year, now.month, 1);
    }
  }

  DateTime _endForPeriod(String p) => DateTime.now();
}