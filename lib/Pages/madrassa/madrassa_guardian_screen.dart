// lib/pages/madrassa/madrassa_guardian_screen.dart
//
// FIXES:
//  • Global-level admin/staff (non-guardian) now sees a student picker
//    dialog first when viewing the guardian portal, then renders the
//    ParentReportCard for the selected student — exactly like a guardian would see.
//  • Regular guardians continue to work as before (their linked studentIds).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'widgets/parent_report_card.dart';
import '../../services/offline_auth_service.dart';
import '../login_page.dart';

class MadrassaGuardianScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const MadrassaGuardianScreen({super.key, required this.userData});

  @override
  State<MadrassaGuardianScreen> createState() =>
      _MadrassaGuardianScreenState();
}

class _MadrassaGuardianScreenState extends State<MadrassaGuardianScreen> {
  int _selectedIndex = 0;

  // For admin preview — the student they picked from the dialog
  String? _adminPreviewStudentId;
  Map<String, dynamic>? _adminPreviewStudentData;

  Future<void> _logout() async {
    try {
      await OfflineAuthService.clearCredentials();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (r) => false,
        );
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  Future<List<DocumentSnapshot>> _fetchStudents(
      String branchId, List<String> ids) {
    return Future.wait(ids.map((id) => FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('madrassa_students')
        .doc(id)
        .get()));
  }

  bool _isAdminViewing() {
    final role = (widget.userData['role'] as String? ?? '').toLowerCase();
    return role != 'madrassa guardian';
  }

  Future<void> _showStudentPickerDialog(String branchId) async {
    final snap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('madrassa_students')
        .where('status', isEqualTo: 'active')
        .get();

    if (!mounted) return;

    final students = snap.docs
      ..sort((a, b) => (a['rollNumber'] ?? '').compareTo(b['rollNumber'] ?? ''));

    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active students found.')));
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF4C4DDC).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.person_search_rounded, color: Color(0xFF4C4DDC), size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Guardian Portal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A1C1E))),
                        Text('Select student to preview', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: students.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = students[i];
                    final d = s.data();
                    return InkWell(
                      onTap: () {
                        setState(() { _adminPreviewStudentId = s.id; _adminPreviewStudentData = d; });
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FD),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE0E2E7)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF4C4DDC),
                              child: Text(d['name']?[0] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text('Roll: ${d['rollNumber'] ?? "?"} • Guardian: ${d['guardianName'] ?? "?"}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Color(0xFF4C4DDC)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () { Navigator.pop(ctx); _logout(); },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('Logout', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchId = widget.userData['branchId'] as String? ?? '';
    if (branchId.isEmpty) return _EmptyState(onLogout: _logout, message: 'Branch missing');

    if (_isAdminViewing()) {
      if (_adminPreviewStudentId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (_adminPreviewStudentId == null && mounted) _showStudentPickerDialog(branchId); });
        return _LoadingScreen();
      }
      return Stack(
        children: [
          ParentReportCard(branchId: branchId, studentId: _adminPreviewStudentId!, studentData: _adminPreviewStudentData!, onLogout: _logout),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _AdminStudentSwitchButton(onTap: () => _showStudentPickerDialog(branchId), studentName: _adminPreviewStudentData?['name'] ?? ''),
          ),
        ],
      );
    }

    final dynamic rawIds = widget.userData['studentIds'] ?? widget.userData['studentId'];
    final List<String> studentIds = rawIds is List ? List<String>.from(rawIds) : (rawIds is String && rawIds.isNotEmpty ? [rawIds] : []);

    if (studentIds.isEmpty) return _EmptyState(onLogout: _logout);

    return FutureBuilder<List<DocumentSnapshot>>(
      future: _fetchStudents(branchId, studentIds),
      builder: (context, allSnap) {
        final allDocs = allSnap.data ?? [];
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('branches').doc(branchId).collection('madrassa_students').doc(studentIds[_selectedIndex]).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return _EmptyState(onLogout: _logout, message: 'Error loading data');
            if (snap.connectionState == ConnectionState.waiting) return _LoadingScreen();
            if (!snap.hasData || !snap.data!.exists) return _EmptyState(onLogout: _logout);
            final studentData = snap.data!.data() as Map<String, dynamic>;
            return Stack(
              children: [
                ParentReportCard(branchId: branchId, studentId: studentIds[_selectedIndex], studentData: studentData, onLogout: _logout),
                if (studentIds.length > 1)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 12,
                    child: _StudentSwitcher(allDocs: allDocs, studentIds: studentIds, selectedIndex: _selectedIndex, onChanged: (i) => setState(() => _selectedIndex = i)),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AdminStudentSwitchButton extends StatelessWidget {
  final VoidCallback onTap;
  final String studentName;
  const _AdminStudentSwitchButton({required this.onTap, required this.studentName});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4C4DDC),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF4C4DDC).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(studentName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF4C4DDC))),
    );
  }
}

class _StudentSwitcher extends StatelessWidget {
  final List<DocumentSnapshot> allDocs;
  final List<String> studentIds;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _StudentSwitcher({required this.allDocs, required this.studentIds, required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF4C4DDC),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF4C4DDC).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: DropdownButton<int>(
        value: selectedIndex,
        dropdownColor: const Color(0xFF4C4DDC),
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
        items: List.generate(studentIds.length, (i) {
          String name = 'Student ${i + 1}';
          if (allDocs.length > i && allDocs[i].exists) name = (allDocs[i].data() as Map<String, dynamic>)['name'] ?? name;
          return DropdownMenuItem(value: i, child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)));
        }),
        onChanged: (v) => onChanged(v!),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onLogout;
  final String? message;
  const _EmptyState({required this.onLogout, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_off_rounded, size: 64, color: Color(0xFF4C4DDC)),
              const SizedBox(height: 24),
              const Text('Account Not Linked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message ?? 'Your account is not linked to any student.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onLogout,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C4DDC), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Back to Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}