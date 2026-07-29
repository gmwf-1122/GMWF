// lib/pages/school/views/school_teacher_attendance_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/school_theme.dart';
import '../utils/school_local_storage.dart';

class SchoolTeacherAttendanceView extends StatefulWidget {
  final String branchId;
  final String editorName;

  const SchoolTeacherAttendanceView({
    super.key,
    required this.branchId,
    this.editorName = 'School Admin',
  });

  @override
  State<SchoolTeacherAttendanceView> createState() => _SchoolTeacherAttendanceViewState();
}

class _SchoolTeacherAttendanceViewState extends State<SchoolTeacherAttendanceView> {
  DateTime _selectedDate = DateTime.now();
  String _selectedDeptFilter = 'All';
  bool _isSaving = false;
  final Map<String, Map<String, dynamic>> _localChanges = {};

  final List<String> _departments = [
    'All',
    'Science & IT',
    'Mathematics',
    'Languages & English',
    'Social Studies & Humanities',
    'Arts & Commerce',
    'Primary Education',
    'Administration',
  ];

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
            Text('Unsaved Faculty Attendance Edits'),
          ],
        ),
        content: const Text(
          'You have unsaved faculty attendance edits for this date. If you leave now, these changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay & Edit'),
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
        // Date & Department Filter Toolbar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              // Date picker button
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, dd MMM yyyy').format(_selectedDate),
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Department Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedDeptFilter,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: _departments.map((d) {
                      return DropdownMenuItem(value: d, child: Text('Dept: $d'));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedDeptFilter = v);
                    },
                  ),
                ),
              ),
              const Spacer(),

              // Mark All Present Button
              OutlinedButton.icon(
                onPressed: _markAllPresent,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Mark All Present'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 12),

              // Save Log Button
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveAttendance,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save Teacher Log'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
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
            stream: SchoolLocalStorage.streamTeachersCached(widget.branchId),
            builder: (context, teacherSnapshot) {
              final allTeachers = teacherSnapshot.data ?? [];
              var teachers = allTeachers.where((t) => (t['status'] ?? 'active') == 'active').toList();

              if (_selectedDeptFilter != 'All') {
                teachers = teachers.where((t) => (t['department'] ?? '') == _selectedDeptFilter).toList();
              }

              if (teachers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'No teachers found for Department: $_selectedDeptFilter',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                      ),
                    ],
                  ),
                );
              }

              return StreamBuilder<Map<String, dynamic>?>(
                stream: SchoolLocalStorage.streamTeacherLogCached(widget.branchId, dateKey),
                builder: (context, logSnapshot) {
                  final logMap = (logSnapshot.data?['entries'] as Map?) ?? {};

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: teachers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final t = teachers[index];
                      final teacherId = (t['id'] ?? t['employeeId']).toString();

                      final existingEntry = _localChanges[teacherId] ??
                          Map<String, dynamic>.from((logMap[teacherId] as Map?) ?? {});

                      final status = (existingEntry['status'] ?? 'present').toString();

                      return _buildTeacherAttendanceCard(
                        teacher: t,
                        teacherId: teacherId,
                        status: status,
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

  Widget _buildTeacherAttendanceCard({
    required Map<String, dynamic> teacher,
    required String teacherId,
    required String status,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.1),
            child: const Icon(Icons.record_voice_over_rounded, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teacher['name'] ?? 'Unknown Teacher',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${teacher['designation']} (${teacher['department']}) • ID: ${teacher['employeeId']}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),

          // Status Selector Chips
          Wrap(
            spacing: 6,
            children: [
              _buildStatusChip(teacherId, 'present', 'Present', SchoolTheme.statusPresent, status),
              _buildStatusChip(teacherId, 'absent', 'Absent', SchoolTheme.statusAbsent, status),
              _buildStatusChip(teacherId, 'leave', 'On Leave', SchoolTheme.statusLeave, status),
              _buildStatusChip(teacherId, 'late', 'Late Arrival', SchoolTheme.statusLate, status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    String teacherId,
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
            _localChanges.putIfAbsent(teacherId, () => {});
            _localChanges[teacherId]!['status'] = statusKey;
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
    final teachers = SchoolLocalStorage.getAllTeachersCached(widget.branchId);
    setState(() {
      for (var t in teachers) {
        final id = (t['id'] ?? t['employeeId']).toString();
        _localChanges.putIfAbsent(id, () => {});
        _localChanges[id]!['status'] = 'present';
      }
    });
  }

  Future<void> _saveAttendance() async {
    setState(() => _isSaving = true);
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    final existingLog = SchoolLocalStorage.getLogCached(widget.branchId, '${dateKey}_teachers');
    final existingEntries = Map<String, dynamic>.from((existingLog?['entries'] as Map?) ?? {});

    _localChanges.forEach((teacherId, changeMap) {
      existingEntries[teacherId] = {
        ...?existingEntries[teacherId],
        ...changeMap,
      };
    });

    await SchoolLocalStorage.saveTeacherDailyLog(
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
          content: Text('Faculty attendance log saved successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }
}
