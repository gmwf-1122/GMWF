// lib/pages/school/views/school_student_management_view.dart

import 'package:flutter/material.dart';
import '../../../widgets/media_upload_tile.dart';
import '../dialogs/school_enrollment_dialog.dart';
import '../theme/school_theme.dart';
import '../models/school_student.dart';
import '../utils/school_local_storage.dart';
import '../constants/school_constants.dart';

class SchoolStudentManagementView extends StatefulWidget {
  final String branchId;

  const SchoolStudentManagementView({
    super.key,
    required this.branchId,
  });

  @override
  State<SchoolStudentManagementView> createState() => _SchoolStudentManagementViewState();
}

class _SchoolStudentManagementViewState extends State<SchoolStudentManagementView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedGradeFilter = 'All';
  String _selectedStatusFilter = 'All';

  final List<String> _gradeOptions = SchoolConstants.filterGrades;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openEnrollmentDialog([SchoolStudent? student]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SchoolEnrollmentDialog(
        branchId: widget.branchId,
        studentToEdit: student,
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search & Action Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              // Search Input
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search student by name or roll number...',
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6366F1)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Grade Filter
              DropdownButtonHideUnderline(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedGradeFilter,
                    items: _gradeOptions.map((g) {
                      return DropdownMenuItem(value: g, child: Text('Grade: $g'));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedGradeFilter = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Status Filter
              DropdownButtonHideUnderline(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedStatusFilter,
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('Status: All')),
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'graduated', child: Text('Graduated')),
                      DropdownMenuItem(value: 'dropped', child: Text('Dropped')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedStatusFilter = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Add Student Button
              ElevatedButton.icon(
                onPressed: () => _openEnrollmentDialog(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Admission'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Students Grid/List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: SchoolLocalStorage.streamStudentsCached(widget.branchId),
            builder: (context, snapshot) {
              final rawList = snapshot.data ?? [];
              final query = _searchCtrl.text.trim().toLowerCase();

              var filtered = rawList.map((m) => SchoolStudent.fromMap(m['id'] ?? '', m)).toList();

              if (query.isNotEmpty) {
                filtered = filtered.where((s) {
                  return s.name.toLowerCase().contains(query) ||
                      s.rollNo.toLowerCase().contains(query) ||
                      s.guardianName.toLowerCase().contains(query);
                }).toList();
              }

              if (_selectedGradeFilter != 'All') {
                filtered = filtered.where((s) => s.grade == _selectedGradeFilter).toList();
              }

              if (_selectedStatusFilter != 'All') {
                filtered = filtered.where((s) => s.status == _selectedStatusFilter).toList();
              }

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text(
                        'No school students found',
                        style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Click "+ New Admission" to add your first student.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final student = filtered[index];
                  return _buildStudentTile(student);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showStudentDocumentsDialog(SchoolStudent student) {
    int docCount = (student.photoUrl.isNotEmpty ? 1 : 0) +
        (student.guardianCnicUrl.isNotEmpty ? 1 : 0) +
        (student.bformUrl.isNotEmpty ? 1 : 0) +
        student.additionalDocuments.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.folder_shared_rounded, color: Color(0xFF6366F1)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Student Documents ($docCount) — ${student.name}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (student.photoUrl.isNotEmpty) ...[
                  const Text('Student Profile Photo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  MediaUploadTile(label: 'Student Photo', icon: Icons.person_outlined, initialValue: student.photoUrl, readOnly: true),
                  const SizedBox(height: 12),
                ],
                if (student.guardianCnicUrl.isNotEmpty) ...[
                  const Text('Guardian CNIC / ID Card:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  MediaUploadTile(label: 'Guardian CNIC', icon: Icons.badge_outlined, isDocument: true, initialValue: student.guardianCnicUrl, readOnly: true),
                  const SizedBox(height: 12),
                ],
                if (student.bformUrl.isNotEmpty) ...[
                  const Text('B-Form / Birth Certificate:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  MediaUploadTile(label: 'B-Form Document', icon: Icons.description_outlined, isDocument: true, initialValue: student.bformUrl, readOnly: true),
                  const SizedBox(height: 12),
                ],
                if (student.additionalDocuments.isNotEmpty) ...[
                  const Text('Custom Documents:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  ...student.additionalDocuments.map((doc) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: MediaUploadTile(
                          label: doc['name'] ?? 'Document',
                          icon: Icons.file_present_rounded,
                          isDocument: true,
                          initialValue: doc['url'],
                          readOnly: true,
                        ),
                      )),
                ],
                if (docCount == 0)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('No documents uploaded for this student yet.', style: TextStyle(color: Colors.grey))),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildStudentTile(SchoolStudent student) {
    Color statusColor = const Color(0xFF10B981);
    if (student.status == 'graduated') statusColor = const Color(0xFF3B82F6);
    if (student.status == 'dropped') statusColor = const Color(0xFFEF4444);

    int docCount = (student.photoUrl.isNotEmpty ? 1 : 0) +
        (student.guardianCnicUrl.isNotEmpty ? 1 : 0) +
        (student.bformUrl.isNotEmpty ? 1 : 0) +
        student.additionalDocuments.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Roll No Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
            child: Text(
              student.rollNo.isNotEmpty ? student.rollNo : 'N/A',
              style: const TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Name & Grade
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: SchoolTheme.getGradeColor(student.grade).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        student.grade,
                        style: TextStyle(
                          color: SchoolTheme.getGradeColor(student.grade),
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sec ${student.section} • ${student.academicGroup}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Guardian Info
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guardian: ${student.guardianName}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Phone: ${student.guardianPhone}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              student.status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Documents Viewer Icon
          IconButton(
            tooltip: 'View Student Documents ($docCount)',
            icon: Badge(
              label: Text('$docCount'),
              isLabelVisible: docCount > 0,
              child: const Icon(Icons.folder_shared_rounded, color: Color(0xFF6366F1)),
            ),
            onPressed: () => _showStudentDocumentsDialog(student),
          ),

          // Edit Action Button
          IconButton(
            tooltip: 'Edit Profile & Admission',
            icon: const Icon(Icons.edit_rounded, color: Color(0xFF64748B)),
            onPressed: () => _openEnrollmentDialog(student),
          ),
        ],
      ),
    );
  }
}
