// lib/pages/users.dart — Role-Theme Aware + Full Mobile Responsive

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'dispensary/patient_detail_screen.dart';
import 'user_detail_screen.dart';
import 'dart:async';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';
import '../services/local_storage_service.dart';

class UsersScreen extends StatefulWidget {
  final bool isPatientMode;
  final String? branchId;
  const UsersScreen({super.key, this.isPatientMode = false, this.branchId});

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

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.textPrimary, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isPatientMode ? 'Patients' : 'Staff',
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
    final isMobile = MediaQuery.of(context).size.width < 600;
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
                  hintText: widget.isPatientMode ? 'Search records…' : 'Search by username…',
                  hintStyle: TextStyle(color: t.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: t.accent, size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
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
        if (snapshot.hasError) {
          return _emptyState(t, Icons.error_outline_rounded, 'Something went wrong', '${snapshot.error}', isError: true);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: t.accent));
        }

        var docs = snapshot.data!.docs;

        if (_searchQuery.isNotEmpty) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return ((data['username'] as String?)?.toLowerCase() ?? '').contains(_searchQuery);
          }).toList();
        }

        var list = docs.map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>}).toList();
        list.sort((a, b) => (a['username'] as String? ?? '').compareTo(b['username'] as String? ?? ''));

        if (list.isEmpty) {
          return _emptyState(t, Icons.manage_accounts_rounded, 'No users found', 'Try adjusting your search or filters');
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
                  Icon(Icons.badge_rounded, color: t.accent, size: 14),
                  const SizedBox(width: 5),
                  Text('${list.length} Users', style: TextStyle(color: t.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
              itemCount: list.length,
              itemBuilder: (ctx, i) => _buildCard(list[i], branchId, t),
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildCard(Map<String, dynamic> data, String branchId, RoleThemeData t) {
    final itemId = data['patientId'] ?? data['id'] ?? '';
    final profilePicUrl = data['profilePictureUrl'] as String?;
    final name = widget.isPatientMode
        ? (data['name'] ?? 'Unknown') as String
        : (data['username'] ?? 'Unknown') as String;
    final subtitle = widget.isPatientMode
        ? '${data['gender'] ?? 'N/A'} · ${data['age']?.toString() ?? '?'} yrs · ${data['status'] ?? ''}'
        : (data['role'] as String? ?? 'N/A').toUpperCase();

    final initials = name.trim().isEmpty ? '?' :
        name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 0.8),
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
              // Avatar
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.accentMuted,
                  image: profilePicUrl != null
                      ? DecorationImage(image: NetworkImage(profilePicUrl), fit: BoxFit.cover)
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
              const SizedBox(width: 14),
              // Info
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: t.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 11.5, color: t.textSecondary, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              // Status Indicator or Arrow
              Icon(Icons.chevron_right_rounded, color: t.accent.withValues(alpha: 0.4), size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  void _openDetail(String itemId, String branchId) {
    if (_localBox == null) return;
    if (widget.isPatientMode) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PatientDetailScreen(
        patientId: itemId, isOnline: true, localBox: _localBox!,
        branchId: branchId, doctorId: '', isAdmin: true,
      )));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => UserDetailScreen(
        userId: itemId, branchId: branchId, localBox: _localBox!, isOnline: true,
      )));
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
    if (!widget.isPatientMode && _roleFilter != null) q = q.where('role', isEqualTo: _roleFilter);
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
