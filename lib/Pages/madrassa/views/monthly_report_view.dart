import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/madrassa_config.dart';
import '../models/madrassa_fee_logic.dart';
import '../widgets/madrassa_common_widgets.dart';
import '../utils/madrassa_report_helper.dart';
import '../madrassa_strings.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/madrassa_providers.dart';
import '../utils/madrassa_local_storage.dart';

/// Safely converts whatever Map-ish value comes back from Firestore / JSON
/// / local-storage into a proper `Map<String, dynamic>`. Firestore (and
/// some local/json sources) can hand back a raw `Map<dynamic, dynamic>` for
/// nested maps, and a direct `as Map<String, dynamic>` cast on that throws:
///   "type '_Map<dynamic, dynamic>' is not a subtype of type
///    'Map<String, dynamic>?' in type cast"
/// `Map<String, dynamic>.from(...)` re-keys everything as Strings instead
/// of doing an unsafe runtime cast, so this never throws for a Map of any
/// shape.
Map<String, dynamic>? _asStringMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

class MonthlyReportView extends ConsumerStatefulWidget {
  final String branchId;
  const MonthlyReportView({super.key, required this.branchId});

  @override
  ConsumerState<MonthlyReportView> createState() => _MonthlyReportViewState();
}

class _MonthlyReportViewState extends ConsumerState<MonthlyReportView> {
  int? _selectedYear;
  int? _selectedMonth;
  bool? _userShowDetailOverride;
  String _searchQuery = '';
  int? _downloadedYear;
  int? _downloadedMonth;
  // Cache for student fee calculations to improve performance
  final Map<String, Map<String, dynamic>> _feeCache = {};

  // Shared vertical scroll controller so the frozen (name/roll) column and
  // the scrollable data columns move together as one table, even though
  // they're technically two separate widgets side by side.
  final ScrollController _verticalController = ScrollController();

  static const double _kRowHeight = 56;
  static const double _kHeaderHeight = 50;
  static const Color _kHeadingBg = Color(0xFFF8F9FD);

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  // Helper to get cached fee for a student or compute if absent
  Map<String, dynamic> _getStudentFee({
    required String studentId,
    required dynamic studentSnap,
    required List<dynamic> monthLogs,
    required MadrassaConfig config,
    required int workingDays,
    required List<DateTime> holidays,
  }) {
    if (_feeCache.containsKey(studentId)) {
      return _feeCache[studentId]!;
    }
    final fee = MadrassaFeeLogic.calculateStudentFee(
      studentId: studentId,
      studentData: studentSnap is DocumentSnapshot
          ? (_asStringMap(studentSnap.data()) ?? <String, dynamic>{})
          : Map<String, dynamic>.from(studentSnap as Map),
      logs: monthLogs,
      config: config,
      totalWorkingDays: workingDays,
      holidays: holidays,
    );
    _feeCache[studentId] = fee;
    return fee;
  }

  @override
  void initState() {
    super.initState();
    MadrassaLocalStorage.downloadStudents(widget.branchId);
    MadrassaLocalStorage.downloadHolidays(widget.branchId);
  }

