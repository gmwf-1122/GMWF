import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/madrassa_providers.dart';
import '../madrassa_strings.dart';

class MadrassaProgressView extends ConsumerStatefulWidget {
  final String branchId;
  final bool isAdmin;

  const MadrassaProgressView({
    super.key,
    required this.branchId,
    required this.isAdmin,
  });

  @override
  ConsumerState<MadrassaProgressView> createState() => _MadrassaProgressViewState();
}

class _MadrassaProgressViewState extends ConsumerState<MadrassaProgressView> {
  String _selectedTimeframe = 'Daily'; // 'Daily', 'Weekly', 'Monthly', 'Overall'
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _calculateProgress(Map<String, dynamic> student, List<Map<String, dynamic>> allLogs) {
    final sId = student['id'] ?? '';
    final prevHifzLines = int.tryParse(student['prevHifzLines']?.toString() ?? '0') ?? 0;

    if (allLogs.isEmpty) {
      if (_selectedTimeframe == 'Overall') {
        return prevHifzLines;
      }
      return 0;
    }

    // Sort allLogs chronologically by dateKey
    final sortedLogs = List<Map<String, dynamic>>.from(allLogs)
      ..sort((a, b) => a['dateKey'].toString().compareTo(b['dateKey'].toString()));

    final latestDateKey = sortedLogs.last['dateKey']?.toString() ?? '';
    final latestDate = DateTime.tryParse(latestDateKey) ?? DateTime.now();

    if (_selectedTimeframe == 'Daily') {
      final latestLog = sortedLogs.last;
      final studentLog = latestLog[sId];
      if (studentLog is Map && studentLog.containsKey('currentLines')) {
        return int.tryParse(studentLog['currentLines']?.toString() ?? '') ?? 0;
      }
      return 0;
    }

    DateTime startDate;
    if (_selectedTimeframe == 'Weekly') {
      // Last 7 days ending at latestDate (e.g. from T-6 to T)
      startDate = latestDate.subtract(const Duration(days: 6));
    } else if (_selectedTimeframe == 'Monthly') {
      // Last 30 days ending at latestDate (e.g. from T-29 to T)
      startDate = latestDate.subtract(const Duration(days: 29));
    } else {
      // Overall: sum all logs in history
      startDate = DateTime(2000, 1, 1);
    }

    int sum = 0;
    for (final log in sortedLogs) {
      final dateKey = log['dateKey']?.toString() ?? '';
      final parsedDate = DateTime.tryParse(dateKey);
      if (parsedDate == null) continue;

      if (_selectedTimeframe == 'Weekly' || _selectedTimeframe == 'Monthly') {
        if (parsedDate.isBefore(startDate) || parsedDate.isAfter(latestDate)) {
          continue;
        }
      }

      final studentLog = log[sId];
      if (studentLog is Map && studentLog.containsKey('currentLines')) {
        sum += int.tryParse(studentLog['currentLines']?.toString() ?? '') ?? 0;
      }
    }

    if (_selectedTimeframe == 'Overall') {
      sum += prevHifzLines;
    }

    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(madrassaStudentsProvider(widget.branchId));
    final logsAsync = ref.watch(madrassaAllLogsProvider(widget.branchId));

    return studentsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF4C4DDC)),
      ),
      error: (e, st) => Center(child: Text('Error loading students: $e')),
      data: (students) {
        return logsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF4C4DDC)),
          ),
          error: (e, st) => Center(child: Text('Error loading logs: $e')),
          data: (allLogs) {
            // Process students and compute progress
            final List<Map<String, dynamic>> processedStudents = [];
            for (final std in students) {
              final statusVal = std['status'];
              final isActive = (statusVal == null || statusVal == '')
                  ? (std['active'] == true)
                  : (statusVal == 'active');
              if (!isActive) continue;

              final progress = _calculateProgress(std, allLogs);
              processedStudents.add({
                ...std,
                'calculatedProgress': progress,
              });
            }

            // Filter by search query
            final query = _searchQuery.trim().toLowerCase();
            final filteredStudents = processedStudents.where((std) {
              final name = (std['name']?.toString() ?? '').toLowerCase();
              final roll = (std['rollNumber']?.toString() ?? '').toLowerCase();
              return name.contains(query) || roll.contains(query);
            }).toList();

            // Sort lists
            final bestStudents = List<Map<String, dynamic>>.from(processedStudents)
              ..sort((a, b) => (b['calculatedProgress'] as int).compareTo(a['calculatedProgress'] as int));

            final worstStudents = List<Map<String, dynamic>>.from(processedStudents)
              ..sort((a, b) => (a['calculatedProgress'] as int).compareTo(b['calculatedProgress'] as int));

            // Categorize filtered students with dynamic thresholds based on timeframe
            int goodThreshold = 10;
            int badThreshold = 5;
            if (_selectedTimeframe == 'Weekly') {
              goodThreshold = 70;
              badThreshold = 35;
            } else if (_selectedTimeframe == 'Monthly') {
              goodThreshold = 300;
              badThreshold = 150;
            } else if (_selectedTimeframe == 'Overall') {
              goodThreshold = 10;
              badThreshold = 5;
            }

            final goodProgress = filteredStudents.where((s) => (s['calculatedProgress'] as int) > goodThreshold).toList()
              ..sort((a, b) => (b['calculatedProgress'] as int).compareTo(a['calculatedProgress'] as int));

            final avgProgress = filteredStudents.where((s) {
              final prog = s['calculatedProgress'] as int;
              return prog >= badThreshold && prog <= goodThreshold;
            }).toList()
              ..sort((a, b) => (b['calculatedProgress'] as int).compareTo(a['calculatedProgress'] as int));

            final badProgress = filteredStudents.where((s) => (s['calculatedProgress'] as int) < badThreshold).toList()
              ..sort((a, b) => (b['calculatedProgress'] as int).compareTo(a['calculatedProgress'] as int));

            return Scaffold(
              backgroundColor: const Color(0xFFF8F9FD),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTimeframeHeader(),
                    const SizedBox(height: 24),
                    _buildInsightsGrid(bestStudents, worstStudents),
                    const SizedBox(height: 32),
                    _buildSearchAndFilters(),
                    const SizedBox(height: 24),
                    _buildCategorizedLists(goodProgress, avgProgress, badProgress, goodThreshold, badThreshold),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimeframeHeader() {
    final options = ['Daily', 'Weekly', 'Monthly', 'Overall'];
    final optionsUrdu = {
      'Daily': 'روزانہ',
      'Weekly': 'ہفتہ وار',
      'Monthly': 'ماہانہ',
      'Overall': 'مجموعی',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = MediaQuery.of(context).size.width < 600;

        final title = Text(
          context.isUrdu ? 'طالب علموں کی کارکردگی' : 'Student Progress Insights',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        );

        final selector = Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final isSelected = _selectedTimeframe == opt;
              final label = context.isUrdu ? optionsUrdu[opt]! : opt;
              return GestureDetector(
                onTap: () => setState(() => _selectedTimeframe = opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF4C4DDC) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: selector,
              ),
            ],
          );
        } else {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              title,
              selector,
            ],
          );
        }
      },
    );
  }

  Widget _buildInsightsGrid(List<Map<String, dynamic>> best, List<Map<String, dynamic>> worst) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final topPerformers = best.take(5).toList();
        final struggling = worst.take(5).toList();

        final bestCard = _buildInsightsCard(
          title: context.isUrdu ? 'بہترین کارکردگی (ٹاپ 5)' : 'Top Performers (Best 5)',
          students: topPerformers,
          isGood: true,
          gradient: const [Color(0xFF0D9488), Color(0xFF0F766E)],
        );

        final worstCard = _buildInsightsCard(
          title: context.isUrdu ? 'توجہ طلب طالب علم (آخری 5)' : 'Needs Attention (Worst 5)',
          students: struggling,
          isGood: false,
          gradient: const [Color(0xFFE11D48), Color(0xFFBE123C)],
        );

        if (isMobile) {
          return Column(
            children: [
              bestCard,
              const SizedBox(height: 16),
              worstCard,
            ],
          );
        } else {
          return Row(
            children: [
              Expanded(child: bestCard),
              const SizedBox(width: 24),
              Expanded(child: worstCard),
            ],
          );
        }
      },
    );
  }

  Widget _buildInsightsCard({
    required String title,
    required List<Map<String, dynamic>> students,
    required bool isGood,
    required List<Color> gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isGood ? Icons.stars_rounded : Icons.warning_amber_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (students.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.isUrdu ? 'کوئی ڈیٹا موجود نہیں' : 'No data available',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            )
          else
            ...students.asMap().entries.map((e) {
              final idx = e.key;
              final std = e.value;
              final progress = std['calculatedProgress'] as int;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              std['name']?.toString() ?? '',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+$progress ${context.isUrdu ? 'لائنیں' : 'lines'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: Color(0xFF64748B)),
          hintText: context.isUrdu ? 'طالب علم کا نام یا رول نمبر تلاش کریں...' : 'Search student by name or roll number...',
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF94A3B8),
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildCategorizedLists(
    List<Map<String, dynamic>> good,
    List<Map<String, dynamic>> avg,
    List<Map<String, dynamic>> bad,
    int goodThreshold,
    int badThreshold,
  ) {
    return Column(
      children: [
        _buildCategorySection(
          title: context.isUrdu ? 'بہترین ترقی (> $goodThreshold لائنیں)' : 'Good Progress (> $goodThreshold Lines)',
          count: good.length,
          students: good,
          indicatorColor: const Color(0xFF10B981),
          lightTint: const Color(0xFFECFDF5),
        ),
        const SizedBox(height: 20),
        _buildCategorySection(
          title: context.isUrdu ? 'اوسط ترقی ($badThreshold سے $goodThreshold لائنیں)' : 'Average Progress ($badThreshold - $goodThreshold Lines)',
          count: avg.length,
          students: avg,
          indicatorColor: const Color(0xFFF59E0B),
          lightTint: const Color(0xFFFFFBEB),
        ),
        const SizedBox(height: 20),
        _buildCategorySection(
          title: context.isUrdu ? 'کمزور ترقی (< $badThreshold لائنیں)' : 'Slow Progress (< $badThreshold Lines)',
          count: bad.length,
          students: bad,
          indicatorColor: const Color(0xFFEF4444),
          lightTint: const Color(0xFFFEF2F2),
        ),
      ],
    );
  }

  Widget _buildCategorySection({
    required String title,
    required int count,
    required List<Map<String, dynamic>> students,
    required Color indicatorColor,
    required Color lightTint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ExpansionTile(
        initiallyExpanded: count > 0,
        shape: const Border(),
        leading: Container(
          width: 8,
          height: 24,
          decoration: BoxDecoration(
            color: indicatorColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: lightTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: indicatorColor,
                ),
              ),
            ),
          ],
        ),
        children: [
          if (students.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  context.isUrdu ? 'اس زمرے میں کوئی طالب علم نہیں ہے' : 'No students in this category',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: students.length,
              separatorBuilder: (context, index) => const Divider(color: Color(0xFFF1F5F9), height: 1),
              itemBuilder: (context, index) {
                final std = students[index];
                final progress = std['calculatedProgress'] as int;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFEEF2F6),
                              child: Text(
                                (std['rollNumber']?.toString() ?? '#').substring(0, 1),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    std['name']?.toString() ?? '',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1E293B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${context.isUrdu ? 'رول نمبر' : 'Roll'}: ${std['rollNumber'] ?? ''}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: lightTint,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: indicatorColor.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 12,
                              color: indicatorColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$progress ${context.isUrdu ? 'لائنیں' : 'lines'}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: indicatorColor,
                              ),
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
  }
}
