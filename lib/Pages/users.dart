// lib/pages/users.dart — COMPLETE REDESIGN

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:flutter/services.dart';
import 'patient_detail_screen.dart';
import 'user_detail_screen.dart';
import 'package:intl/intl.dart';
import 'dart:async';

// ─── Shared Design Tokens ────────────────────────────────────────────────────
class _DS {
  // Patient (teal) palette
  static const teal800 = Color(0xFF00514A);
  static const teal600 = Color(0xFF00796B);
  static const teal400 = Color(0xFF26A69A);
  static const tealBg  = Color(0xFFE0F2F1);

  // Staff (indigo) palette
  static const indigo800 = Color(0xFF1A237E);
  static const indigo600 = Color(0xFF3949AB);
  static const indigo400 = Color(0xFF5C6BC0);
  static const indigoBg  = Color(0xFFE8EAF6);

  // Neutrals
  static const bg       = Color(0xFFF5F6FA);
  static const surface  = Color(0xFFFFFFFF);
  static const ink      = Color(0xFF1C1F26);
  static const inkMid   = Color(0xFF5A6072);
  static const inkLight = Color(0xFFADB5BD);
  static const divider  = Color(0xFFE9ECEF);

  static const radius = 16.0;
  static const radiusLg = 22.0;
}