  @override
  Widget build(BuildContext context) {
    final configAsyncValue = ref.watch(madrassaConfigProvider(widget.branchId));
    final holidaysAsyncValue = ref.watch(madrassaHolidaysProvider(widget.branchId));

    return configAsyncValue.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error loading config: $e'))),
      data: (config) {
        final currentYear = _selectedYear ?? config.year;
        final currentMonth = _selectedMonth ?? config.month;

        // ── Holidays are now resolved BEFORE `workingDays`, so the
        // denominator passed into the fee calculation excludes the exact
        // same Sundays + holidays that the numerator (`activeWorkingDays`)
        // excludes. Previously `workingDays` was computed without
        // `holidays`, so a fully-present student could never reach 100% of
        // the base fee whenever a holiday fell inside the month.
        final cachedHolidays = holidaysAsyncValue.value ?? [];
        final holidays = cachedHolidays
            .map<DateTime>((d) {
              final dateVal = d['date'];
              if (dateVal is Timestamp) return dateVal.toDate();
              if (dateVal is String) return DateTime.tryParse(dateVal) ?? DateTime.now();
              return DateTime.now();
            })
            .toList();

        final workingDays = MadrassaFeeLogic.getWorkingDaysCount(currentYear, currentMonth, holidays);

        final displayConfig = MadrassaConfig(
          id: config.id,
          year: currentYear,
          month: currentMonth,
          ptmDay: config.ptmDay,
          baseFee: config.baseFee,
          ptmDeduction: config.ptmDeduction,
          messageTotalDeduction: config.messageTotalDeduction,
          attendanceMaxDeduction: config.attendanceMaxDeduction,
          uniformMaxDeduction: config.uniformMaxDeduction,
          auditLog: config.auditLog,
        );

        if (_downloadedYear != currentYear || _downloadedMonth != currentMonth) {
          _downloadedYear = currentYear;
          _downloadedMonth = currentMonth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            MadrassaLocalStorage.downloadLogsForMonth(widget.branchId, currentYear, currentMonth);
          });
        }

        final studentsAsyncValue = ref.watch(madrassaStudentsProvider(widget.branchId));
        final logsAsyncValue = ref.watch(madrassaMonthlyLogsProvider((branchId: widget.branchId, year: currentYear, month: currentMonth)));

