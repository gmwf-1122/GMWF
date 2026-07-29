// lib/pages/school/views/school_teacher_management_view.dart

import 'package:flutter/material.dart';
import '../../../widgets/media_upload_tile.dart';
import '../dialogs/school_teacher_dialog.dart';
import '../models/school_teacher.dart';
import '../utils/school_local_storage.dart';

class SchoolTeacherManagementView extends StatefulWidget {
  final String branchId;

  const SchoolTeacherManagementView({
    super.key,
    required this.branchId,
  });

  @override
  State<SchoolTeacherManagementView> createState() => _SchoolTeacherManagementViewState();
}

class _SchoolTeacherManagementViewState extends State<SchoolTeacherManagementView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openTeacherDialog([SchoolTeacher? teacher]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SchoolTeacherDialog(
        branchId: widget.branchId,
        teacherToEdit: teacher,
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
        // Search & Action Toolbar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search teacher by name, employee ID, or subject...',
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF10B981)),
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
              const SizedBox(width: 16),

              ElevatedButton.icon(
                onPressed: () => _openTeacherDialog(),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Register Teacher'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Teacher List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: SchoolLocalStorage.streamTeachersCached(widget.branchId),
            builder: (context, snapshot) {
              final rawList = snapshot.data ?? [];
              final query = _searchCtrl.text.trim().toLowerCase();

              var teachers = rawList.map((m) => SchoolTeacher.fromMap(m['id'] ?? '', m)).toList();

              if (query.isNotEmpty) {
                teachers = teachers.where((t) {
                  return t.name.toLowerCase().contains(query) ||
                      t.employeeId.toLowerCase().contains(query) ||
                      t.subjects.any((s) => s.toLowerCase().contains(query));
                }).toList();
              }

              if (teachers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text(
                        'No teachers registered yet',
                        style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Click "+ Register Teacher" to add your school staff.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: teachers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final teacher = teachers[index];
                  return _buildTeacherCard(teacher);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showTeacherDocumentsDialog(SchoolTeacher teacher) {
    int docCount = (teacher.photoUrl.isNotEmpty ? 1 : 0) +
        (teacher.cnicUrl.isNotEmpty ? 1 : 0) +
        teacher.additionalDocuments.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.folder_shared_rounded, color: Color(0xFF10B981)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Faculty Documents ($docCount) — ${teacher.name}',
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
                if (teacher.photoUrl.isNotEmpty) ...[
                  const Text('Faculty Profile Photo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  MediaUploadTile(label: 'Faculty Photo', icon: Icons.account_box_outlined, initialValue: teacher.photoUrl, readOnly: true),
                  const SizedBox(height: 12),
                ],
                if (teacher.cnicUrl.isNotEmpty) ...[
                  const Text('CNIC / ID Card Document:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  MediaUploadTile(label: 'Faculty CNIC', icon: Icons.badge_outlined, isDocument: true, initialValue: teacher.cnicUrl, readOnly: true),
                  const SizedBox(height: 12),
                ],
                if (teacher.additionalDocuments.isNotEmpty) ...[
                  const Text('Custom Documents:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  ...teacher.additionalDocuments.map((doc) => Padding(
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
                    child: Center(child: Text('No documents uploaded for this faculty member yet.', style: TextStyle(color: Colors.grey))),
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

  Widget _buildTeacherCard(SchoolTeacher teacher) {
    int docCount = (teacher.photoUrl.isNotEmpty ? 1 : 0) +
        (teacher.cnicUrl.isNotEmpty ? 1 : 0) +
        teacher.additionalDocuments.length;

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
          // Teacher Icon Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.1),
            child: const Icon(Icons.record_voice_over_rounded, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      teacher.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        teacher.employeeId,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (teacher.isHomeroom) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Class Incharge: ${teacher.homeroomClass}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF4338CA), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${teacher.designation} (${teacher.department}) • ${teacher.qualification}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),

          // Assigned Classes & Subjects
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (teacher.assignedGrades.isNotEmpty)
                  Text(
                    'Classes: ${teacher.assignedGrades.join(", ")}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                  ),
                const SizedBox(height: 2),
                if (teacher.subjects.isNotEmpty)
                  Text(
                    'Subjects: ${teacher.subjects.join(", ")}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),

          // Phone
          Text(
            teacher.phone,
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          const SizedBox(width: 8),

          // Documents Viewer Icon
          IconButton(
            tooltip: 'View Faculty Documents ($docCount)',
            icon: Badge(
              label: Text('$docCount'),
              isLabelVisible: docCount > 0,
              child: const Icon(Icons.folder_shared_rounded, color: Color(0xFF10B981)),
            ),
            onPressed: () => _showTeacherDocumentsDialog(teacher),
          ),

          // Edit Button
          IconButton(
            tooltip: 'Edit Faculty Details',
            icon: const Icon(Icons.edit_rounded, color: Color(0xFF64748B)),
            onPressed: () => _openTeacherDialog(teacher),
          ),
        ],
      ),
    );
  }
}