class UsersScreen extends StatefulWidget {
  final bool isPatientMode;
  const UsersScreen({super.key, this.isPatientMode = false});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with SingleTickerProviderStateMixin {
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

  Color get _primary => widget.isPatientMode ? _DS.teal600 : _DS.indigo600;
  Color get _dark    => widget.isPatientMode ? _DS.teal800 : _DS.indigo800;
  Color get _light   => widget.isPatientMode ? _DS.tealBg  : _DS.indigoBg;

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
      final branches = snap.docs.map((d) {
        final data = d.data();
        return {'id': d.id, 'name': data['name'] as String? ?? d.id};
      }).toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      setState(() {
        _branches = branches;
        _tabController = TabController(length: branches.length, vsync: this);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load branches: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
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
    if (_branches.isEmpty || _tabController == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _primary),
            const SizedBox(height: 16),
            Text('Loading branches…', style: TextStyle(color: _DS.inkMid, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Tab bar ──────────────────────────────────────────────
        Container(
          color: _DS.surface,
          child: TabBar(
            controller: _tabController!,
            isScrollable: true,
            labelColor: _primary,
            unselectedLabelColor: _DS.inkLight,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(color: _primary, width: 3),
              insets: const EdgeInsets.symmetric(horizontal: 12),
            ),
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: _branches.map((b) => Tab(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(b['name'] as String),
              ),
            )).toList(),
          ),
        ),

        // ── Search + Filter bar ───────────────────────────────────
        _buildFilterBar(),

        // ── Content ───────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController!,
            children: _branches.map((b) => _buildList(b['id'] as String)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: _DS.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          // Search row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: _DS.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _DS.divider),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    style: const TextStyle(fontSize: 14, color: _DS.ink),
                    decoration: InputDecoration(
                      hintText: widget.isPatientMode
                          ? 'Search name, CNIC, phone, UID…'
                          : 'Search by username…',
                      hintStyle: TextStyle(color: _DS.inkLight, fontSize: 13),
                      prefixIcon: Icon(Icons.search_rounded, color: _primary, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Filter toggle
              GestureDetector(
                onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _filtersExpanded ? _primary : _DS.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _filtersExpanded ? _primary : _DS.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          color: _filtersExpanded ? Colors.white : _DS.inkMid, size: 18),
                      const SizedBox(width: 6),
                      Text('Filters',
                          style: TextStyle(
                            color: _filtersExpanded ? Colors.white : _DS.inkMid,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Expandable filters
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _filtersExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: widget.isPatientMode ? _buildPatientFilters() : _buildStaffFilters(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientFilters() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _filterChipGroup(
          label: 'Status',
          value: _filterStatus,
          icon: Icons.mosque_rounded,
          options: {'Zakat': 'Zakat', 'Non-Zakat': 'Non-Zakat', 'GMWF': 'GMWF'},
          onChanged: (v) => setState(() => _filterStatus = v),
        ),
        _filterChipGroup(
          label: 'Gender',
          value: _genderFilter,
          icon: Icons.wc_rounded,
          options: {'Male': 'Male', 'Female': 'Female', 'Other': 'Other'},
          onChanged: (v) => setState(() => _genderFilter = v),
        ),
        _filterChipGroup(
          label: 'Age',
          value: _ageFilter,
          icon: Icons.cake_rounded,
          options: {'child': '0–18', 'adult': '19–60', 'senior': '61+'},
          onChanged: (v) => setState(() => _ageFilter = v),
        ),
        // Family view toggle chip
        GestureDetector(
          onTap: () => setState(() => _familyView = !_familyView),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _familyView ? _primary : _DS.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _familyView ? _primary : _DS.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.family_restroom_rounded,
                    color: _familyView ? Colors.white : _DS.inkMid, size: 16),
                const SizedBox(width: 6),
                Text('Family View',
                    style: TextStyle(
                      color: _familyView ? Colors.white : _DS.inkMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStaffFilters() {
    return _filterChipGroup(
      label: 'Role',
      value: _roleFilter,
      icon: Icons.badge_outlined,
      options: {
        'doctor': 'Doctor',
        'receptionist': 'Receptionist',
        'dispenser': 'Dispenser',
        'supervisor': 'Supervisor',
        'food token generator': 'Food Token',
        'kitchen': 'Kitchen',
      },
      onChanged: (v) => setState(() => _roleFilter = v),
    );
  }

  Widget _filterChipGroup({
    required String label,
    required String? value,
    required IconData icon,
    required Map<String, String> options,
    required Function(String?) onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // "All" chip
        GestureDetector(
          onTap: () => onChanged(null),
          child: _chip('All $label', value == null, icon),
        ),
        ...options.entries.map((e) => GestureDetector(
              onTap: () => onChanged(value == e.key ? null : e.key),
              child: _chip(e.value, value == e.key, icon),
            )),
      ],
    );
  }

  Widget _chip(String label, bool active, IconData icon) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? _primary : _DS.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? _primary : _DS.divider),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : _DS.inkMid,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── List ──────────────────────────────────────────────────────

  Widget _buildList(String branchId) {
    final collection = widget.isPatientMode ? 'patients' : 'users';
    return StreamBuilder<QuerySnapshot>(
      stream: _getFilteredStream(branchId, collection),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _emptyState(Icons.error_outline_rounded, 'Something went wrong', '${snapshot.error}', isError: true);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: _primary));
        }

        var docs = snapshot.data!.docs;

        if (_searchQuery.isNotEmpty) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (widget.isPatientMode) {
              final name = (data['name'] as String?)?.toLowerCase() ?? '';
              final phone = data['phone'] as String? ?? '';
              final cnic = data['cnic'] as String? ?? '';
              final guardianCnic = data['guardianCnic'] as String? ?? '';
              final uid = doc.id.toLowerCase();
              return name.contains(_searchQuery) || phone.contains(_searchQuery) ||
                  cnic.contains(_searchQuery) || guardianCnic.contains(_searchQuery) ||
                  uid.contains(_searchQuery);
            } else {
              return ((data['username'] as String?)?.toLowerCase() ?? '').contains(_searchQuery);
            }
          }).toList();
        }

        docs.sort((a, b) {
          final da = a.data() as Map<String, dynamic>;
          final db = b.data() as Map<String, dynamic>;
          final key = widget.isPatientMode ? 'name' : 'username';
          return (da[key] as String? ?? '').compareTo(db[key] as String? ?? '');
        });

        if (docs.isEmpty) {
          return _emptyState(
            widget.isPatientMode ? Icons.person_search_rounded : Icons.manage_accounts_rounded,
            'No ${widget.isPatientMode ? 'patients' : 'users'} found',
            'Try adjusting your search or filters',
          );
        }

        return Column(
          children: [
            // Count bar
            Container(
              color: _light.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.isPatientMode ? Icons.people_rounded : Icons.badge_rounded,
                            color: _primary, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          '${docs.length} ${widget.isPatientMode ? 'Patients' : 'Users'}',
                          style: TextStyle(
                              color: _primary, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.isPatientMode && _familyView
                  ? _buildFamilyView(docs, branchId)
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) => _buildCard(docs[i], branchId),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard(QueryDocumentSnapshot doc, String branchId) {
    final data = doc.data() as Map<String, dynamic>;
    final itemId = doc.id;
    final profilePicUrl = data['profilePictureUrl'] as String?;
    final name = widget.isPatientMode
        ? (data['name'] ?? 'Unknown') as String
        : (data['username'] ?? 'Unknown') as String;
    final subtitle = widget.isPatientMode
        ? '${data['gender'] ?? 'N/A'} · ${data['age']?.toString() ?? '?'} yrs · ${data['status'] ?? ''}'
        : (data['role'] as String? ?? 'N/A').toUpperCase();

    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(_DS.radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_DS.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_DS.radius),
          onTap: () => _openDetail(itemId, branchId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _light,
                    image: profilePicUrl != null
                        ? DecorationImage(image: NetworkImage(profilePicUrl), fit: BoxFit.cover)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: profilePicUrl == null
                      ? Text(initials,
                          style: TextStyle(color: _primary, fontWeight: FontWeight.w800, fontSize: 16))
                      : null,
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: _DS.ink)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: const TextStyle(fontSize: 12, color: _DS.inkMid)),
                    ],
                  ),
                ),
                // View button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_forward_ios_rounded, color: _primary, size: 13),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDetail(String itemId, String branchId) {
    if (_localBox == null) return;
    if (widget.isPatientMode) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => PatientDetailScreen(
          patientId: itemId, isOnline: true, localBox: _localBox!,
          branchId: branchId, doctorId: '', isAdmin: true,
        ),
      ));
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => UserDetailScreen(
          userId: itemId, branchId: branchId, localBox: _localBox!, isOnline: true,
        ),
      ));
    }
  }

  Widget _emptyState(IconData icon, String title, String subtitle, {bool isError = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (isError ? Colors.red : _primary).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: isError ? Colors.red.shade400 : _primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _DS.ink)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _DS.inkMid)),
          ],
        ),
      ),
    );
  }

  // ── Family view ───────────────────────────────────────────────

  Widget _buildFamilyView(List<QueryDocumentSnapshot> docs, String branchId) {
    Map<String, Map<String, dynamic>> cnicToGuardian = {};
    Map<String, List<Map<String, dynamic>>> families = {};
    List<Map<String, dynamic>> adultsWithoutChildren = [];

    for (var doc in docs) {
      final data = {...doc.data() as Map<String, dynamic>, 'id': doc.id};
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
    families.keys.forEach((gc) {
      adultsWithoutChildren.removeWhere((a) => a['cnic'] == gc);
    });

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        ...families.entries.map((entry) {
          final guardian = cnicToGuardian[entry.key];
          final children = entry.value;
          final guardianName = guardian?['name'] ?? 'Unknown';

          return _familyCard(
            guardianName: guardianName,
            guardianCnic: entry.key,
            guardian: guardian,
            children: children,
            branchId: branchId,
          );
        }),
        if (adultsWithoutChildren.isNotEmpty)
          _soloAdultsCard(adultsWithoutChildren, branchId),
      ],
    );
  }

  Widget _familyCard({
    required String guardianName,
    required String guardianCnic,
    required Map<String, dynamic>? guardian,
    required List<Map<String, dynamic>> children,
    required String branchId,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _light, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.family_restroom_rounded, color: _primary, size: 22),
          ),
          title: Text(guardianName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _DS.ink)),
          subtitle: Text(
            '${children.length} child${children.length != 1 ? 'ren' : ''} · CNIC: $guardianCnic',
            style: const TextStyle(fontSize: 12, color: _DS.inkMid),
          ),
          children: [
            if (guardian != null)
              _familyMemberTile(guardian, Icons.person_rounded, _primary, branchId, isGuardian: true),
            ...children.map((c) => _familyMemberTile(c, Icons.child_care_rounded, Colors.orange.shade600, branchId)),
          ],
        ),
      ),
    );
  }

  Widget _familyMemberTile(Map<String, dynamic> data, IconData icon, Color color, String branchId, {bool isGuardian = false}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'] ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _DS.ink)),
                Text('${data['gender'] ?? 'N/A'} · ${data['age']?.toString() ?? '?'} yrs',
                    style: const TextStyle(fontSize: 11, color: _DS.inkMid)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _openDetail(data['id'], branchId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('View', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _soloAdultsCard(List<Map<String, dynamic>> adults, String branchId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.person_outline_rounded, color: Colors.purple.shade600, size: 22),
          ),
          title: Text('Adults without Children',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _DS.ink)),
          subtitle: Text('${adults.length} individual${adults.length != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, color: _DS.inkMid)),
          children: adults
              .map((a) => _familyMemberTile(a, Icons.person_rounded, Colors.purple.shade600, branchId))
              .toList(),
        ),
      ),
    );
  }

  // ── Stream ────────────────────────────────────────────────────

  Stream<QuerySnapshot> _getFilteredStream(String branchId, String collection) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('branches').doc(branchId).collection(collection);

    if (widget.isPatientMode && _filterStatus != null)
      q = q.where('status', isEqualTo: _filterStatus);
    if (widget.isPatientMode && _genderFilter != null)
      q = q.where('gender', isEqualTo: _genderFilter);
    if (widget.isPatientMode && _ageFilter != null) {
      int min = 0, max = 200;
      if (_ageFilter == 'child') { max = 18; }
      else if (_ageFilter == 'adult') { min = 19; max = 60; }
      else if (_ageFilter == 'senior') { min = 61; }
      q = q.where('age', isGreaterThanOrEqualTo: min).where('age', isLessThanOrEqualTo: max);
    }
    if (!widget.isPatientMode && _roleFilter != null)
      q = q.where('role', isEqualTo: _roleFilter);

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
    return TextEditingValue(
        text: buffer.toString(), selection: TextSelection.collapsed(offset: buffer.length));
  }
}

class _DobFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) {
    var t = newVal.text.replaceAll(RegExp(r'\D'), '');
    if (t.length > 8) t = t.substring(0, 8);
    final b = StringBuffer();
    for (int i = 0; i < t.length; i++) {
      if (i == 2 || i == 4) b.write('-');
      b.write(t[i]);
    }
    return TextEditingValue(text: b.toString(), selection: TextSelection.collapsed(offset: b.length));
  }
}