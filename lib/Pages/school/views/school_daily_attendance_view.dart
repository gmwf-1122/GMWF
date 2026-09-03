// lib/pages/school/views/school_daily_attendance_view.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../services/image_upload_service.dart';
import '../theme/school_theme.dart';
import '../utils/school_local_storage.dart';
import '../constants/school_constants.dart';

class SchoolDailyAttendanceView extends StatefulWidget {
  final String branchId;
  final String editorName;
  final String userRole;

  const SchoolDailyAttendanceView({
    super.key,
    required this.branchId,
    this.editorName = 'School Admin',
    this.userRole = 'School Admin',
  });

  @override
  State<SchoolDailyAttendanceView> createState() => _SchoolDailyAttendanceViewState();
}

class _SchoolDailyAttendanceViewState extends State<SchoolDailyAttendanceView> {
  DateTime _selectedDate = DateTime.now();
  String _selectedGradeFilter = 'All';
  bool _isSaving = false;
  final Map<String, Map<String, dynamic>> _localChanges = {};
  bool? _localAllowStudentLeave;

  final List<String> _gradeOptions = SchoolConstants.filterGrades;

  bool _isGlobalLevelUser(String role) {
    final r = role.toLowerCase().trim();
    return r == 'chairman' ||
        r == 'ceo' ||
        r == 'hq_manager' ||
        r == 'hq manager' ||
        r == 'superadmin' ||
        r == 'super_admin' ||
        r == 'global_admin' ||
        r == 'global admin' ||
        r == 'admin';
  }

