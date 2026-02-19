import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'branches.dart';
import 'register.dart';
import 'download_screen.dart';
import 'users.dart';

class ChairmanScreen extends StatefulWidget {
  const ChairmanScreen({super.key});

  @override
  State<ChairmanScreen> createState() => _ChairmanScreenState();
}

class _ChairmanScreenState extends State<ChairmanScreen> {
  bool _isDarkMode = false;
  String username = 'Chairman';
  bool _isLoading = true;
  String _selectedMenu = 'overview';

  @override
  void initState() {
    super.initState();
    _fetchUsername();
  }

  Future<void> _fetchUsername() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final branchesSnap = await FirebaseFirestore.instance.collection('branches').get();

    for (final branchDoc in branchesSnap.docs) {
      final userSnap = await FirebaseFirestore.instance
          .collection('branches/${branchDoc.id}/users')
          .doc(uid)
          .get();

      if (userSnap.exists) {
        final data = userSnap.data();
        if (data != null && data['username'] != null) {
          setState(() {
            username = data['username'] as String;
            _isLoading = false;
          });
          return;
        }
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  Widget _buildQuickAccessButton({
    required String title,
    required IconData icon,
    required Color color,
    required String menuKey,
  }) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedMenu = menuKey;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        elevation: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final Color backgroundColor = _isDarkMode ? const Color(0xFF121212) : const Color(0xFFE1F5FE);
    final Color appBarColor = _isDarkMode ? const Color(0xFF01579B) : const Color(0xFF4FC3F7);
    final Color textColor = _isDarkMode ? Colors.white : const Color(0xFF212121);
    final List<Color> heroGradient = _isDarkMode 
        ? [const Color(0xFF01579B), const Color(0xFF0277BD)] 
        : [const Color(0xFF4FC3F7), const Color(0xFF29B6F6)];
    final Color cardColor = _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final Color buttonColor = _isDarkMode ? const Color(0xFF0277BD) : const Color(0xFF4FC3F7);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        title: Row(
          children: [
            Image.asset("assets/logo/gmwf.png", height: 36, width: 36),
            const SizedBox(width: 10),
            Text(
              "Chairman Overview - $username",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isDarkMode ? Icons.brightness_7 : Icons.brightness_4, color: Colors.white),
            onPressed: _toggleDarkMode,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        backgroundColor: backgroundColor,
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: appBarColor,
              ),
              child: const Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.store, color: textColor),
              title: Text('Branches', style: TextStyle(color: textColor)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedMenu = 'branches';
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.person_add, color: textColor),
              title: Text('Register User', style: TextStyle(color: textColor)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedMenu = 'register';
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.local_hospital, color: textColor),
              title: Text('Patients', style: TextStyle(color: textColor)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedMenu = 'patients';
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.group, color: textColor),
              title: Text('Users', style: TextStyle(color: textColor)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedMenu = 'users';
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.download, color: textColor),
              title: Text('Download', style: TextStyle(color: textColor)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedMenu = 'download';
                });
              },
            ),
          ],
        ),
      ),
      body: _buildBody(textColor, heroGradient, buttonColor, cardColor, backgroundColor),
    );
  }

  Widget _buildBody(Color textColor, List<Color> heroGradient, Color buttonColor, Color cardColor, Color backgroundColor) {
    if (_selectedMenu == 'branches') {
      return const Branches();
    } else if (_selectedMenu == 'register') {
      return const Register();
    } else if (_selectedMenu == 'patients') {
      return const UsersScreen(isPatientMode: true);
    } else if (_selectedMenu == 'users') {
      return const UsersScreen();
    } else if (_selectedMenu == 'download') {
      return const DownloadScreen();
    } else {
      // overview
      return RefreshIndicator(
        onRefresh: () async {
          setState(() {}); // Trigger rebuild to refresh data
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero section
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: heroGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset("assets/logo/gmwf.png", height: 80, width: 80),
                      const SizedBox(height: 16),
                      Text(
                        "Welcome $username",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Monitor and manage branch performance efficiently",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Quick Actions",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Changed to Wrap for different visualization (grid-like on wider screens)
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildQuickAccessButton(
                          title: 'Branches',
                          icon: Icons.store,
                          color: buttonColor,
                          menuKey: 'branches',
                        ),
                        _buildQuickAccessButton(
                          title: 'Register User',
                          icon: Icons.person_add,
                          color: buttonColor,
                          menuKey: 'register',
                        ),
                        _buildQuickAccessButton(
                          title: 'Patients',
                          icon: Icons.local_hospital,
                          color: buttonColor,
                          menuKey: 'patients',
                        ),
                        _buildQuickAccessButton(
                          title: 'Users',
                          icon: Icons.group,
                          color: buttonColor,
                          menuKey: 'users',
                        ),
                        _buildQuickAccessButton(
                          title: 'Download',
                          icon: Icons.download,
                          color: buttonColor,
                          menuKey: 'download',
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      "Branch Performance Overview",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Different visualization: Bar chart for all branches' completion rates
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
                        if (branches.isEmpty) {
                          return Card(
                            color: cardColor,
                            child: const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No branches available'),
                            ),
                          );
                        }
                        return FutureBuilder<List<Map<String, dynamic>>>(
                          future: Future.wait(branches.map((branch) async {
                            final summary = await _fetchBranchSummary(branch['id'] as String, 'today');
                            return {
                              'name': branch['name'],
                              'tokens': summary['tokens'] ?? 0,
                              'prescribed': summary['prescribed'] ?? 0,
                              'dispensed': summary['dispensed'] ?? 0,
                            };
                          })),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const SizedBox(
                                height: 300,
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            if (snap.hasError) {
                              return SizedBox(
                                height: 300,
                                child: Center(child: Text('Error: ${snap.error}')),
                              );
                            }
                            if (!snap.hasData || snap.data!.isEmpty) {
                              return const SizedBox(
                                height: 300,
                                child: Center(child: Text('No data')),
                              );
                            }
                            final branchData = snap.data!;
                            int total_tokens = 0;
                            int total_prescribed = 0;
                            int total_dispensed = 0;
                            List<BarChartGroupData> barGroups = [];
                            double maxValue = 0;
                            for (int i = 0; i < branchData.length; i++) {
                              final data = branchData[i];
                              final tokens = data['tokens'] as int;
                              final prescribed = data['prescribed'] as int;
                              final dispensed = data['dispensed'] as int;
                              total_tokens += tokens;
                              total_prescribed += prescribed;
                              total_dispensed += dispensed;
                              maxValue = max(maxValue, tokens.toDouble());
                              maxValue = max(maxValue, prescribed.toDouble());
                              maxValue = max(maxValue, dispensed.toDouble());
                              barGroups.add(
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: tokens.toDouble(),
                                      color: const Color(0xFF66BB6A),
                                      width: 12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    BarChartRodData(
                                      toY: prescribed.toDouble(),
                                      color: const Color(0xFF4FC3F7),
                                      width: 12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    BarChartRodData(
                                      toY: dispensed.toDouble(),
                                      color: const Color(0xFFFFA726),
                                      width: 12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final double maxY = maxValue * 1.2;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Separate cards for overall progress
                                Text(
                                  'Overall Progress',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildProgressCard(
                                      title: 'Tokens',
                                      value: total_tokens,
                                      color: const Color(0xFF66BB6A),
                                      icon: Icons.confirmation_number,
                                    ),
                                    _buildProgressCard(
                                      title: 'Prescribed',
                                      value: total_prescribed,
                                      color: const Color(0xFF4FC3F7),
                                      icon: Icons.description,
                                    ),
                                    _buildProgressCard(
                                      title: 'Dispensed',
                                      value: total_dispensed,
                                      color: const Color(0xFFFFA726),
                                      icon: Icons.local_pharmacy,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Bar chart
                                SizedBox(
                                  height: 300,
                                  child: BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: maxY,
                                      barTouchData: BarTouchData(
                                        enabled: true,
                                        touchTooltipData: BarTouchTooltipData(
                                          getTooltipColor: (group) => Colors.transparent,
                                          tooltipPadding: const EdgeInsets.all(8),
                                          tooltipMargin: 8,
                                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                            String label = rodIndex == 0 ? 'Tokens' : (rodIndex == 1 ? 'Prescribed' : 'Dispensed');
                                            return BarTooltipItem(
                                              '$label: ${rod.toY.toInt()}',
                                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                            );
                                          },
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        show: true,
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 40,
                                            getTitlesWidget: (value, meta) {
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 8),
                                                child: Text(
                                                  branchData[value.toInt()]['name'].toString(),
                                                  style: TextStyle(fontSize: 12, color: textColor),
                                                  textAlign: TextAlign.center,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      barGroups: barGroups,
                                      gridData: const FlGridData(show: false),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildProgressCard({
    required String title,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
      int tokens = 0;
      int prescribed = 0;
      int dispensed = 0;
      final presRoot = FirebaseFirestore.instance.collection('branches').doc(branchId).collection('prescriptions');
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
          tokens += countSnap.count ?? 0;
        }

        // Prescriptions count (aligned with branches.dart logic)
        final getFutures = ['zakat', 'non-zakat', 'gmwf'].map((coll) => base.collection(coll).get());
        final snaps = await Future.wait(getFutures);

        Map<String, String> serialToPatientId = {};
        List<Future<DocumentSnapshot>> childFutures = [];
        List<String> childSerials = [];

        for (int i = 0; i < 3; i++) {
          for (final doc in snaps[i].docs) {
            final data = doc.data();
            final serial = data['serial']?.toString();
            if (serial == null || serial.isEmpty) continue;
            final cnic = data['cnic']?.toString() ?? '';
            final id = data['id']?.toString() ?? '';
            if (cnic.isNotEmpty) {
              serialToPatientId[serial] = cnic;
            } else if (id.isNotEmpty) {
              childFutures.add(FirebaseFirestore.instance.collection('branches/$branchId/patients').doc(id).get());
              childSerials.add(serial);
            }
          }
        }

        if (childFutures.isNotEmpty) {
          final childSnaps = await Future.wait(childFutures);
          for (int j = 0; j < childSnaps.length; j++) {
            final snap = childSnaps[j];
            if (snap.exists && snap.data() != null) {
              final gCnic = (snap.data() as Map<String, dynamic>)['guardianCnic']?.toString() ?? '';
              if (gCnic.isNotEmpty) {
                serialToPatientId[childSerials[j]] = gCnic;
              }
            }
          }
        }

        final presFutures = serialToPatientId.entries
            .map((e) => presRoot.doc(e.value).collection('prescriptions').doc(e.key).get())
            .toList();
        if (presFutures.isNotEmpty) {
          final presSnaps = await Future.wait(presFutures);
          prescribed += presSnaps.where((s) => s.exists).length;
        }

        // Dispensary (Dispense data)
        final dispRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('dispensary')
            .doc(ds)
            .collection(ds);
        final dispCountSnap = await dispRef.count().get();
        dispensed += dispCountSnap.count ?? 0;
      }
      return {
        'tokens': tokens,
        'prescribed': prescribed,
        'dispensed': dispensed,
      };
    } catch (e) {
      return {
        'tokens': 0,
        'prescribed': 0,
        'dispensed': 0,
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