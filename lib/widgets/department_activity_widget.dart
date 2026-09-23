// lib/widgets/department_activity_widget.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/local_storage_service.dart';
import '../services/auto_update_service.dart';

class DepartmentActivityWidget extends StatefulWidget {
  final String branchId;

  const DepartmentActivityWidget({
    super.key,
    required this.branchId,
  });

  @override
  State<DepartmentActivityWidget> createState() => _DepartmentActivityWidgetState();
}

class _DepartmentActivityWidgetState extends State<DepartmentActivityWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, dynamic>> _departments = const [
    {
      'id': 'dispensary',
      'title': 'Dispensary & OPD',
      'icon': Icons.local_hospital_rounded,
      'color': Color(0xFF10B981),
      'roles': ['receptionist', 'doctor', 'dispenser', 'pharmacist', 'supervisor'],
    },
    {
      'id': 'madrassa',
      'title': 'Madrassa Department',
      'icon': Icons.school_rounded,
      'color': Color(0xFF3B82F6),
      'roles': ['teacher', 'faculty', 'madrassa', 'madrassa admin'],
    },
    {
      'id': 'school',
      'title': 'School & Library',
      'icon': Icons.local_library_rounded,
      'color': Color(0xFF8B5CF6),
      'roles': ['school', 'school admin', 'library'],
    },
    {
      'id': 'finance',
      'title': 'Finance & Accounts',
      'icon': Icons.account_balance_rounded,
      'color': Color(0xFFF59E0B),
      'roles': ['finance manager', 'finance', 'donations', 'global accounts'],
    },
    {
      'id': 'dasterkhwaan',
      'title': 'Welfare & Kitchen',
      'icon': Icons.soup_kitchen_rounded,
      'color': Color(0xFFEF4444),
      'roles': ['dasterkhwaan', 'attendance', 'kitchen'],
    },
  ];

  late Future<List<Map<String, dynamic>>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _departments.length, vsync: this);
    _usersFuture = _loadUsers();
    if (!Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      LocalStorageService.ensureBoxOpen(LocalStorageService.entriesBox).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(DepartmentActivityWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      _usersFuture = _loadUsers();
    }
  }

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    final local = LocalStorageService.getAllLocalUsers();
    if (local.isNotEmpty) {
      return local;
    }
    try {
      final normalizedBranch = widget.branchId.trim().toLowerCase();
      QuerySnapshot snap;
      if (normalizedBranch.isEmpty || normalizedBranch == 'all' || normalizedBranch == 'global') {
        snap = await FirebaseFirestore.instance.collection('users').limit(100).get(const GetOptions(source: Source.serverAndCache));
      } else {
        snap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(normalizedBranch)
            .collection('users')
            .limit(100)
            .get(const GetOptions(source: Source.serverAndCache));
      }
      return snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
    } catch (_) {
      return LocalStorageService.getAllLocalUsers();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getDepartmentEntries(String deptId) {
    final entries = LocalStorageService.getLocalEntries(widget.branchId);
    if (deptId == 'all') return entries;

    final roles = (_departments.firstWhere((d) => d['id'] == deptId)['roles'] as List<String>)
        .map((r) => r.toLowerCase())
        .toList();

    return entries.where((e) {
      final role = (e['performedByRole'] ?? e['role'] ?? '').toString().toLowerCase();
      final qt = (e['queueType'] ?? e['category'] ?? '').toString().toLowerCase();

      if (roles.contains(role)) return true;
      if (deptId == 'dispensary' && (qt.contains('zakat') || qt.contains('general') || qt.contains('dispensary') || qt.contains('patient'))) return true;
      if (deptId == 'madrassa' && qt.contains('madrassa')) return true;
      if (deptId == 'school' && (qt.contains('school') || qt.contains('library'))) return true;
      if (deptId == 'finance' && (qt.contains('finance') || qt.contains('donation') || qt.contains('expense'))) return true;
      if (deptId == 'dasterkhwaan' && (qt.contains('food') || qt.contains('dasterkhwaan'))) return true;

      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Department Selection TabBar
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: const Color(0xFF10B981),
            indicatorWeight: 3,
            labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
            unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: _departments.map((dept) {
              return Tab(
                child: Row(
                  children: [
                    Icon(dept['icon'] as IconData, size: 16, color: dept['color'] as Color),
                    const SizedBox(width: 8),
                    Text(dept['title'] as String),
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        // Tab Views for Each Department
        Expanded(
          child: !Hive.isBoxOpen(LocalStorageService.entriesBox)
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                )
              : ValueListenableBuilder(
                  valueListenable: Hive.box(LocalStorageService.entriesBox).listenable(),
                  builder: (context, Box box, _) {
              return TabBarView(
                controller: _tabController,
                children: _departments.map((dept) {
                  final deptId = dept['id'] as String;
                  final deptColor = dept['color'] as Color;
                  final deptEntries = _getDepartmentEntries(deptId);

                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _usersFuture,
                    builder: (context, snapshot) {
                      final allUsers = snapshot.data ?? [];

                      final deptRoles = (dept['roles'] as List<String>).map((r) => r.toLowerCase()).toList();
                      final deptUsers = allUsers.where((u) {
                        final role = (u['role'] ?? '').toString().toLowerCase();
                        final userBranch = (u['branchId'] ?? '').toString();
                        if (widget.branchId.isNotEmpty && widget.branchId != 'all' && userBranch.isNotEmpty && userBranch != 'all' && userBranch != widget.branchId) {
                          return false;
                        }
                        return deptRoles.contains(role);
                      }).toList();

                      deptUsers.sort((a, b) {
                        final rA = (a['role'] ?? '').toString().toLowerCase().trim();
                        final rB = (b['role'] ?? '').toString().toLowerCase().trim();
                        if (rA == 'chairman' && rB != 'chairman') return -1;
                        if (rA != 'chairman' && rB == 'chairman') return 1;
                        return (a['name'] ?? a['username'] ?? '').toString().compareTo((b['name'] ?? b['username'] ?? '').toString());
                      });

                      final activeUsersCount = deptUsers.where((u) => u['isOnline'] == true).length;
                      final totalTransactions = deptEntries.length;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Department Overview Metrics Card
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? deptColor.withValues(alpha: 0.3) : const Color(0xFFE2E8F0)),
                                boxShadow: isDark ? [] : [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: deptColor.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(dept['icon'] as IconData, size: 28, color: deptColor),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dept['title'] as String,
                                          style: TextStyle(
                                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Active Department Staff & Data Routing Log',
                                          style: TextStyle(
                                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Metric Pills
                                  _metricPill('Active Staff', '$activeUsersCount / ${deptUsers.length}', Colors.blueAccent, isDark),
                                  const SizedBox(width: 12),
                                  _metricPill('Total Actions', '$totalTransactions', deptColor, isDark),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Section Title
                            Text(
                              'Department Staff Members & Progress Timeline',
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),

                            if (deptUsers.isEmpty && deptEntries.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                ),
                                child: Center(
                                  child: Text(
                                    'No staff members or data logged for this department yet.',
                                    style: TextStyle(
                                      color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: deptUsers.isNotEmpty ? deptUsers.length : 1,
                                itemBuilder: (context, idx) {
                                  if (deptUsers.isEmpty) {
                                    return _buildUnassignedEntriesCard(deptEntries, deptColor, isDark);
                                  }

                                  final u = deptUsers[idx];
                                  final uid = u['uid'] ?? '';
                                  final name = (u['name'] ?? u['username'] ?? u['email'] ?? 'Staff User').toString();
                                  final role = (u['role'] ?? 'Staff').toString().toUpperCase();
                                  final isOnline = u['isOnline'] == true;
                                  
                                  // Safe extraction of lastDeviceInfo map
                                  final rawDevInfo = u['lastDeviceInfo'];
                                  final devInfo = rawDevInfo is Map ? Map<String, dynamic>.from(rawDevInfo) : null;
                                  final deviceSummary = (devInfo?['deviceSummary'] ?? devInfo?['deviceName'] ?? 'Windows Workstation').toString();
                                  final appVer = (u['appVersion'] ?? devInfo?['appVersion'] ?? 'v${AutoUpdateService.currentVersion}').toString();

                                  // Filter user's specific actions from local entries
                                  final userActions = deptEntries.where((e) {
                                    final by = (e['performedBy'] ?? '').toString().toLowerCase();
                                    final uidInEntry = (e['userId'] ?? e['performedByUid'] ?? '').toString();
                                    return uidInEntry == uid || by.contains(name.toLowerCase());
                                  }).toList();

                                  userActions.sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));

                                  final isChairman = role.toLowerCase().trim() == 'chairman';

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      gradient: isChairman
                                          ? const LinearGradient(
                                              colors: [Color(0xFF1E112A), Color(0xFF2A1706), Color(0xFF170F2A)],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      color: isChairman ? null : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isChairman
                                            ? const Color(0xFFFBBF24)
                                            : (isDark ? (isOnline ? Colors.greenAccent.withValues(alpha: 0.3) : const Color(0xFF334155)) : const Color(0xFFE2E8F0)),
                                        width: isChairman ? 2.0 : 1.0,
                                      ),
                                      boxShadow: isChairman
                                          ? [
                                              const BoxShadow(
                                                color: Color(0x66F59E0B),
                                                blurRadius: 18,
                                                spreadRadius: 1.5,
                                              )
                                            ]
                                          : (isDark ? [] : [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.03),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]),
                                    ),
                                    child: ExpansionTile(
                                      shape: Border.all(color: Colors.transparent),
                                      leading: CircleAvatar(
                                        backgroundColor: isChairman ? const Color(0xFF92400E) : deptColor.withValues(alpha: 0.2),
                                        child: isChairman
                                            ? const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFCD34D), size: 20)
                                            : Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                style: TextStyle(color: deptColor, fontWeight: FontWeight.bold),
                                              ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                color: isChairman ? const Color(0xFFFFFBEB) : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                letterSpacing: isChairman ? 0.3 : 0,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isOnline
                                                  ? (isDark ? Colors.greenAccent.withValues(alpha: 0.15) : const Color(0xFFECFDF5))
                                                  : (isDark ? Colors.grey.withValues(alpha: 0.2) : const Color(0xFFF1F5F9)),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isOnline ? const Color(0xFF10B981) : (isDark ? Colors.grey : const Color(0xFFCBD5E1)),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.circle, size: 7, color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isOnline ? 'ONLINE' : 'OFFLINE',
                                                  style: TextStyle(
                                                    color: isOnline ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46)) : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          isChairman
                                              ? '👑 CHAIRMAN · SUPREME AUTHORITY • $deviceSummary • App $appVer'
                                              : '$role • $deviceSummary • App $appVer • (${userActions.length} Actions Saved)',
                                          style: TextStyle(
                                            color: isChairman ? const Color(0xFFFDE68A) : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                            fontSize: 11.5,
                                            fontWeight: isChairman ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      children: [
                                        Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), height: 1),
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: userActions.isEmpty
                                              ? Text('No data actions recorded for this user today.', style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8), fontSize: 13))
                                              : Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'USER ACTION HISTORY TIMELINE:',
                                                      style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    ListView.builder(
                                                      shrinkWrap: true,
                                                      physics: const NeverScrollableScrollPhysics(),
                                                      itemCount: userActions.length > 8 ? 8 : userActions.length,
                                                      itemBuilder: (ctx, actionIdx) {
                                                        final action = userActions[actionIdx];
                                                        final serial = action['serial']?.toString() ?? 'N/A';
                                                        final patient = (action['patientName'] ?? action['name'] ?? action['title'] ?? 'Entry Payload').toString();
                                                        final status = (action['status'] ?? 'completed').toString();
                                                        final timeStr = action['createdAt']?.toString() ?? '';

                                                        String timeDisplay = '';
                                                        if (timeStr.isNotEmpty) {
                                                          try {
                                                            timeDisplay = DateFormat('hh:mm a').format(DateTime.parse(timeStr));
                                                          } catch (_) {}
                                                        }

                                                        return Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                                          child: Row(
                                                            children: [
                                                              const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF10B981)),
                                                              const SizedBox(width: 8),
                                                              Text('#$serial', style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 12)),
                                                              const SizedBox(width: 8),
                                                              Expanded(
                                                                child: Text(
                                                                  patient,
                                                                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13),
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                              Text(
                                                                status.toUpperCase(),
                                                                style: TextStyle(
                                                                  color: status == 'completed' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                                                  fontSize: 10,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                              const SizedBox(width: 12),
                                                              Text(timeDisplay, style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8), fontSize: 11)),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUnassignedEntriesCard(List<Map<String, dynamic>> entries, Color color, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '${entries.length} department records processed.',
          style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF0F172A)),
        ),
      ),
    );
  }

  Widget _metricPill(String title, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.35 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
