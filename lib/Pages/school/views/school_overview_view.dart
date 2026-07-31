// lib/pages/school/views/school_overview_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/school_local_storage.dart';

class SchoolOverviewView extends StatelessWidget {
  final String branchId;

  const SchoolOverviewView({
    super.key,
    required this.branchId,
  });

  @override
  Widget build(BuildContext context) {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SchoolLocalStorage.streamStudentsCached(branchId),
      builder: (context, studentSnapshot) {
        final students = studentSnapshot.data ?? [];
        final totalStudents = students.length;
        final activeStudents = students.where((s) => (s['status'] ?? 'active') == 'active').length;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: SchoolLocalStorage.streamTeachersCached(branchId),
          builder: (context, teacherSnapshot) {
            final teachers = teacherSnapshot.data ?? [];
            final totalTeachers = teachers.length;
            final activeTeachers = teachers.where((t) => (t['status'] ?? 'active') == 'active').length;

            return StreamBuilder<Map<String, dynamic>?>(
              stream: SchoolLocalStorage.streamLogCached(branchId, todayKey),
              builder: (context, logSnapshot) {
                final logData = logSnapshot.data;
                final entries = (logData?['entries'] as Map?) ?? {};

                int presentCount = 0;
                int absentCount = 0;
                int leaveCount = 0;

                entries.forEach((key, value) {
                  if (value is Map) {
                    final status = (value['status'] ?? '').toString().toLowerCase();
                    if (status == 'present') presentCount++;
                    else if (status == 'absent') absentCount++;
                    else if (status == 'leave') leaveCount++;
                  }
                });

                final attendancePct = activeStudents > 0
                    ? ((presentCount / activeStudents) * 100).toStringAsFixed(1)
                    : '0.0';

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overview Header Banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E1B4B), Color(0xFF4338CA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4338CA).withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // 1. GMWF Logo
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.asset(
                                          'assets/logo/gmwf-1.webp',
                                          height: 38,
                                          width: 38,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text('GMWF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text('•', style: TextStyle(color: Colors.white70, fontSize: 18)),
                                      const SizedBox(width: 10),

                                      // 2. Taleem-o-Tarbiyat Logo Placeholder
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.asset(
                                          'assets/logo/twt_logo.webp',
                                          height: 38,
                                          width: 38,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                              border: Border.all(color: const Color(0xFF34D399)),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(Icons.school_rounded, color: Color(0xFF34D399), size: 16),
                                                SizedBox(width: 6),
                                                Text('[ TWT Logo ]', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Taleem-o-Tarbiyat School System',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Established by GMWF • Real-time student admissions, faculty records, attendance & library management.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Stream Grades for KPI Card
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: SchoolLocalStorage.streamGradesCached(branchId),
                        builder: (context, gradeSnapshot) {
                          final grades = gradeSnapshot.data ?? [];
                          double totalPct = 0;
                          int validCount = 0;
                          for (final g in grades) {
                            final total = (g['totalMarks'] as num? ?? 100).toDouble();
                            final obt = (g['marksObtained'] as num? ?? 0).toDouble();
                            if (total > 0) {
                              totalPct += (obt / total) * 100;
                              validCount++;
                            }
                          }
                          final avgPct = validCount > 0 ? (totalPct / validCount).toStringAsFixed(1) : 'N/A';

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final isMobile = constraints.maxWidth < 650;
                              return GridView.count(
                                crossAxisCount: isMobile ? 2 : 5,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: isMobile ? 1.3 : 1.4,
                                children: [
                                  _buildMetricCard(
                                    title: 'Active Students',
                                    value: '$activeStudents',
                                    subtitle: 'Total: $totalStudents',
                                    icon: Icons.groups_rounded,
                                    color: const Color(0xFF6366F1),
                                  ),
                                  _buildMetricCard(
                                    title: 'Teaching Staff',
                                    value: '$activeTeachers',
                                    subtitle: 'Total: $totalTeachers',
                                    icon: Icons.record_voice_over_rounded,
                                    color: const Color(0xFF10B981),
                                  ),
                                  _buildMetricCard(
                                    title: 'Present Today',
                                    value: '$presentCount',
                                    subtitle: 'Absent: $absentCount | Leave: $leaveCount',
                                    icon: Icons.check_circle_rounded,
                                    color: const Color(0xFF3B82F6),
                                  ),
                                  _buildMetricCard(
                                    title: 'Attendance Rate',
                                    value: '$attendancePct%',
                                    subtitle: 'Today\'s percentage',
                                    icon: Icons.analytics_rounded,
                                    color: const Color(0xFFF59E0B),
                                  ),
                                  _buildMetricCard(
                                    title: 'Academic Avg',
                                    value: avgPct == 'N/A' ? 'N/A' : '$avgPct%',
                                    subtitle: '$validCount grades recorded',
                                    icon: Icons.grade_rounded,
                                    color: const Color(0xFF8B5CF6),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 32),

                      // Class-wise breakdown list
                      const Text(
                        'Class Distribution',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildClassDistributionCard(students),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassDistributionCard(List<Map<String, dynamic>> students) {
    final Map<String, int> classCounts = {};
    for (var s in students) {
      final grade = (s['grade'] ?? 'Unassigned').toString();
      classCounts[grade] = (classCounts[grade] ?? 0) + 1;
    }

    if (classCounts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text(
            'No students registered yet. Click on "Students" tab to enroll students.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: classCounts.entries.map((e) {
          return Container(
            width: 160,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${e.value} Students',
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
