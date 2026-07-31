// lib/pages/users.dart — Role-Theme Aware + Full Mobile Responsive

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dispensary/patient_detail_screen.dart';
import 'user_detail_screen.dart';
import 'dart:async';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';
import '../services/local_storage_service.dart';
import '../services/image_upload_service.dart';
import '../widgets/global_module_wrapper.dart';
import '../widgets/app_back_button.dart';
import '../widgets/device_badge_widget.dart';
import '../utils/formatters.dart';

class UsersScreen extends StatefulWidget {
  final bool isPatientMode;
  final bool isGuardianMode;
  final String? branchId;
  const UsersScreen({
    super.key,
    this.isPatientMode = false,
    this.isGuardianMode = false,
    this.branchId,
  });

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _branches = [];
  TabController? _tabController;

  String? _filterStatus;
  String _searchQuery = '';
  String? _roleFilter;
  String? _genderFilter;
  String? _ageFilter;
  bool _familyView = false;
  String _selectedCategoryFilter = 'all';
  Box? _localBox;
  bool _filtersExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _initHive();
  }

  Future<void> _initHive() async => _localBox = await Hive.openBox('local');

  Future<void> _loadBranches() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('branches').get();
      var branches = snap.docs.map((d) {
        final data = d.data();
        return {'id': d.id, 'name': data['name'] as String? ?? d.id};
      }).toList();

      if (widget.branchId != null) {
        branches = branches.where((b) => b['id'] == widget.branchId).toList();
      }

      branches.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      setState(() {
        _branches = branches;
        _tabController = TabController(length: branches.length, vsync: this);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to load branches: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    if (_branches.isEmpty || _tabController == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: t.accent),
        const SizedBox(height: 16),
        Text('Loading branches…', style: TextStyle(color: t.textSecondary, fontSize: 14)),
      ]));
    }

    final isWrapped = GlobalModuleWrapper.isWrapped(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: isWrapped
          ? null
          : AppBar(
              backgroundColor: t.bgCard,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: AppBackButton(color: t.textPrimary),
              title: Text(
                widget.isPatientMode
                    ? 'Patients'
                    : (widget.isGuardianMode ? 'Guardians' : 'Staff'),
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(height: 1, color: t.bgRule),
              ),
            ),
      body: Column(children: [
        // ── Tab bar ──
        Container(
          color: t.bgCard,
          child: TabBar(
            controller: _tabController!,
            isScrollable: true,
            labelColor: t.accent,
            unselectedLabelColor: t.textTertiary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(color: t.accent, width: 3),
              insets: const EdgeInsets.symmetric(horizontal: 12),
            ),
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: _branches.map((b) => Tab(
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(b['name'] as String)),
            )).toList(),
          ),
        ),

        // ── Filter bar ──
        _buildFilterBar(t),

        // ── Content ──
        Expanded(
          child: TabBarView(
            controller: _tabController!,
            children: _branches.map((b) => _buildList(b['id'] as String, t)).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildFilterBar(RoleThemeData t) {
    return Container(
      color: t.bgCard,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.bgRule),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                style: TextStyle(fontSize: 14, color: t.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.isPatientMode
                      ? 'Search records…'
                      : (widget.isGuardianMode ? 'Search by username/email…' : 'Search by username…'),
                  hintStyle: TextStyle(color: t.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: t.accent, size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          if (!widget.isGuardianMode) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _filtersExpanded ? t.accent : t.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _filtersExpanded ? t.accent : t.bgRule),
                ),
                child: Row(children: [
                  Icon(Icons.tune_rounded, color: _filtersExpanded ? Colors.white : t.textSecondary, size: 18),
                  const SizedBox(width: 5),
                  Text('Filters', style: TextStyle(
                      color: _filtersExpanded ? Colors.white : t.textSecondary,
                      fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ]),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _filtersExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: widget.isPatientMode ? _buildPatientFilters(t) : _buildStaffFilters(t),
          ),
        ),
      ]),
    );
  }

  Widget _buildPatientFilters(RoleThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Status chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip(t, 'All Status', _filterStatus == null, () => setState(() => _filterStatus = null)),
          const SizedBox(width: 6),
          _chip(t, 'Zakat', _filterStatus == 'Zakat', () => setState(() => _filterStatus = _filterStatus == 'Zakat' ? null : 'Zakat')),
          const SizedBox(width: 6),
          _chip(t, 'Non-Zakat', _filterStatus == 'Non-Zakat', () => setState(() => _filterStatus = _filterStatus == 'Non-Zakat' ? null : 'Non-Zakat')),
          const SizedBox(width: 6),
          _chip(t, 'GMWF', _filterStatus == 'GMWF', () => setState(() => _filterStatus = _filterStatus == 'GMWF' ? null : 'GMWF')),
        ]),
      ),
      const SizedBox(height: 8),
      // Gender + Age + Family in one scrollable row
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip(t, 'All Gender', _genderFilter == null, () => setState(() => _genderFilter = null)),
          const SizedBox(width: 6),
          _chip(t, 'Male', _genderFilter == 'Male', () => setState(() => _genderFilter = _genderFilter == 'Male' ? null : 'Male')),
          const SizedBox(width: 6),
          _chip(t, 'Female', _genderFilter == 'Female', () => setState(() => _genderFilter = _genderFilter == 'Female' ? null : 'Female')),
          const SizedBox(width: 12),
          _chip(t, '0–18', _ageFilter == 'child', () => setState(() => _ageFilter = _ageFilter == 'child' ? null : 'child')),
          const SizedBox(width: 6),
          _chip(t, '19–60', _ageFilter == 'adult', () => setState(() => _ageFilter = _ageFilter == 'adult' ? null : 'adult')),
          const SizedBox(width: 6),
          _chip(t, '61+', _ageFilter == 'senior', () => setState(() => _ageFilter = _ageFilter == 'senior' ? null : 'senior')),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => _familyView = !_familyView),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _familyView ? t.accent : t.bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _familyView ? t.accent : t.bgRule),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.family_restroom_rounded, color: _familyView ? Colors.white : t.textSecondary, size: 14),
                const SizedBox(width: 5),
                Text('Family', style: TextStyle(color: _familyView ? Colors.white : t.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildStaffFilters(RoleThemeData t) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _chip(t, 'All Roles', _roleFilter == null, () => setState(() => _roleFilter = null)),
        const SizedBox(width: 6),
        ...{
          'doctor': 'Doctor', 'receptionist': 'Receptionist',
          'dispenser': 'Dispenser', 'supervisor': 'Supervisor',
          'food token generator': 'Food Token', 'kitchen': 'Kitchen',
        }.entries.map((e) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: _chip(t, e.value, _roleFilter == e.key,
              () => setState(() => _roleFilter = _roleFilter == e.key ? null : e.key)),
        )),
      ]),
    );
  }

  Widget _chip(RoleThemeData t, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? t.accent : t.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? t.accent : t.bgRule),
        ),
        child: Text(label, style: TextStyle(
            color: active ? Colors.white : t.textSecondary,
            fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ── List ──

  Future<void> _syncPatientsForBranch(String branchId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        d['patientId'] = doc.id;
        d['branchId'] = branchId;
        await LocalStorageService.saveLocalPatient(d);
      }
    } catch (e) {
      debugPrint('Sync patients failed for branch $branchId: $e');
    }
  }

  Widget _buildList(String branchId, RoleThemeData t) {
    if (widget.isPatientMode) {
      _syncPatientsForBranch(branchId);
      return ValueListenableBuilder<Box>(
        valueListenable: Hive.box(LocalStorageService.patientsBox).listenable(),
        builder: (context, box, _) {
          final allLocal = LocalStorageService.getAllLocalPatients(branchId: branchId);
          var filtered = allLocal.where((p) {
            if (_filterStatus != null && p['status']?.toString().toLowerCase() != _filterStatus!.toLowerCase()) {
              return false;
            }
            if (_genderFilter != null && p['gender']?.toString().toLowerCase() != _genderFilter!.toLowerCase()) {
              return false;
            }
            if (_ageFilter != null) {
              final age = (p['age'] as num?)?.toInt() ?? 0;
              if (_ageFilter == 'child' && age > 18) return false;
              if (_ageFilter == 'adult' && (age < 19 || age > 60)) return false;
              if (_ageFilter == 'senior' && age < 61) return false;
            }
            if (_searchQuery.isNotEmpty) {
              final name = (p['name'] as String?)?.toLowerCase() ?? '';
              final phone = (p['phone'] as String?)?.toLowerCase() ?? '';
              final cnic = (p['cnic'] as String?)?.toLowerCase() ?? '';
              final gcnic = (p['guardianCnic'] as String?)?.toLowerCase() ?? '';
              final uid = (p['patientId'] as String?)?.toLowerCase() ?? '';
              return name.contains(_searchQuery) || phone.contains(_searchQuery) ||
                  cnic.contains(_searchQuery) || gcnic.contains(_searchQuery) || uid.contains(_searchQuery);
            }
            return true;
          }).toList();

          filtered.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));

          if (filtered.isEmpty) {
            return _emptyState(t, Icons.person_search_rounded, 'No patients found', 'Try adjusting your search or filters');
          }

          return Column(children: [
            Container(
              color: t.accentMuted.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.people_rounded, color: t.accent, size: 14),
                    const SizedBox(width: 5),
                    Text('${filtered.length} Patients', style: TextStyle(color: t.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: _familyView
                  ? _buildFamilyView(filtered, branchId, t)
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _buildCard(filtered[i], branchId, t),
                    ),
            ),
          ]);
        },
      );
    }

    // Staff path (original StreamBuilder)
    final collection = 'users';
    return StreamBuilder<QuerySnapshot>(
      stream: _getFilteredStream(branchId, collection),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: t.accent));
        }

        final Map<String, Map<String, dynamic>> mergedMap = {};

        String getDedupKey(Map<String, dynamic> u, String defaultId) {
          final usernameLower = (u['usernameLower'] ?? u['username'])?.toString().trim().toLowerCase() ?? '';
          if (!widget.isPatientMode && usernameLower.isNotEmpty) {
            return 'user:$usernameLower';
          }
          final email = u['email']?.toString().trim().toLowerCase() ?? '';
          if (!widget.isPatientMode && email.isNotEmpty) {
            return 'email:$email';
          }
          final uid = (u['uid'] ?? u['id'] ?? u['patientId'] ?? defaultId).toString();
          return 'id:$uid';
        }

        // 1. Add Hive local users first
        try {
          final box = Hive.box('local_users');
          for (final val in box.values) {
            if (val is Map) {
              final Map<String, dynamic> u = Map<String, dynamic>.from(val);
              final uid = u['uid']?.toString() ?? u['id']?.toString() ?? '';
              final uBranchId = u['branchId']?.toString() ?? '';
              if (uid.isNotEmpty) {
                if (uBranchId == branchId || uBranchId == 'all' || uBranchId == 'global') {
                  mergedMap[getDedupKey(u, uid)] = u;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error reading local users: $e');
        }

        // 2. Add Firestore users on top
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final Map<String, dynamic> u = {'id': doc.id, ...doc.data() as Map<String, dynamic>};
            final key = getDedupKey(u, doc.id);
            mergedMap[key] = u;
          }
        }

        var list = mergedMap.values.toList();

        if (branchId != 'all' && branchId != 'global') {
          final targetBranch = branchId.trim().toLowerCase();
          list = list.where((item) {
            final uBranch = (item['branchId'] ?? item['branch'] ?? '').toString().trim().toLowerCase();
            if (uBranch.isEmpty) return true;
            return uBranch == targetBranch || uBranch == 'all' || uBranch == 'global';
          }).toList();
        }

        if (_searchQuery.isNotEmpty) {
          list = list.where((item) {
            final username = (item['username'] as String?)?.toLowerCase() ?? '';
            final name = (item['name'] as String?)?.toLowerCase() ?? '';
            final email = (item['email'] as String?)?.toLowerCase() ?? '';
            return username.contains(_searchQuery) || name.contains(_searchQuery) || email.contains(_searchQuery);
          }).toList();
        }

        if (widget.isGuardianMode) {
          list = list.where((item) => (item['role'] as String? ?? '').toLowerCase() == 'madrassa parent').toList();
        } else {
          list = list.where((item) => (item['role'] as String? ?? '').toLowerCase() != 'madrassa parent').toList();
        }

        if (!widget.isGuardianMode && _roleFilter != null) {
          final target = _roleFilter!.toLowerCase();
          list = list.where((item) {
            final role = (item['role'] as String? ?? '').toLowerCase();
            if (target == 'dispenser') {
              return role.contains('dis') || role.contains('dispens');
            } else if (target == 'doctor') {
              return role.contains('doc');
            } else if (target == 'receptionist') {
              return role.contains('rec');
            } else if (target == 'supervisor') {
              return role.contains('sup') || role.contains('manag');
            }
            return role == target;
          }).toList();
        }

        list.sort((a, b) => (a['username'] as String? ?? '').compareTo(b['username'] as String? ?? ''));

        bool isUserOnline(Map<String, dynamic> data) {
          if (data['isOnline'] == false) return false;

          final raw = data['lastSeen'] ?? data['lastOnlineAt'] ?? data['lastActiveAt'] ?? data['lastLoginAt'] ?? data['updatedAt'];
          DateTime? lastActive;
          if (raw is Timestamp) {
            lastActive = raw.toDate();
          } else if (raw is DateTime) {
            lastActive = raw;
          } else if (raw is String && raw.isNotEmpty) {
            lastActive = DateTime.tryParse(raw);
          }

          if (lastActive != null) {
            final diffMinutes = DateTime.now().difference(lastActive).inMinutes;
            return diffMinutes <= 2;
          }

          return data['isOnline'] == true;
        }

        String getDepartment(Map<String, dynamic> u) {
          final role = (u['role'] as String? ?? '').toLowerCase().trim();
          final dept = (u['department'] as String? ?? '').toLowerCase().trim();

          if (role.contains('school') || dept.contains('school')) {
            if (role.contains('guardian') || role.contains('parent')) {
              return 'school_guardian';
            }
            return 'school_faculty';
          }
          if (role == 'madrassa parent' || role == 'madrassa guardian' || role.contains('madrassa')) {
            if (role.contains('guardian') || role.contains('parent')) {
              return 'madrassa_guardian';
            }
            return 'madrassa_faculty';
          }
          if (role.contains('doc') || role.contains('dis') || role.contains('rec') || role.contains('nurse') || role.contains('sup') || role.contains('supervisor') || dept.contains('dispensary') || dept.contains('health')) {
            return 'dispensary';
          }
          if (role.contains('kitchen') || role.contains('cook') || role.contains('food') || role.contains('token') || role.contains('daster') || dept.contains('kitchen') || dept.contains('daster')) {
            return 'kitchen';
          }
          return 'office';
        }

        final onlineList = <Map<String, dynamic>>[];
        final officeList = <Map<String, dynamic>>[];
        final kitchenList = <Map<String, dynamic>>[];
        final dispensaryList = <Map<String, dynamic>>[];
        final madrassaFacultyList = <Map<String, dynamic>>[];
        final madrassaGuardianList = <Map<String, dynamic>>[];
        final schoolFacultyList = <Map<String, dynamic>>[];
        final schoolGuardianList = <Map<String, dynamic>>[];
        final revokedList = <Map<String, dynamic>>[];

        for (final item in list) {
          final status = (item['status'] ?? item['accountStatus'] ?? item['studentStatus'] ?? 'active').toString().toLowerCase().trim();
          final isOffboardedOrArchived = (
              status == 'inactive' ||
              status == 'suspended' ||
              status == 'terminated' ||
              status == 'resigned' ||
              status == 'retired' ||
              status == 'offboarded' ||
              status == 'revoked' ||
              status == 'archived' ||
              status == 'hifz_completed' ||
              status == 'hifz completed' ||
              status == 'left' ||
              status == 'dropped' ||
              status == 'dropped_out' ||
              item['isActive'] == false
          );

          if (isOffboardedOrArchived) {
            revokedList.add(item);
          } else if (isUserOnline(item)) {
            onlineList.add(item);
          } else {
            final dept = getDepartment(item);
            if (dept == 'school_faculty') {
              schoolFacultyList.add(item);
            } else if (dept == 'school_guardian') {
              schoolGuardianList.add(item);
            } else if (dept == 'madrassa_faculty') {
              madrassaFacultyList.add(item);
            } else if (dept == 'madrassa_guardian') {
              madrassaGuardianList.add(item);
            } else if (dept == 'dispensary') {
              dispensaryList.add(item);
            } else if (dept == 'kitchen') {
              kitchenList.add(item);
            } else {
              officeList.add(item);
            }
          }
        }

        if (list.isEmpty) {
          return _emptyState(t, widget.isGuardianMode ? Icons.people_outline : Icons.manage_accounts_rounded, widget.isGuardianMode ? 'No guardians found' : 'No users found', 'Try adjusting your search query');
        }

        final listItems = <Widget>[];

        void addCategorySection(String title, int count, IconData icon, Color color, List<Map<String, dynamic>> items) {
          if (items.isEmpty) return;
          listItems.add(_buildCategoryHeader(t, title, count, icon, color));
          for (final item in items) {
            listItems.add(_buildCard(item, branchId, t));
          }
        }

        if (_selectedCategoryFilter == 'online') {
          addCategorySection('Currently Online', onlineList.length, Icons.fiber_manual_record, Colors.green, onlineList);
        } else if (_selectedCategoryFilter == 'office') {
          addCategorySection('Office & Administration', officeList.length, Icons.business_center_rounded, Colors.indigo, officeList);
        } else if (_selectedCategoryFilter == 'kitchen') {
          addCategorySection('Dasterkhawaan & Kitchen', kitchenList.length, Icons.soup_kitchen_rounded, Colors.amber.shade800, kitchenList);
        } else if (_selectedCategoryFilter == 'dispensary') {
          addCategorySection('Dispensary Department', dispensaryList.length, Icons.local_hospital_rounded, Colors.blue, dispensaryList);
        } else if (_selectedCategoryFilter == 'madrassa_faculty') {
          addCategorySection('Madrassa Faculty', madrassaFacultyList.length, Icons.school_rounded, Colors.teal, madrassaFacultyList);
        } else if (_selectedCategoryFilter == 'madrassa_guardian') {
          addCategorySection('Madrassa Guardians', madrassaGuardianList.length, Icons.family_restroom_rounded, Colors.orange, madrassaGuardianList);
        } else if (_selectedCategoryFilter == 'school_faculty') {
          addCategorySection('School Faculty', schoolFacultyList.length, Icons.account_balance_rounded, Colors.deepPurple, schoolFacultyList);
        } else if (_selectedCategoryFilter == 'school_guardian') {
          addCategorySection('School Guardians', schoolGuardianList.length, Icons.family_restroom_rounded, Colors.purpleAccent, schoolGuardianList);
        } else if (_selectedCategoryFilter == 'revoked') {
          addCategorySection('Offboarded & Inactive Accounts', revokedList.length, Icons.no_accounts_rounded, Colors.red, revokedList);
        } else {
          addCategorySection('Currently Online', onlineList.length, Icons.fiber_manual_record, Colors.green, onlineList);
          addCategorySection('Office & Administration', officeList.length, Icons.business_center_rounded, Colors.indigo, officeList);
          addCategorySection('Dasterkhawaan & Kitchen', kitchenList.length, Icons.soup_kitchen_rounded, Colors.amber.shade800, kitchenList);
          addCategorySection('Dispensary Department', dispensaryList.length, Icons.local_hospital_rounded, Colors.blue, dispensaryList);
          if (madrassaFacultyList.isNotEmpty) addCategorySection('Madrassa Faculty', madrassaFacultyList.length, Icons.school_rounded, Colors.teal, madrassaFacultyList);
          if (madrassaGuardianList.isNotEmpty) addCategorySection('Madrassa Guardians', madrassaGuardianList.length, Icons.family_restroom_rounded, Colors.orange, madrassaGuardianList);
          if (schoolFacultyList.isNotEmpty) addCategorySection('School Faculty', schoolFacultyList.length, Icons.account_balance_rounded, Colors.deepPurple, schoolFacultyList);
          if (schoolGuardianList.isNotEmpty) addCategorySection('School Guardians', schoolGuardianList.length, Icons.family_restroom_rounded, Colors.purpleAccent, schoolGuardianList);
          addCategorySection('Offboarded & Inactive Accounts', revokedList.length, Icons.no_accounts_rounded, Colors.red, revokedList);
        }

        return Column(children: [
          Container(
            color: t.bgCard,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _categoryChip(t, 'All (${list.length})', 'all', Icons.grid_view_rounded, t.accent),
                  const SizedBox(width: 6),
                  _categoryChip(t, 'Online (${onlineList.length})', 'online', Icons.fiber_manual_record, Colors.green),
                  const SizedBox(width: 6),
                  _categoryChip(t, 'Office (${officeList.length})', 'office', Icons.business_center_rounded, Colors.indigo),
                  const SizedBox(width: 6),
                  _categoryChip(t, 'Dasterkhawaan (${kitchenList.length})', 'kitchen', Icons.soup_kitchen_rounded, Colors.amber.shade800),
                  const SizedBox(width: 6),
                  _categoryChip(t, 'Dispensary (${dispensaryList.length})', 'dispensary', Icons.local_hospital_rounded, Colors.blue),
                  const SizedBox(width: 6),
                  // Madrassa faculty and guardians
                  if (madrassaFacultyList.isNotEmpty) ...[
                    _categoryChip(t, 'Madrassa Faculty (${madrassaFacultyList.length})', 'madrassa_faculty', Icons.school_rounded, Colors.teal),
                    const SizedBox(width: 6),
                  ],
                  if (madrassaGuardianList.isNotEmpty) ...[
                    _categoryChip(t, 'Madrassa Guardians (${madrassaGuardianList.length})', 'madrassa_guardian', Icons.family_restroom_rounded, Colors.orange),
                    const SizedBox(width: 6),
                  ],
                  // School faculty and guardians
                  if (schoolFacultyList.isNotEmpty) ...[
                    _categoryChip(t, 'School Faculty (${schoolFacultyList.length})', 'school_faculty', Icons.account_balance_rounded, Colors.deepPurple),
                    const SizedBox(width: 6),
                  ],
                  if (schoolGuardianList.isNotEmpty) ...[
                    _categoryChip(t, 'School Guardians (${schoolGuardianList.length})', 'school_guardian', Icons.family_restroom_rounded, Colors.purpleAccent),
                    const SizedBox(width: 6),
                  ],
                  _categoryChip(t, 'Offboarded (${revokedList.length})', 'revoked', Icons.no_accounts_rounded, Colors.red),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
              children: listItems,
            ),
          ),
        ]);
      },
    );
  }

  Color _getStatusColor(String rawStatus) {
    final s = rawStatus.toLowerCase().trim();
    if (s == 'hifz_completed' || s == 'hifz completed') return const Color(0xFF4C4DDC);
    if (s == 'left') return Colors.redAccent;
    if (s == 'dropped' || s == 'dropped out' || s == 'dropped_out') return Colors.red;
    if (s == 'archived') return Colors.orange;
    if (s == 'active') return Colors.green;
    return Colors.red;
  }

  bool _isUserOnline(Map<String, dynamic> data) {
    if (data['isOnline'] == false) return false;
    if (data['isOnline'] == true) return true;
    final raw = data['lastOnlineAt'] ?? data['lastLoginAt'] ?? data['updatedAt'];
    if (raw is Timestamp) {
      return DateTime.now().difference(raw.toDate()).inMinutes <= 15;
    } else if (raw is String && raw.isNotEmpty) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) return DateTime.now().difference(dt).inMinutes <= 15;
    }
    return false;
  }

  Widget _categoryChip(RoleThemeData t, String label, String catKey, IconData icon, Color color) {
    final active = _selectedCategoryFilter == catKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategoryFilter = catKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? Colors.white : color, size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : color,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(RoleThemeData t, String title, int count, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: color,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> data, String branchId, RoleThemeData t) {
    final itemId = (data['uid'] ?? data['id'] ?? data['docId'] ?? data['patientId'] ?? '').toString();
    final profilePicUrl = data['profilePictureUrl'] as String?;
    final name = widget.isPatientMode
        ? (data['name'] ?? 'Unknown').toString()
        : resolveUserDisplayName(data, fallback: 'Unknown');
    final subtitle = widget.isPatientMode
        ? '${data['gender'] ?? 'N/A'} · ${data['age']?.toString() ?? '?'} yrs · ${data['status'] ?? ''}'
        : ((data['role'] as String? ?? 'N/A').toLowerCase() == 'madrassa parent' ? 'GUARDIAN' : (data['role'] as String? ?? 'N/A').toUpperCase());

    final initials = name.trim().isEmpty ? '?' :
        name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    final rawRole = (data['role'] as String? ?? '').toLowerCase();
    final isGuardianRole = rawRole == 'madrassa parent' || rawRole == 'madrassa guardian';
    final isOnline = _isUserOnline(data);
    final status = (data['status'] ?? data['accountStatus'] ?? 'active').toString().toLowerCase().trim();
    final isRevoked = status == 'inactive' ||
        status == 'suspended' ||
        status == 'terminated' ||
        status == 'resigned' ||
        status == 'retired' ||
        status == 'offboarded' ||
        status == 'revoked' ||
        data['isActive'] == false;

    final Map<String, dynamic>? devInfo = (data['lastDeviceInfo'] is Map)
        ? Map<String, dynamic>.from(data['lastDeviceInfo'] as Map)
        : ((data['deviceInfo'] is Map) ? Map<String, dynamic>.from(data['deviceInfo'] as Map) : null);

    final effectiveDevInfo = devInfo ?? (isOnline ? {
      'platform': 'Active Device',
      'browser': 'App/Web',
      'os': 'Online Session',
      'iconType': 'unknown',
      'isOnline': true,
    } : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isRevoked ? Colors.red.withValues(alpha: 0.05) : t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isRevoked ? Colors.red.withValues(alpha: 0.3) : t.bgRule, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: t.accent.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(itemId, branchId),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              // Avatar with online badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.accentMuted,
                      image: profilePicUrl != null && profilePicUrl.trim().isNotEmpty
                          ? DecorationImage(
                              image: (ImageUploadService.decodeBase64ToBytes(profilePicUrl) != null
                                  ? MemoryImage(ImageUploadService.decodeBase64ToBytes(profilePicUrl)!)
                                  : NetworkImage(profilePicUrl) as ImageProvider),
                              fit: BoxFit.cover,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(color: t.accent.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2)),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: profilePicUrl == null
                        ? Text(initials, style: TextStyle(color: t.accent, fontWeight: FontWeight.w900, fontSize: 14))
                        : null,
                  ),
                  if (isOnline)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.bgCard, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: isRevoked ? Colors.red.shade900 : t.textPrimary,
                              decoration: isRevoked ? TextDecoration.lineThrough : null,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            softWrap: true,
                          ),
                        ),
                        if (isOnline) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ONLINE',
                              style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        if (status != 'active' && status.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(color: _getStatusColor(status), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(fontSize: 11.5, color: t.textSecondary, fontWeight: FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (effectiveDevInfo != null) ...[
                      const SizedBox(height: 4),
                      DeviceBadgeWidget(
                        deviceInfo: effectiveDevInfo,
                        compact: true,
                      ),
                    ],
                  ],
                ),
              ),
              // Action buttons: Revoke/Archive on LEFT, Edit on RIGHT
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.isPatientMode) ...[
                    if (!isGuardianRole && _canManageUserAccess(data))
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isRevoked ? Colors.grey.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isRevoked ? Icons.key_rounded : Icons.no_accounts_rounded,
                            size: 16,
                            color: isRevoked ? Colors.grey.shade700 : Colors.red,
                          ),
                        ),
                        tooltip: isRevoked ? 'Update Access Status' : 'Revoke Access',
                        onPressed: () => _showQuickRevokeDialog(data, branchId, t),
                      )
                    else if (isGuardianRole && _canManageUserAccess(data))
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            size: 16,
                            color: Colors.teal,
                          ),
                        ),
                        tooltip: 'Update Student / Guardian Status',
                        onPressed: () => _showGuardianStatusDialog(data, branchId, t),
                      ),
                    if (_canManageUserAccess(data)) const SizedBox(width: 4),
                  ],
                  if (_canManageUserAccess(data))
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: t.accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.edit_rounded, size: 16, color: t.accent),
                      ),
                      tooltip: 'Edit Profile',
                      onPressed: () => _openDetail(itemId, branchId),
                    )
                  else
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(Icons.chevron_right_rounded, color: t.textSecondary, size: 20),
                      tooltip: 'View Profile',
                      onPressed: () => _openDetail(itemId, branchId),
                    ),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showGuardianStatusDialog(Map<String, dynamic> data, String branchId, RoleThemeData t) async {
    final itemId = (data['uid'] ?? data['id'] ?? data['docId'] ?? '').toString();
    final currentStatus = (data['status'] ?? data['studentStatus'] ?? 'active').toString().toLowerCase().trim();

    String selectedStatus = currentStatus;
    final reasonCtrl = TextEditingController();

    final statusOptions = [
      {'key': 'active', 'label': 'Active Student / Guardian', 'color': Colors.green, 'icon': Icons.check_circle_rounded},
      {'key': 'hifz_completed', 'label': 'Hifz Completed', 'color': const Color(0xFF4C4DDC), 'icon': Icons.workspace_premium_rounded},
      {'key': 'left', 'label': 'Left Madrassa', 'color': Colors.redAccent, 'icon': Icons.exit_to_app_rounded},
      {'key': 'dropped', 'label': 'Dropped Out', 'color': Colors.red, 'icon': Icons.person_off_rounded},
      {'key': 'archived', 'label': 'Archived', 'color': Colors.orange, 'icon': Icons.archive_rounded},
    ];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final currentOpt = statusOptions.firstWhere((o) => o['key'] == selectedStatus, orElse: () => statusOptions[0]);
          return Dialog(
            backgroundColor: t.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (currentOpt['color'] as Color).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(currentOpt['icon'] as IconData, color: currentOpt['color'] as Color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Madrassa Guardian Status',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: t.textPrimary),
                            ),
                            Text(
                              'Update enrolment status for @${data['username'] ?? 'Guardian'}',
                              style: TextStyle(fontSize: 12, color: t.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Select Student / Guardian Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary)),
                  const SizedBox(height: 8),
                  ...statusOptions.map((opt) {
                    final isSelected = selectedStatus == opt['key'];
                    final optColor = opt['color'] as Color;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? optColor.withValues(alpha: 0.1) : t.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? optColor : t.bgRule,
                          width: isSelected ? 1.5 : 0.8,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: Icon(opt['icon'] as IconData, color: optColor, size: 20),
                        title: Text(
                          opt['label'] as String,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? optColor : t.textPrimary,
                            fontSize: 13.5,
                          ),
                        ),
                        trailing: isSelected ? Icon(Icons.check_circle_rounded, color: optColor, size: 18) : null,
                        onTap: () => setS(() => selectedStatus = opt['key'] as String),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text('Remarks / Reason (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    style: TextStyle(fontSize: 13, color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. Completed Hifz exam / Relocated to another city',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: t.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentOpt['color'] as Color,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Update Status', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirm != true) return;

    final reason = reasonCtrl.text.trim();
    final isReadOnly = selectedStatus != 'active';

    final updates = <String, dynamic>{
      'status': selectedStatus,
      'studentStatus': selectedStatus,
      'accountStatus': selectedStatus,
      'isReadOnly': isReadOnly,
      'statusReason': reason.isNotEmpty ? reason : 'Status updated to $selectedStatus',
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await LocalStorageService.saveUserOffline(
        uid: itemId,
        branchId: branchId,
        userData: {...data, ...updates, 'uid': itemId, 'branchId': branchId},
      );

      if (!itemId.startsWith('local-')) {
        await FirebaseFirestore.instance.collection('users').doc(itemId).set(updates, SetOptions(merge: true));
        if (branchId.isNotEmpty && branchId != 'all') {
          await FirebaseFirestore.instance.collection('branches').doc(branchId).collection('users').doc(itemId).set(updates, SetOptions(merge: true));
        }
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guardian status updated to ${selectedStatus.replaceAll('_', ' ').toUpperCase()}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openDetail(String itemId, String branchId) {
    if (_localBox == null) return;
    String curRole = '';
    try {
      curRole = RoleThemeScope.dataOf(context).roleLabel;
    } catch (_) {}

    if (widget.isPatientMode) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PatientDetailScreen(
        patientId: itemId, isOnline: true, localBox: _localBox!,
        branchId: branchId, doctorId: '', isAdmin: true,
      )));
    } else {
      final roleData = RoleThemeScope.of(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => RoleThemeScope(
        role: roleData,
        child: UserDetailScreen(
          userId: itemId, branchId: branchId, localBox: _localBox!, isOnline: true,
          currentUserRole: curRole,
        ),
      )));
    }
  }

  bool _canManageUserAccess(Map<String, dynamic> targetData) {
    String actorRole = '';
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final currentMap = box.get('user_data') ?? box.get('currentUser') ?? box.get('active_user');
        if (currentMap is Map && currentMap['role'] != null) {
          actorRole = (currentMap['role'] as String).toLowerCase().trim();
        }
      }
    } catch (_) {}

    if (actorRole.isEmpty && _localBox != null) {
      try {
        final currentMap = _localBox!.get('user_data') ?? _localBox!.get('currentUser') ?? _localBox!.get('active_user');
        if (currentMap is Map && currentMap['role'] != null) {
          actorRole = (currentMap['role'] as String).toLowerCase().trim();
        }
      } catch (_) {}
    }

    if (actorRole.isEmpty && mounted) {
      try {
        final scope = context.dependOnInheritedWidgetOfExactType<RoleThemeScope>();
        if (scope != null) {
          actorRole = scope.role.name.toLowerCase().trim();
        }
      } catch (_) {}
    }

    // GOD MODE: Chairman role can edit, delete, or revoke ANY role at all (including CEO, HQ Manager, Admins, global roles, server, self)
    if (actorRole == 'chairman') {
      return true;
    }

    final actorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final targetUid = (targetData['uid'] ?? targetData['id'] ?? targetData['docId'] ?? '').toString();
    if (actorUid.isNotEmpty && targetUid.isNotEmpty && actorUid == targetUid) {
      return false;
    }

    final targetRole = (targetData['role'] as String? ?? '').toLowerCase().trim();

    // Rule 2: Server accounts protection for non-chairman
    if (targetRole == 'server' || targetRole.contains('server')) {
      return false;
    }

    // Rule 3: Non-chairman roles CANNOT manage Administration / Executive employees (HQ Manager, CEO, Admin, Chairman)
    final isTargetExecOrAdmin = targetRole == 'ceo' ||
        targetRole == 'hq manager' ||
        targetRole == 'hq_manager' ||
        targetRole == 'admin' ||
        targetRole == 'chairman' ||
        targetRole == 'administration';

    if (isTargetExecOrAdmin) {
      return false;
    }

    return true;
  }

  Future<void> _showQuickRevokeDialog(Map<String, dynamic> data, String branchId, RoleThemeData t) async {
    if (!_canManageUserAccess(data)) {
      final roleName = (data['role'] as String? ?? 'User').toUpperCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: You do not have permission to revoke or alter access for $roleName accounts.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }

    final itemId = (data['uid'] ?? data['id'] ?? data['docId'] ?? '').toString();
    final status = (data['status'] ?? data['accountStatus'] ?? 'active').toString().toLowerCase().trim();
    final isRevoked = status == 'inactive' ||
        status == 'suspended' ||
        status == 'terminated' ||
        status == 'resigned' ||
        status == 'retired' ||
        status == 'offboarded' ||
        status == 'revoked' ||
        data['isActive'] == false;

    String selectedCategory = isRevoked ? 'Active' : 'Resigned';
    final reasonCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final categories = ['Resigned', 'Terminated', 'Retired', 'Suspended', 'Offboarded', 'Inactive'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Dialog(
            backgroundColor: t.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isRevoked ? Colors.green : Colors.red).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isRevoked ? Icons.lock_open_rounded : Icons.no_accounts_rounded,
                          color: isRevoked ? Colors.green : Colors.red,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isRevoked ? 'Re-Enable App Access' : 'Revoke App Access',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: t.textPrimary),
                            ),
                            Text(
                              isRevoked
                                  ? 'Restore access for @${data['username'] ?? 'User'}'
                                  : 'Offboard @${data['username'] ?? 'User'}',
                              style: TextStyle(fontSize: 12, color: t.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (!isRevoked) ...[
                    Text('Revocation Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          isExpanded: true,
                          dropdownColor: t.bgCard,
                          style: TextStyle(fontSize: 14, color: t.textPrimary, fontWeight: FontWeight.w600),
                          items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (v) {
                            if (v != null) setS(() => selectedCategory = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(isRevoked ? 'Restoration Remarks (Optional)' : 'Reason / Remarks (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    style: TextStyle(fontSize: 13, color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: isRevoked ? 'e.g. Access restored by HQ Manager' : 'e.g. Resigned voluntarily / End of contract',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: t.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Admin Password Verification', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    style: TextStyle(fontSize: 13, color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter admin password',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: t.bg,
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: t.textTertiary, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (passwordCtrl.text != 'admin1122') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Wrong admin password'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          icon: Icon(isRevoked ? Icons.lock_open_rounded : Icons.lock_person_rounded, size: 16),
                          label: Text(isRevoked ? 'Restore' : 'Revoke'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRevoked ? Colors.green : Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirm != true) return;

    final reason = reasonCtrl.text.trim();
    final Map<String, dynamic> updates;

    if (isRevoked) {
      updates = <String, dynamic>{
        'status': 'active',
        'accountStatus': 'active',
        'isActive': true,
        'revocationReason': null,
        'revokedAt': null,
        'restoredAt': FieldValue.serverTimestamp(),
      };
    } else {
      updates = <String, dynamic>{
        'status': selectedCategory,
        'accountStatus': selectedCategory,
        'isActive': false,
        'revocationReason': reason.isNotEmpty ? reason : 'Access revoked by admin ($selectedCategory)',
        'revokedAt': FieldValue.serverTimestamp(),
      };
    }

    try {
      await LocalStorageService.saveUserOffline(
        uid: itemId,
        branchId: branchId,
        userData: {...data, ...updates, 'uid': itemId, 'branchId': branchId},
      );

      if (!itemId.startsWith('local-')) {
        await FirebaseFirestore.instance.collection('users').doc(itemId).set(updates, SetOptions(merge: true));
        if (branchId.isNotEmpty && branchId != 'all') {
          await FirebaseFirestore.instance.collection('branches').doc(branchId).collection('users').doc(itemId).set(updates, SetOptions(merge: true));
        }
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRevoked
                ? 'App access restored for @${data['username'] ?? 'User'}'
                : 'Access revoked for @${data['username'] ?? 'User'} ($selectedCategory)'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update access status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _emptyState(RoleThemeData t, IconData icon, String title, String subtitle, {bool isError = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: (isError ? Colors.red : t.accent).withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: isError ? Colors.red.shade400 : t.accent.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: t.textSecondary)),
        ]),
      ),
    );
  }

  // ── Family view ──

  Widget _buildFamilyView(List<Map<String, dynamic>> list, String branchId, RoleThemeData t) {
    Map<String, Map<String, dynamic>> cnicToGuardian = {};
    Map<String, List<Map<String, dynamic>>> families = {};
    List<Map<String, dynamic>> adultsWithoutChildren = [];

    for (var data in list) {
      if (data['isAdult'] == true) {
        final cnic = data['cnic'] as String? ?? '';
        if (cnic.isNotEmpty) cnicToGuardian[cnic] = data;
        adultsWithoutChildren.add(data);
      } else {
        final guardianCnic = data['guardianCnic'] as String? ?? 'Unknown';
        families.putIfAbsent(guardianCnic, () => []);
        families[guardianCnic]!.add(data);
      }
    }
    for (var gc in families.keys) {
      adultsWithoutChildren.removeWhere((a) => a['cnic'] == gc);
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
      children: [
        ...families.entries.map((entry) => _familyCard(
          t: t, guardianName: cnicToGuardian[entry.key]?['name'] ?? 'Unknown',
          guardianCnic: entry.key, guardian: cnicToGuardian[entry.key],
          children: entry.value, branchId: branchId,
        )),
        if (adultsWithoutChildren.isNotEmpty)
          _soloAdultsCard(adultsWithoutChildren, branchId, t),
      ],
    );
  }

  Widget _familyCard({required RoleThemeData t, required String guardianName,
      required String guardianCnic, required Map<String, dynamic>? guardian,
      required List<Map<String, dynamic>> children, required String branchId}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 0.8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: t.accentMuted, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.family_restroom_rounded, color: t.accent, size: 20)),
          title: Text(guardianName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: t.textPrimary)),
          subtitle: Text('${children.length} child${children.length != 1 ? 'ren' : ''}',
              style: TextStyle(fontSize: 11, color: t.textSecondary)),
          children: [
            if (guardian != null)
              _familyMemberTile(guardian, Icons.person_rounded, t.accent, branchId, t, isGuardian: true),
            ...children.map((c) => _familyMemberTile(c, Icons.child_care_rounded, Colors.orange.shade600, branchId, t)),
          ],
        ),
      ),
    );
  }

  Widget _familyMemberTile(Map<String, dynamic> data, IconData icon, Color color, String branchId, RoleThemeData t, {bool isGuardian = false}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data['name'] ?? 'N/A', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: t.textPrimary)),
          Text('${data['gender'] ?? 'N/A'} · ${data['age']?.toString() ?? '?'} yrs',
              style: TextStyle(fontSize: 11, color: t.textSecondary)),
        ])),
        GestureDetector(
          onTap: () => _openDetail(data['id'], branchId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text('View', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _soloAdultsCard(List<Map<String, dynamic>> adults, String branchId, RoleThemeData t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 0.8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: t.accentMuted, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.person_outline_rounded, color: t.accent, size: 20)),
          title: Text('Adults without Children', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: t.textPrimary)),
          subtitle: Text('${adults.length} individual${adults.length != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 11, color: t.textSecondary)),
          children: adults.map((a) => _familyMemberTile(a, Icons.person_rounded, t.accent, branchId, t)).toList(),
        ),
      ),
    );
  }

  // ── Stream ──

  Stream<QuerySnapshot> _getFilteredStream(String branchId, String collection) {
    if (collection == 'users') {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('users');
      if (branchId != 'all' && branchId != 'global') {
        q = q.where('branchId', isEqualTo: branchId);
      }
      return q.snapshots();
    }
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('branches').doc(branchId).collection(collection);
    if (widget.isPatientMode && _filterStatus != null) q = q.where('status', isEqualTo: _filterStatus);
    if (widget.isPatientMode && _genderFilter != null) q = q.where('gender', isEqualTo: _genderFilter);
    if (widget.isPatientMode && _ageFilter != null) {
      int min = 0, max = 200;
      if (_ageFilter == 'child') { max = 18; }
      else if (_ageFilter == 'adult') { min = 19; max = 60; }
      else if (_ageFilter == 'senior') { min = 61; }
      q = q.where('age', isGreaterThanOrEqualTo: min).where('age', isLessThanOrEqualTo: max);
    }
    return q.snapshots();
  }
}

// ─── Formatters ───────────────────────────────────────────────────────────────
class CNICInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if ((i == 4 || i == 11) && i != digits.length - 1) buffer.write('-');
    }
    return TextEditingValue(text: buffer.toString(), selection: TextSelection.collapsed(offset: buffer.length));
  }
}