  Future<bool> _confirmDiscardChanges() async {
    if (_localChanges.isEmpty) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 10),
            Text('Unsaved Attendance Edits'),
          ],
        ),
        content: const Text(
          'You have unsaved attendance edits for this date. If you leave now, these changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay & Continue Editing'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard Changes'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Check teacher homeroom permissions
    final r = widget.userRole.toLowerCase().trim();
    final isTeacherOnly = r.contains('teacher') && !r.contains('admin') && !r.contains('principal');

    final teachers = SchoolLocalStorage.getAllTeachersCached(widget.branchId);
    final loggedTeacher = teachers.firstWhere(
      (t) => (t['name'] ?? '').toString().toLowerCase().trim() == widget.editorName.toLowerCase().trim(),
      orElse: () => <String, dynamic>{},
    );

    final teacherHomeroomGrade = (loggedTeacher['homeroomGrade'] ?? '').toString().trim();
    final homeroomAssignment = _selectedGradeFilter != 'All'
        ? SchoolLocalStorage.getHomeroomAssignmentCached(widget.branchId, _selectedGradeFilter, 'A')
        : null;
    final assignedHomeroomTeacherName = homeroomAssignment?['teacherName']?.toString() ?? 'Unassigned';

    // Lock attendance marking if user is a teacher and selected grade != their assigned homeroom class
    bool isAttendanceLocked = false;
    if (isTeacherOnly) {
      if (_selectedGradeFilter == 'All') {
        isAttendanceLocked = true;
      } else if (teacherHomeroomGrade.isNotEmpty && teacherHomeroomGrade != _selectedGradeFilter) {
        isAttendanceLocked = true;
      } else if (teacherHomeroomGrade.isEmpty && assignedHomeroomTeacherName.toLowerCase() != widget.editorName.toLowerCase()) {
        isAttendanceLocked = true;
      }
    }

    final bool effectiveAllowLeave = _localAllowStudentLeave ?? true;

    return PopScope(
      canPop: _localChanges.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardChanges();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Column(
            children: [
              // Global Level User Allow Leave Banner
              if (_isGlobalLevelUser(widget.userRole)) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: effectiveAllowLeave ? const Color(0xFFFFF8E1) : const Color(0xFFEEF2FF),
                  child: Row(
                    children: [
                      Icon(
                        effectiveAllowLeave ? Icons.event_available_rounded : Icons.event_busy_rounded,
                        color: effectiveAllowLeave ? Colors.amber.shade900 : const Color(0xFF4338CA),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '👑 Global Users Only (Chairman, CEO, HQ Manager, Admin)',
                                    style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              effectiveAllowLeave ? 'Student Leave Option Allowed (Visible to ALL Users)' : 'Student Leave Option Stopped (Hidden from ALL Users)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: effectiveAllowLeave ? Colors.amber.shade900 : const Color(0xFF3730A3)),
                            ),
                            Text(
                              effectiveAllowLeave
                                  ? 'Leave button is displayed for ALL users. Click Stop Leave to hide it.'
                                  : 'Leave option is hidden from ALL users. Click Allow Leave to display it.',
                              style: TextStyle(fontSize: 11, color: effectiveAllowLeave ? Colors.amber.shade900 : Colors.indigo.shade700),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: effectiveAllowLeave ? Colors.red.shade700 : const Color(0xFF4338CA),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: Icon(effectiveAllowLeave ? Icons.block : Icons.check_circle_outline, size: 16),
                        label: Text(effectiveAllowLeave ? 'Stop Leave' : 'Allow Leave', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: () async {
                          final newAllowState = !effectiveAllowLeave;
                          setState(() {
                            _localAllowStudentLeave = newAllowState;
                          });
                          await FirebaseFirestore.instance
                              .collection('branches')
                              .doc(widget.branchId)
                              .collection('madrassa_config')
                              .doc('current')
                              .set({'allowStudentLeave': newAllowState}, SetOptions(merge: true));

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 2),
                                backgroundColor: newAllowState ? Colors.green.shade700 : Colors.red.shade700,
                                content: Text(newAllowState ? 'Student Leave option enabled & visible to ALL users.' : 'Student Leave option disabled & hidden from ALL users.'),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],

              // Homeroom Teacher Lock Banner
              if (isAttendanceLocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFFFEF2F2),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Color(0xFFEF4444), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedGradeFilter == 'All'
                              ? '🔒 Attendance marking locked in "All Classes" view. Please select your assigned Homeroom Class to mark student attendance.'
                              : '🔒 Attendance Marking Locked: Only the assigned Homeroom Teacher ($assignedHomeroomTeacherName) can mark attendance for Grade $_selectedGradeFilter.',
                          style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              // Date & Grade Filter Toolbar
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Row(
                  children: [
                    // Date picker button
                    InkWell(
                      onTap: isAttendanceLocked ? null : _pickDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, color: Color(0xFF6366F1), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('EEEE, dd MMM yyyy').format(_selectedDate),
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Grade Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedGradeFilter,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          items: _gradeOptions.map((g) {
                            return DropdownMenuItem(value: g, child: Text('Class: $g'));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedGradeFilter = v);
                          },
                        ),
                      ),
                    ),
                    const Spacer(),

                    // Mark All Present Button
                    OutlinedButton.icon(
                      onPressed: isAttendanceLocked ? null : _markAllPresent,
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Mark All Present'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF10B981),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Save Changes Button
                    ElevatedButton.icon(
                      onPressed: (isAttendanceLocked || _isSaving) ? null : _saveAttendance,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save Log'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Attendance List
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: SchoolLocalStorage.streamStudentsCached(widget.branchId),
                  builder: (context, studentSnapshot) {
                    final allStudents = studentSnapshot.data ?? [];
                    var students = allStudents.where((s) => (s['status'] ?? 'active') == 'active').toList();

                    if (_selectedGradeFilter != 'All') {
                      students = students.where((s) => (s['grade'] ?? '') == _selectedGradeFilter).toList();
                    }

                    if (students.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rule_folder_rounded, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No active students found for Grade: $_selectedGradeFilter',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                            ),
                          ],
                        ),
                      );
                    }

                    return StreamBuilder<Map<String, dynamic>?>(
                      stream: SchoolLocalStorage.streamLogCached(widget.branchId, dateKey),
                      builder: (context, logSnapshot) {
                        final logMap = (logSnapshot.data?['entries'] as Map?) ?? {};

                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: students.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final st = students[index];
                            final studentId = (st['id'] ?? st['rollNo']).toString();

                            final existingEntry = _localChanges[studentId] ??
                                Map<String, dynamic>.from((logMap[studentId] as Map?) ?? {});

                            final status = (existingEntry['status'] ?? 'present').toString();
                            final isUniform = (existingEntry['uniform'] ?? true) as bool;
                            final remarks = (existingEntry['remarks'] ?? '').toString();

                            return _buildStudentAttendanceCard(
                              student: st,
                              studentId: studentId,
                              status: status,
                              isUniform: isUniform,
                              remarks: remarks,
                              readOnly: isAttendanceLocked,
                              allowStudentLeave: effectiveAllowLeave,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildStudentAttendanceCard({
    required Map<String, dynamic> student,
    required String studentId,
    required String status,
    required bool isUniform,
    required String remarks,
    bool readOnly = false,
    bool allowStudentLeave = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Student Info Avatar & Name (Clickable Profile)
          Expanded(
            child: InkWell(
              onTap: () => _showStudentProfileDialog(student),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) {
                        final photoUrl = (student['photoUrl'] ?? '').toString();
                        final bytes = ImageUploadService.decodeBase64ToBytes(photoUrl);
                        if (bytes != null && bytes.isNotEmpty) {
                          return CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                            backgroundImage: MemoryImage(bytes),
                          );
                        } else if (photoUrl.startsWith('http')) {
                          return CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                            backgroundImage: NetworkImage(photoUrl),
                          );
                        }
                        return CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                          child: Text(
                            (student['rollNo'] ?? '0').toString(),
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  student['name'] ?? 'Unknown Student',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF1E293B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${student['grade']} - Sec ${student['section']} • Roll: ${student['rollNo'] ?? '—'}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Status Selector Chips
          AbsorbPointer(
            absorbing: readOnly,
            child: Opacity(
              opacity: readOnly ? 0.6 : 1.0,
              child: Wrap(
                spacing: 6,
                children: [
                  _buildStatusChip(studentId, 'present', 'Present', SchoolTheme.statusPresent, status),
                  _buildStatusChip(studentId, 'absent', 'Absent', SchoolTheme.statusAbsent, status),
                  if (allowStudentLeave || status == 'leave')
                    _buildStatusChip(studentId, 'leave', 'Leave', SchoolTheme.statusLeave, status),
                  _buildStatusChip(studentId, 'late', 'Late', SchoolTheme.statusLate, status),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Uniform Checkbox
          AbsorbPointer(
            absorbing: readOnly,
            child: Opacity(
              opacity: readOnly ? 0.6 : 1.0,
              child: FilterChip(
                label: const Text('Uniform'),
                selected: isUniform,
                selectedColor: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF3B82F6),
                onSelected: readOnly ? null : (val) {
                  setState(() {
                    _localChanges.putIfAbsent(studentId, () => {});
                    _localChanges[studentId]!['uniform'] = val;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    String studentId,
    String statusKey,
    String label,
    Color color,
    String currentStatus,
  ) {
    final isSelected = currentStatus.toLowerCase() == statusKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _localChanges.putIfAbsent(studentId, () => {});
            _localChanges[studentId]!['status'] = statusKey;
          });
        }
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _localChanges.clear();
      });
    }
  }

  void _markAllPresent() {
    // Fetches cached students and updates local changes to present
    final students = SchoolLocalStorage.getAllStudentsCached(widget.branchId);
    setState(() {
      for (var s in students) {
        final id = (s['id'] ?? s['rollNo']).toString();
        _localChanges.putIfAbsent(id, () => {});
        _localChanges[id]!['status'] = 'present';
        _localChanges[id]!['uniform'] = true;
      }
    });
  }

  Future<void> _saveAttendance() async {
    setState(() => _isSaving = true);
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Merge existing log entries with local changes
    final existingLog = SchoolLocalStorage.getLogCached(widget.branchId, dateKey);
    final existingEntries = Map<String, dynamic>.from((existingLog?['entries'] as Map?) ?? {});

    _localChanges.forEach((studentId, changeMap) {
      existingEntries[studentId] = {
        ...?existingEntries[studentId],
        ...changeMap,
      };
    });

    await SchoolLocalStorage.saveDailyLog(
      branchId: widget.branchId,
      dateKey: dateKey,
      logEntries: existingEntries,
      editorName: widget.editorName,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        _localChanges.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance log saved successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  void _showStudentProfileDialog(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (ctx) {
        final photoUrl = (student['photoUrl'] ?? '').toString();
        final bytes = ImageUploadService.decodeBase64ToBytes(photoUrl);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: bytes != null && bytes.isNotEmpty
                      ? CircleAvatar(radius: 40, backgroundImage: MemoryImage(bytes))
                      : (photoUrl.startsWith('http')
                          ? CircleAvatar(radius: 40, backgroundImage: NetworkImage(photoUrl))
                          : CircleAvatar(
                              radius: 40,
                              backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                              child: const Icon(Icons.person_rounded, size: 44, color: Color(0xFF6366F1)),
                            )),
                ),
                const SizedBox(height: 12),
                Text(
                  student['name'] ?? 'Student',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Class: ${student['grade']} - Sec ${student['section']} • Roll: ${student['rollNo'] ?? '—'}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
                const Divider(height: 24),
                _buildProfileRow('Father / Guardian:', student['guardianName']?.toString() ?? '—'),
                _buildProfileRow('Contact Phone:', student['guardianPhone']?.toString() ?? '—'),
                if ((student['bformNo'] ?? '').toString().isNotEmpty)
                  _buildProfileRow('B-Form Number:', student['bformNo'].toString()),
                if ((student['guardianCnic'] ?? '').toString().isNotEmpty)
                  _buildProfileRow('Father CNIC:', student['guardianCnic'].toString()),
                if ((student['biometricPin'] ?? '').toString().isNotEmpty)
                  _buildProfileRow('Biometric PIN:', student['biometricPin'].toString()),
                if ((student['address'] ?? '').toString().isNotEmpty)
                  _buildProfileRow('Residential Address:', student['address'].toString()),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ),
        ],
      ),
    );
  }
}