        return studentsAsyncValue.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, st) => Scaffold(body: Center(child: Text('Error loading students: $e'))),
          data: (students) {
            final filteredStudents = students.where((s) {
              final name = (s['name']?.toString() ?? '').toLowerCase();
              final roll = (s['rollNumber']?.toString() ?? '').toLowerCase();
              return name.contains(_searchQuery) || roll.contains(_searchQuery);
            }).toList();

            return logsAsyncValue.when(
              loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
              error: (e, st) => Scaffold(body: Center(child: Text('Error loading logs: $e'))),
              data: (monthLogs) {
                _feeCache.clear();

                return Scaffold(
                  backgroundColor: const Color(0xFFF8F9FD),
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool showDetail = _userShowDetailOverride ?? (constraints.maxWidth >= 1100);
                      final isMobile = MediaQuery.of(context).size.width < 600;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context, displayConfig, students, monthLogs, currentYear, currentMonth, holidays, workingDays, showDetail),

                          // Warning Banner
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.isUrdu
                                          ? 'آرکائیو اور مکمل شدہ طلباء کو بلک ڈاؤن لوڈ سے خارج کر دیا گیا ہے۔ ان کی رپورٹس دستی طور پر ڈاؤن لوڈ کریں۔'
                                          : 'Archived and Completed students are excluded from bulk downloads and must be downloaded manually.',
                                      style: TextStyle(
                                        color: Colors.amber.shade900,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: context.isUrdu ? 'Noori' : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Search Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: context.isUrdu ? 'طالب علم تلاش کریں (نام یا رول نمبر)...' : 'Search student by name or roll number...',
                                hintStyle: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF008080)),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF008080), width: 2),
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val.trim().toLowerCase();
                                });
                              },
                            ),
                          ),

                          Expanded(
                            child: isMobile
                                ? ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    itemCount: filteredStudents.length,
                                    itemBuilder: (context, i) {
                                      final s = filteredStudents[i];
                                      final sId = s['id']?.toString() ?? '';
                                      final fee = _getStudentFee(
                                        studentId: sId,
                                        studentSnap: s,
                                        monthLogs: monthLogs,
                                        config: displayConfig,
                                        workingDays: workingDays,
                                        holidays: holidays,
                                      );
                                      return _buildMobileStudentSummaryCard(
                                        context,
                                        s,
                                        fee,
                                        displayConfig,
                                        monthLogs,
                                        holidays,
                                      );
                                    },
                                  )
                                : Padding(
                                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                                    child: filteredStudents.isEmpty
                                        ? _buildEmptyState(context)
                                        : _buildFrozenColumnTable(
                                            context,
                                            filteredStudents,
                                            displayConfig,
                                            monthLogs,
                                            workingDays,
                                            holidays,
                                            showDetail,
                                          ),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E2E7)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text('No students match your search', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }

  /// Renders the monthly grid as two side-by-side panels sharing one
  /// vertical scroll: a FROZEN left panel (row #, student name, roll
  /// number) that never moves horizontally, and a horizontally scrollable
  /// right panel with every other column (attendance, fees, actions...).
  ///
  /// This solves the "who am I downloading?" problem — no matter how far
  /// right you scroll to reach the export menu, the student's name and
  /// roll number stay pinned and visible on the left at all times.
  Widget _buildFrozenColumnTable(
    BuildContext context,
    List<dynamic> filteredStudents,
    MadrassaConfig config,
    List<dynamic> logs,
    int workingDays,
    List<DateTime> holidays,
    bool showDetail,
  ) {
    // Pre-resolve each row's data once so both panels read from the same
    // source and never get out of sync.
    final rows = List.generate(filteredStudents.length, (i) {
      final s = filteredStudents[i];
      final sId = s['id']?.toString() ?? '';
      final fee = _getStudentFee(
        studentId: sId,
        studentSnap: s,
        monthLogs: logs,
        config: config,
        workingDays: workingDays,
        holidays: holidays,
      );
      final data = s is DocumentSnapshot ? (_asStringMap(s.data()) ?? <String, dynamic>{}) : Map<String, dynamic>.from(s as Map);
      return (s: s, sId: sId, fee: fee, data: data);
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E2E7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        controller: _verticalController,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Frozen panel ────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                border: const Border(right: BorderSide(color: Color(0xFFE0E2E7), width: 1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(2, 0)),
                ],
              ),
              child: Column(
                children: [
                  _frozenHeaderRow(context),
                  ...List.generate(rows.length, (i) => _frozenDataRow(context, i, rows[i].data)),
                ],
              ),
            ),
            // ── Scrollable panel ────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    _scrollableHeaderRow(context, showDetail),
                    ...List.generate(
                      rows.length,
                      (i) => _scrollableDataRow(context, i, rows[i].s, rows[i].fee, rows[i].data, config, logs, holidays, showDetail),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frozenHeaderRow(BuildContext context) {
    return Container(
      height: _kHeaderHeight,
      decoration: const BoxDecoration(
        color: _kHeadingBg,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E2E7))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _colCell(const Text('#', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), 32, center: true),
          _colCell(Text(context.l.students, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))), 170),
          _colCell(Text(context.l.rollNumber, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))), 95, center: true),
        ],
      ),
    );
  }

  Widget _frozenDataRow(BuildContext context, int index, Map<String, dynamic> data) {
    final isEven = index.isEven;
    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFFAFBFE),
        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 0.75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _colCell(Text('${index + 1}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)), 32, center: true),
          _colCell(
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                data['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            170,
          ),
          _colCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFF0FDFC), borderRadius: BorderRadius.circular(6)),
              child: Text(
                '${data['rollNumber'] ?? '?'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            95,
            center: true,
          ),
        ],
      ),
    );
  }

  Widget _scrollableHeaderRow(BuildContext context, bool showDetail) {
    return Container(
      height: _kHeaderHeight,
      decoration: const BoxDecoration(
        color: _kHeadingBg,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E2E7))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _colCell(Text(context.l.academicDays, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))), 90, center: true),
          _colCell(Text(context.l.present[0], style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13)), 60, center: true),
          _colCell(Text(context.l.leave[0], style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFED6C02), fontSize: 13)), 60, center: true),
          _colCell(Text(context.l.absent[0], style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), fontSize: 13)), 60, center: true),
          if (showDetail)
            _colCell(Text(context.l.attendance, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13))), 75, center: true),
          _colCell(Text(context.l.uniform[0], style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF008080), fontSize: 13)), 65, center: true),
          if (showDetail)
            _colCell(Text('${context.l.uniform[0]}.Rs', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13)), 85, center: true),
          _colCell(const Text('Msg', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFED6C02), fontSize: 13)), 65, center: true),
          _colCell(Text(context.l.ptm, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), fontSize: 13))), 55, center: true),
          _colCell(Text('Savings', style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13))), 80, center: true),
          _colCell(Text(context.l.due, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), fontSize: 13))), 80, center: true),
          _colCell(Text(context.l.legendPresent, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF008080), fontSize: 13))), 130, center: true),
        ],
      ),
    );
  }

  Widget _scrollableDataRow(
    BuildContext context,
    int index,
    dynamic s,
    Map<String, dynamic> fee,
    Map<String, dynamic> data,
    MadrassaConfig config,
    List<dynamic> logs,
    List<DateTime> holidays,
    bool showDetail,
  ) {
    final sId = s is DocumentSnapshot ? s.id : s['id'].toString();
    final isEven = index.isEven;
    final due = ((fee['amountDue'] as num?) ?? 0.0).toDouble();

    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFFAFBFE),
        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 0.75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _colCell(Text('${fee['activeWorkingDays']}', style: const TextStyle(fontSize: 12)), 90, center: true),
          _colCell(Text('${fee['present']}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12)), 60, center: true),
          _colCell(Text('${fee['leave']}', style: const TextStyle(color: Color(0xFFED6C02), fontWeight: FontWeight.bold, fontSize: 12)), 60, center: true),
          _colCell(Text('${fee['absent']}', style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 12)), 60, center: true),
          if (showDetail)
            _colCell(Text(((fee['attSavings'] as num?) ?? 0).toStringAsFixed(0), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12)), 75, center: true),
          _colCell(Text('${fee['uniform']}', style: const TextStyle(color: Color(0xFF008080), fontWeight: FontWeight.bold, fontSize: 12)), 65, center: true),
          if (showDetail)
            _colCell(Text(((fee['uniSavings'] as num?) ?? 0).toStringAsFixed(0), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12)), 85, center: true),
          _colCell(Text('${fee['message']}/${fee['activeWorkingDays']}', style: const TextStyle(color: Color(0xFFED6C02), fontWeight: FontWeight.bold, fontSize: 12)), 65, center: true),
          _colCell(_tag(fee['ptm'] ? 'J' : 'M', fee['ptm'] ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE), fee['ptm'] ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F)), 55, center: true),
          _colCell(Text(((fee['totalSavings'] as num?) ?? 0).toStringAsFixed(0), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12)), 80, center: true),
          _colCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: due <= 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                due.toStringAsFixed(0),
                style: TextStyle(color: due <= 0 ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            80,
            center: true,
          ),
          _colCell(
            StudentExportMenu(
              onPdf: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preparing report for ${data['name'] ?? 'student'}...')));
                MadrassaReportHelper.exportIndividualPdf(config: config, studentId: sId, studentData: data, logs: logs, holidays: holidays);
              },
              onExcel: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preparing Excel report for ${data['name'] ?? 'student'}...')));
                MadrassaReportHelper.exportIndividualExcel(config: config, studentId: sId, studentData: data, logs: logs, holidays: holidays);
              },
              onWhatsApp: () {
                _sendMonthlyWhatsApp(s, fee, logs);
              },
            ),
            130,
            center: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileStudentSummaryCard(
      BuildContext context,
      dynamic s,
      Map<String, dynamic> fee,
      MadrassaConfig config,
      List<dynamic> logs,
      List<DateTime> holidays) {
    final data = s is DocumentSnapshot ? (_asStringMap(s.data()) ?? <String, dynamic>{}) : Map<String, dynamic>.from(s as Map);
    final sId = s is DocumentSnapshot ? s.id : s['id'].toString();
    final due = ((fee['amountDue'] as num?) ?? 0).toStringAsFixed(0);
    final savings = ((fee['totalSavings'] as num?) ?? 0).toStringAsFixed(0);
    final p = fee['present'];
    final l = fee['leave'];
    final a = fee['absent'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E2E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFF0FDFC), borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            'Roll ${data['rollNumber'] ?? '?'}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Active Days: ${fee['activeWorkingDays']}',
                            style: context.urduStyle(style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              StudentExportMenu(
                onPdf: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preparing report for ${data['name'] ?? 'student'}...')));
                  MadrassaReportHelper.exportIndividualPdf(config: config, studentId: sId, studentData: data, logs: logs, holidays: holidays);
                },
                onExcel: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preparing Excel report for ${data['name'] ?? 'student'}...')));
                  MadrassaReportHelper.exportIndividualExcel(config: config, studentId: sId, studentData: data, logs: logs, holidays: holidays);
                },
                onWhatsApp: () {
                  _sendMonthlyWhatsApp(s, fee, logs);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE0E2E7)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statPill(context.l.present[0], '$p', const Color(0xFF2E7D32)),
              _statPill(context.l.leave[0], '$l', const Color(0xFFED6C02)),
              _statPill(context.l.absent[0], '$a', const Color(0xFFD32F2F)),
              _statPill(context.l.ptm, fee['ptm'] ? 'J' : 'M', fee['ptm'] ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Savings', style: context.urduStyle(style: TextStyle(fontSize: 10, color: Colors.grey[500]))),
                  const SizedBox(height: 2),
                  Text('Rs. $savings', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32), fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(context.l.amountDue, style: context.urduStyle(style: TextStyle(fontSize: 10, color: Colors.grey[500]))),
                  const SizedBox(height: 2),
                  Text('Rs. $due', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F), fontSize: 14)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 11),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    MadrassaConfig displayConfig,
    List<dynamic> students,
    List<dynamic> logs,
    int year,
    int month,
    List<DateTime> holidays,
    int workingDays,
    bool showDetail,
  ) {
    final monthName = DateFormat('MMMM yyyy').format(DateTime(year, month));
    final isMobile = MediaQuery.of(context).size.width < 600;

    final headerInfo = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.description_outlined, color: Color(0xFF008080), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l.appName,
                style: context.urduStyle(
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: isMobile ? 20 : 26,
                    color: const Color(0xFF008080),
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Text(
                // Uses the already-computed `workingDays` (which already
                // has holidays factored in via the caller) instead of
                // recalculating without holidays here — keeps this label
                // in sync with the actual denominator used in every fee
                // calculation on this screen.
                '$monthName • $workingDays working days • ${students.length} students',
                style: const TextStyle(fontSize: 12, color: Color(0xFF454749), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );

    final selectors = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDCFCE7)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: year,
              items: List.generate(5, (i) => 2024 + i).map((y) {
                return DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))));
              }).toList(),
              onChanged: (y) {
                if (y != null) {
                  setState(() => _selectedYear = y);
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDCFCE7)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: month,
              items: List.generate(12, (i) => i + 1).map((m) {
                final mName = DateFormat('MMMM').format(DateTime(2024, m));
                return DropdownMenuItem(value: m, child: Text(mName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))));
              }).toList(),
              onChanged: (m) {
                if (m != null) {
                  setState(() => _selectedMonth = m);
                }
              },
            ),
          ),
        ),
        if (!isMobile) ...[
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: Icon(showDetail ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 14),
            label: Text(showDetail ? 'Hide Detail' : 'Show Detail', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade50,
              foregroundColor: Colors.teal.shade800,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.teal.shade100),
              ),
            ),
            onPressed: () {
              setState(() {
                _userShowDetailOverride = !showDetail;
              });
            },
          ),
        ],
      ],
    );

    final exportSection = Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        ExportButton(
          onExcel: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing Excel report...')));
            final activeStudentsForBulk = students.where((s) {
              final status = s['status']?.toString() ?? 'active';
              return status != 'hifz_completed' && status != 'archived';
            }).toList();
            MadrassaReportHelper.exportMonthlyExcel(config: displayConfig, students: activeStudentsForBulk, logs: logs, holidays: holidays);
          },
          onPdf: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing PDF report...')));
            final activeStudentsForBulk = students.where((s) {
              final status = s['status']?.toString() ?? 'active';
              return status != 'hifz_completed' && status != 'archived';
            }).toList();
            MadrassaReportHelper.exportMonthlyPdf(config: displayConfig, students: activeStudentsForBulk, logs: logs, holidays: holidays);
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 12, color: Colors.teal),
            const SizedBox(width: 4),
            Text('Saved in Downloads', style: context.urduStyle(style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold))),
          ],
        ),
      ],
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headerInfo,
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFEEF2F6)),
              const SizedBox(height: 16),
              selectors,
              const SizedBox(height: 16),
              exportSection,
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            Expanded(child: headerInfo),
            const SizedBox(width: 16),
            selectors,
            const SizedBox(width: 24),
            exportSection,
          ],
        ),
      ),
    );
  }

  Future<void> _sendMonthlyWhatsApp(dynamic s, Map<String, dynamic> fee, List<dynamic> monthLogs) async {
    final studentData = s is DocumentSnapshot ? (_asStringMap(s.data()) ?? <String, dynamic>{}) : Map<String, dynamic>.from(s as Map);
    final sId = s is DocumentSnapshot ? s.id : s['id'].toString();

    // Get parent phone
    final String rawPhone = studentData['contactPhone']?.toString() ?? studentData['phone']?.toString() ?? '';
    if (rawPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Parent contact phone number not provided.')),
      );
      return;
    }

    // Clean phone number
    String phone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.startsWith('0')) {
      phone = '92${phone.substring(1)}';
    }
    phone = phone.replaceAll('+', '');
    if (!phone.startsWith('92') && phone.length == 10) {
      phone = '92$phone';
    }

    // Extract academic updates from month logs
    final sortedLogs = [...monthLogs]..sort((a, b) {
      final aId = a is DocumentSnapshot ? a.id : (a as Map)['id']?.toString() ?? '';
      final bId = b is DocumentSnapshot ? b.id : (b as Map)['id']?.toString() ?? '';
      return aId.compareTo(bId);
    });
    int firstLines = -1;
    int lastLines = -1;
    int latestSabkiPara = 0;
    String latestSabkiRatio = '';
    int latestManzilPara = 0;
    String latestManzilRatio = '';

    for (var logDoc in sortedLogs) {
      Map<String, dynamic>? logData;
      if (logDoc is DocumentSnapshot) {
        logData = _asStringMap(logDoc.data());
      } else if (logDoc is Map) {
        logData = Map<String, dynamic>.from(logDoc);
      }
      if (logData == null || !logData.containsKey(sId)) continue;
      final studentLog = _asStringMap(logData[sId]);
      if (studentLog == null) continue;

      final currentLines = (studentLog['currentLines'] as num?)?.toInt() ?? int.tryParse(studentLog['currentLines']?.toString() ?? '');
      if (currentLines != null && currentLines > 0) {
        if (firstLines == -1) firstLines = currentLines;
        lastLines = currentLines;
      }

      final sabkiPara = (studentLog['sabkiPara'] as num?)?.toInt() ?? int.tryParse(studentLog['sabkiPara']?.toString() ?? '');
      final sabkiRatio = studentLog['sabkiRatio']?.toString();
      if (sabkiPara != null && sabkiPara > 0) {
        latestSabkiPara = sabkiPara;
        latestSabkiRatio = sabkiRatio ?? '';
      } else if (sabkiRatio == 'nahi_sunaya') {
        latestSabkiPara = 0;
        latestSabkiRatio = 'nahi_sunaya';
      }

      final manzilPara = (studentLog['manzilPara'] as num?)?.toInt() ?? int.tryParse(studentLog['manzilPara']?.toString() ?? '');
      final manzilRatio = studentLog['manzilRatio']?.toString();
      if (manzilPara != null && manzilPara > 0) {
        latestManzilPara = manzilPara;
        latestManzilRatio = manzilRatio ?? '';
      } else if (manzilRatio == 'nahi_sunaya') {
        latestManzilPara = 0;
        latestManzilRatio = 'nahi_sunaya';
      }
    }

    String formatRatio(String? ratio) {
      if (ratio == '1/4') return 'Pao (1/4) / پاؤ';
      if (ratio == '1/2') return 'Nisf (1/2) / نصف';
      if (ratio == '3/4') return 'Salasa (3/4) / ثلاثہ';
      if (ratio == '1') return 'Para (1) / پارہ';
      if (ratio == 'nahi_sunaya') return 'Did not recite / نہیں سنایا';
      return ratio ?? '-';
    }

    String sabkiMsg = 'No test recorded / کوئی ریکارڈ نہیں';
    if (latestSabkiPara > 0 && latestSabkiRatio.isNotEmpty && latestSabkiRatio != '-') {
      sabkiMsg = 'Para $latestSabkiPara (${formatRatio(latestSabkiRatio)}) / پارہ $latestSabkiPara (${formatRatio(latestSabkiRatio)})';
    } else if (latestSabkiRatio == 'nahi_sunaya') {
      sabkiMsg = 'Did not recite / نہیں سنایا';
    }

    String manzilMsg = 'No test recorded / کوئی ریکارڈ نہیں';
    if (latestManzilPara > 0 && latestManzilRatio.isNotEmpty && latestManzilRatio != '-') {
      manzilMsg = 'Para $latestManzilPara (${formatRatio(latestManzilRatio)}) / پارہ $latestManzilPara (${formatRatio(latestManzilRatio)})';
    } else if (latestManzilRatio == 'nahi_sunaya') {
      manzilMsg = 'Did not recite / نہیں سنایا';
    }

    int linesMemorized = 0;
    if (firstLines != -1 && lastLines != -1) {
      linesMemorized = (lastLines - firstLines).clamp(0, 99999);
    }
    String sabakMsg = '$linesMemorized lines / $linesMemorized لائنیں';
    if (lastLines != -1) {
      sabakMsg += ' (Cumulative Line: $lastLines / مجموعی لائن: $lastLines)';
    }

    // Financial/Attendance metrics
    final due = (fee['amountDue'] as num?)?.toStringAsFixed(0) ?? '0';
    final savings = (fee['totalSavings'] as num?)?.toStringAsFixed(0) ?? '0';
    final p = fee['present'] ?? 0;
    final l = fee['leave'] ?? 0;
    final a = fee['absent'] ?? 0;
    final ptmAttended = fee['ptm'] == true;

    final currentYear = _selectedYear ?? DateTime.now().year;
    final currentMonth = _selectedMonth ?? DateTime.now().month;
    final monthName = DateFormat('MMMM yyyy').format(DateTime(currentYear, currentMonth));
    final studentName = studentData['name'] ?? '—';
    final rollNumber = studentData['rollNumber'] ?? '?';

    final String message =
        '*Gulzar Madina Welfare Foundation (Madrassa)*\n'
        '*Monthly Progress Report | ماہانہ کارکردگی رپورٹ*\n'
        '--------------------------------------------\n'
        '*Month/مہینہ:* $monthName\n'
        '*Student/طالب علم:* $studentName (Roll: $rollNumber)\n'
        '*Attendance/حاضری:* Present: $p, Leave: $l, Absent: $a / حاضر: $p، رخصت: $l، غیر حاضر: $a\n'
        '*PTM Meeting/میٹنگ:* ${ptmAttended ? "Attended / شامل ہوئے" : "Missed / غیر حاضر"}\n'
        '\n'
        '*Monthly Progress / ماہانہ کارکردگی:*\n'
        '• *Sabak/سبق:* $sabakMsg\n'
        '• *Sabki/سبکی:* $sabkiMsg\n'
        '• *Manzil/منزل:* $manzilMsg\n'
        '\n'
        '*Financial Summary / مالیاتی رپورٹ:*\n'
        '• *Amount Due/قابل ادا رقم:* Rs. $due\n'
        '• *Total Savings/کل بچت:* Rs. $savings\n'
        '--------------------------------------------\n'
        'JazakAllah Khair! / جزاک اللہ خیر!';

    final waUri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');

    try {
      final success = await launchUrl(waUri, mode: LaunchMode.externalApplication);
      if (!success) {
        throw 'Could not launch URL';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp.')),
        );
      }
    }
  }

  Widget _colCell(Widget child, double width, {bool center = false}) {
    return SizedBox(
      width: width,
      child: center
          ? Center(child: child)
          : Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
  }

  Widget _tag(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}