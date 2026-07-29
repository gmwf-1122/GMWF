// lib/pages/office/attendance_tab.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/local_storage_service.dart';
import '../../services/local_biometric_service.dart';
import 'bulk_attendance_dialog.dart';
import 'bulk_individual_attendance_dialog.dart';
import 'shared_widgets.dart';

class AttendanceTab extends StatefulWidget {
  final String branchId;
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onAddEmployee;
  final String departmentFilter;

  const AttendanceTab({
    super.key,
    required this.branchId,
    required this.date,
    required this.onDateChanged,
    required this.onAddEmployee,
    this.departmentFilter = 'all',
  });

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  // Store local modifications before saving to DB
  final Map<String, Map<String, dynamic>> _draftRecords = {};
  String _selectedBranchFilter = 'all';
  String _selectedDeptFilter = 'all';

  @override
  void didUpdateWidget(covariant AttendanceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      _selectedBranchFilter = 'all';
      _selectedDeptFilter = 'all';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tOriginal = RoleThemeScope.dataOf(context);
    final t = RoleThemeData(
      roleLabel: tOriginal.roleLabel,
      isDarkCanvas: false,
      bg: const Color(0xFFF8FAFC),
      bgCard: Colors.white,
      bgCardAlt: const Color(0xFFF1F5F9),
      bgRule: const Color(0xFFE2E8F0),
      accent: const Color(0xFF10B981),
      accentLight: const Color(0xFF34D399),
      accentMuted: const Color(0xFFD1FAE5),
      accentGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
      glassTint: const Color(0x1A10B981),
      textPrimary: const Color(0xFF111827),
      textSecondary: const Color(0xFF6B7280),
      textTertiary: const Color(0xFF9CA3AF),
      danger: const Color(0xFFEF4444),
      zakat: tOriginal.zakat,
      nonZakat: tOriginal.nonZakat,
      gmwf: tOriginal.gmwf,
      cardFillTokens: tOriginal.cardFillTokens,
      cardFillPrescriptions: tOriginal.cardFillPrescriptions,
      cardFillDispensary: tOriginal.cardFillDispensary,
      chartBar1: tOriginal.chartBar1,
      chartBar2: tOriginal.chartBar2,
      chartBar3: tOriginal.chartBar3,
      chartGrid: tOriginal.chartGrid,
    );
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildDatePickerStrip(t),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: FinanceLocalStorage.attendanceBox.listenable(),
              builder: (ctx, Box box, _) {
                final allEmployeesOfBranch = FinanceLocalStorage.getEmployees(widget.branchId).where((e) => e['isActive'] == true).toList();

                final activeEmployees = allEmployeesOfBranch.where((e) {
                  if (widget.departmentFilter != 'all') {
                    final dept = e['department']?.toString() ?? 'Other';
                    final cleanDept = dept.trim().isEmpty ? 'Other' : dept.trim();
                    if (cleanDept.toLowerCase() != widget.departmentFilter.toLowerCase()) return false;
                  }

                  // Limit by Joining Date
                  final joinStr = e['joiningDate']?.toString();
                  if (joinStr != null && joinStr.isNotEmpty) {
                    final joinDate = DateTime.tryParse(joinStr);
                    if (joinDate != null) {
                      final joinDay = DateTime(joinDate.year, joinDate.month, joinDate.day);
                      final checkDay = DateTime(widget.date.year, widget.date.month, widget.date.day);
                      if (checkDay.isBefore(joinDay)) return false;
                    }
                  }
                  
                  // Limit by Exit Date
                  final exitStr = e['exitDate']?.toString();
                  if (exitStr != null && exitStr.isNotEmpty) {
                    final exitDate = DateTime.tryParse(exitStr);
                    if (exitDate != null) {
                      final exitDay = DateTime(exitDate.year, exitDate.month, exitDate.day);
                      final checkDay = DateTime(widget.date.year, widget.date.month, widget.date.day);
                      if (checkDay.isAfter(exitDay)) return false;
                    }
                  }
                  
                  return true;
                }).toList();

                if (allEmployeesOfBranch.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_outlined, size: 54, color: t.textTertiary),
                          const SizedBox(height: 14),
                          Text('No active employees found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textSecondary)),
                          const SizedBox(height: 6),
                          Text('Register a new employee to get started.', style: TextStyle(fontSize: 12, color: t.textTertiary), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: widget.onAddEmployee,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Employee', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (activeEmployees.isEmpty) {
                  return Column(
                    children: [
                      const SizedBox.shrink(),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.filter_list_off_outlined, size: 54, color: t.textTertiary),
                                const SizedBox(height: 14),
                                Text('No employees matching filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textSecondary)),
                                const SizedBox(height: 6),
                                Text('Try adjusting your filters to see more employees.', style: TextStyle(fontSize: 12, color: t.textTertiary), textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Load database records for today
                final dbRecords = FinanceLocalStorage.getAttendanceForDate(widget.branchId, dateStr);

                // Build working checklist
                final isSunday = widget.date.weekday == DateTime.sunday;
                final records = activeEmployees.map((emp) {
                  final empId = emp['localId']?.toString() ?? '';
                  final empDept = emp['department']?.toString() ?? '';
                  final dbRec = dbRecords.firstWhereOrNull((r) => r['employeeId'] == empId);

                  final isHoliday = FinanceLocalStorage.isHoliday(
                    branchId: widget.branchId,
                    department: empDept,
                    dateStr: dateStr,
                  );

                  // Prioritize draft records over DB records
                  final record = _draftRecords[empId] ?? Map<String, dynamic>.from(dbRec ?? {
                    'employeeId': empId,
                    'date': dateStr,
                    'status': isSunday ? 'off' : (isHoliday ? 'holiday' : 'absent'),
                    'leaveType': null,
                    'arrivalTime': null,
                    'departureTime': null,
                    'note': isHoliday ? 'Public Holiday' : null,
                    'overtimeDuration': null,
                    'halfDayType': null,
                  });
                  record['name'] = emp['name']; // cache name for drawing card
                  record['role'] = emp['role'];
                  record['createdBy'] = emp['createdBy'];
                  record['department'] = emp['department'];
                  return record;
                }).toList();

                // Compute header counts
                int present = records.where((r) => r['status'] == 'present').length;
                int late = records.where((r) => r['status'] == 'late').length;
                int leave = records.where((r) => r['status'] == 'leave').length;
                int absent = records.where((r) => r['status'] == 'absent').length;
                int overtime = records.where((r) => r['status'] == 'overtime').length;
                int holiday = records.where((r) => r['status'] == 'holiday').length;

                // Group by department
                final Map<String, List<Map<String, dynamic>>> grouped = {};
                for (final r in records) {
                  final dept = r['department']?.toString() ?? 'Other';
                  final cleanDept = dept.trim().isEmpty ? 'Other' : dept.trim();
                  grouped.putIfAbsent(cleanDept, () => []).add(r);
                }

                final List<Map<String, dynamic>> displayItems = [];
                grouped.forEach((deptName, list) {
                  displayItems.add({'isHeader': true, 'departmentName': deptName, 'count': list.length});
                  for (final r in list) {
                    displayItems.add(r);
                  }
                });

                return Column(
                  children: [
                    _buildSummaryStrip(
                      p: present,
                      lat: late,
                      lv: leave,
                      a: absent,
                      ot: overtime,
                      isSunday: isSunday,
                      t: t,
                      hol: holiday,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (layoutCtx, constraints) {
                          final isWide = constraints.maxWidth >= 900;
                          return Column(children: [
                            if (isWide)
                              Container(
                                color: const Color(0xFFF9FAFB),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: const Row(children: [
                                  SizedBox(width: 42),
                                  SizedBox(width: 12),
                                  Expanded(child: Text('EMPLOYEE', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                                  Text('STATUS', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                                  SizedBox(width: 44),
                                ]),
                              ),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 60),
                                itemCount: displayItems.length,
                                itemBuilder: (c, idx) {
                                  final item = displayItems[idx];
                                  if (item['isHeader'] == true) {
                                    return _buildDepartmentHeader(item['departmentName'] as String, item['count'] as int, t);
                                  }
                                  return isWide
                                      ? _buildCompactAttendanceRow(item, t)
                                      : _buildAttendanceCard(item, t);
                                },
                              ),
                            ),
                          ]);
                        },
                      ),
                    ),
                    _buildSaveButton(records, t),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentHeader(String department, int count, RoleThemeData t) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 20.0, bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                department.toUpperCase(),
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: t.accentMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: t.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
        ],
      ),
    );
  }



  Widget _buildDatePickerStrip(RoleThemeData t) {
    final today = DateTime.now();
    final isToday = widget.date.year == today.year &&
        widget.date.month == today.month &&
        widget.date.day == today.day;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: LayoutBuilder(builder: (_, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final dateRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.chevron_left, color: Color(0xFF374151), size: 20),
              onPressed: () {
                _draftRecords.clear();
                widget.onDateChanged(widget.date.subtract(const Duration(days: 1)));
              },
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: widget.date,
                  firstDate: DateTime(2025),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) { _draftRecords.clear(); widget.onDateChanged(picked); }
              },
              borderRadius: BorderRadius.circular(6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_month_rounded, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, dd MMMM yyyy').format(widget.date),
                  style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ]),
            ),
            const SizedBox(width: 4),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.chevron_right, color: Color(0xFF374151), size: 20),
              onPressed: () {
                _draftRecords.clear();
                widget.onDateChanged(widget.date.add(const Duration(days: 1)));
              },
            ),
          ],
        );

        final chips = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (!isToday)
              _dateChip('+ Today', Icons.today_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5),
                  () { _draftRecords.clear(); widget.onDateChanged(DateTime.now()); }),
            if (isToday)
              _dateChip('Today', Icons.circle, const Color(0xFF10B981), const Color(0xFFECFDF5), null),
            _dateChip('Leave Range', Icons.date_range_rounded, Colors.blue, const Color(0xFFEFF6FF),
                () => _openLeaveRangeDialog(context, t)),
            _dateChip('Bulk Month Entry', Icons.fact_check_outlined, Colors.purple, const Color(0xFFF5F3FF),
                () => BulkAttendanceDialog.open(context: context, branchId: widget.branchId, theme: t, onSaved: () => setState(() {}))),
            _dateChip('Bulk Indiv. Entry', Icons.person_add_alt_1_outlined, Colors.teal, const Color(0xFFE6F4F1),
                () => BulkIndividualAttendanceDialog.open(context: context, branchId: widget.branchId, theme: t, onSaved: () => setState(() {}))),
            _dateChip('Add Employee', Icons.person_add_alt_1_outlined, const Color(0xFF10B981), const Color(0xFFECFDF5),
                widget.onAddEmployee),
          ],
        );

        if (isNarrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            dateRow,
            const SizedBox(height: 8),
            chips,
          ]);
        }
        return Row(children: [
          dateRow,
          const SizedBox(width: 12),
          chips,
        ]);
      }),
    );
  }

  Widget _dateChip(String label, IconData icon, Color color, Color bg, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _buildSummaryStrip({
    required int p,
    required int lat,
    required int lv,
    required int a,
    required int ot,
    required bool isSunday,
    required RoleThemeData t,
    int hol = 0,
  }) {
    if (isSunday) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Row(children: [
          Expanded(child: _statCard('Weekend Off', p + lat + lv + a, Icons.weekend_outlined, const Color(0xFF6B7280), const Color(0xFFF3F4F6))),
          const SizedBox(width: 10),
          Expanded(child: _statCard('Working Overtime', ot, Icons.more_time_outlined, Colors.teal, const Color(0xFFCCFBF1))),
        ]),
      );
    }
    return LayoutBuilder(builder: (_, constraints) {
      final isNarrow = constraints.maxWidth < 600;
      final cards = [
        _statCard('Present', p, Icons.person_rounded, const Color(0xFF10B981), const Color(0xFFD1FAE5)),
        _statCard('Late', lat, Icons.access_time_rounded, const Color(0xFFF59E0B), const Color(0xFFFEF3C7)),
        _statCard('Leave', lv, Icons.event_busy_rounded, const Color(0xFF3B82F6), const Color(0xFFDBEAFE)),
        _statCard('Absent', a, Icons.person_off_rounded, const Color(0xFFEF4444), const Color(0xFFFEE2E2)),
        if (hol > 0) _statCard('Holiday', hol, Icons.celebration_rounded, Colors.indigo, const Color(0xFFE0E7FF)),
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: isNarrow
            ? Wrap(spacing: 8, runSpacing: 8, children: cards.map((c) => SizedBox(width: (constraints.maxWidth - 22) / 2, child: c)).toList())
            : Row(children: cards.map((c) => Expanded(child: c)).toList()
                .fold<List<Widget>>([], (list, w) => list.isEmpty ? [w] : [...list, const SizedBox(width: 10), w])),
      );
    });
  }

  Widget _statCard(String label, int val, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text('$val', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 22, height: 1.1)),
          const Text('employees', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 9)),
        ])),
      ]),
    );
  }

  // kept for compatibility (not called in new design but preserves the old interface)
  Widget _buildSummaryItem(String label, int val, Color color, RoleThemeData t) {
    return Column(children: [
      Text(label, style: TextStyle(color: t.textTertiary, fontSize: 11)),
      const SizedBox(height: 2),
      Text('$val', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
    ]);
  }

  Widget _buildSundayOvertimeControls(Map<String, dynamic> record, String empId, RoleThemeData t) {
    final status = record['status']?.toString() ?? 'off';
    final isOt = status == 'overtime';
    final duration = record['overtimeDuration']?.toString() ?? 'full';

    return Row(
      children: [
        Text('Overtime: ', style: TextStyle(color: t.textSecondary, fontSize: 12)),
        const SizedBox(width: 4),
        SizedBox(
          height: 28,
          child: Row(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: !isOt ? Colors.grey[600] : t.bgCardAlt,
                  foregroundColor: !isOt ? Colors.white : t.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                    side: BorderSide(color: !isOt ? Colors.grey[600]! : t.bgRule, width: 0.5),
                  ),
                ),
                onPressed: () async {
                  setState(() {
                    record['status'] = 'off';
                    record['overtimeDuration'] = null;
                  });
                  await _saveRecordInstantly(empId, record);
                },
                child: const Text('NO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOt ? Colors.teal : t.bgCardAlt,
                  foregroundColor: isOt ? Colors.white : t.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                    side: BorderSide(color: isOt ? Colors.teal : t.bgRule, width: 0.5),
                  ),
                ),
                onPressed: () async {
                  setState(() {
                    record['status'] = 'overtime';
                    record['overtimeDuration'] = 'full';
                  });
                  await _saveRecordInstantly(empId, record);
                },
                child: const Text('YES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        if (isOt) ...[
          const SizedBox(width: 12),
          SizedBox(
            height: 28,
            child: Row(
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: duration == 'full' ? Colors.teal[700] : t.bgCardAlt,
                    foregroundColor: duration == 'full' ? Colors.white : t.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                      side: BorderSide(color: duration == 'full' ? Colors.teal[700]! : t.bgRule, width: 0.5),
                    ),
                  ),
                  onPressed: () async {
                    setState(() {
                      record['overtimeDuration'] = 'full';
                    });
                    await _saveRecordInstantly(empId, record);
                  },
                  child: const Text('Full Day', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: duration == 'half' ? Colors.teal[400] : t.bgCardAlt,
                    foregroundColor: duration == 'half' ? Colors.white : t.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                      side: BorderSide(color: duration == 'half' ? Colors.teal[400]! : t.bgRule, width: 0.5),
                    ),
                  ),
                  onPressed: () async {
                    setState(() {
                      record['overtimeDuration'] = 'half';
                    });
                    await _saveRecordInstantly(empId, record);
                  },
                  child: const Text('Half Day', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactAttendanceRow(Map<String, dynamic> record, RoleThemeData t) {
    final empId = record['employeeId']?.toString() ?? '';
    final name = record['name']?.toString() ?? '';
    final role = record['role']?.toString() ?? 'Employee';
    final dept = record['department']?.toString() ?? '';
    final status = record['status']?.toString() ?? 'absent';
    final isSunday = widget.date.weekday == DateTime.sunday;
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
    final note = record['note']?.toString() ?? '';
    final isHoliday = FinanceLocalStorage.isHoliday(branchId: widget.branchId, department: dept, dateStr: dateStr);

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.5)),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFD1FAE5),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          // Name + role
          Expanded(
            child: InkWell(
              onTap: () => _showEmployeeDetailSheet(context, empId, t),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text(name, style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 13)),
                  if (isHoliday) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFCCFBF1), borderRadius: BorderRadius.circular(4)),
                      child: const Text('Holiday', style: TextStyle(color: Colors.teal, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
                Text('$role • $dept', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          // Status buttons
          isSunday
              ? _buildSundayOvertimeControls(record, empId, t)
              : Wrap(
                  spacing: 4,
                  children: [
                    _buildStatusButton('P', 'present', status, const Color(0xFF10B981), t, empId, record),
                    _buildStatusButton('L', 'late', status, const Color(0xFFF59E0B), t, empId, record),
                    _buildStatusButton('Lv', 'leave', status, const Color(0xFF3B82F6), t, empId, record),
                    _buildStatusButton('HD', 'half_day', status, Colors.teal, t, empId, record),
                    _buildStatusButton('A', 'absent', status, const Color(0xFFEF4444), t, empId, record),
                    if (isHoliday)
                      _buildStatusButton('H', 'holiday', status, Colors.indigo, t, empId, record),
                  ],
                ),
          // Note icon
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(note.isNotEmpty ? Icons.sticky_note_2 : Icons.note_add_outlined,
                size: 16, color: note.isNotEmpty ? const Color(0xFF10B981) : const Color(0xFF9CA3AF)),
            tooltip: note.isNotEmpty ? note : 'Add note',
            onPressed: () => _editNoteDialog(context, empId, record, t),
          ),
        ],
      ),
    );
  }

  void _editNoteDialog(BuildContext context, String empId, Map<String, dynamic> record, RoleThemeData t) {
    final ctrl = TextEditingController(text: record['note']?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bgCard,
        title: Text('Note for ${record['name']}', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 3, style: TextStyle(color: t.textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: t.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: t.accent),
            onPressed: () async {
              record['note'] = ctrl.text.trim();
              Navigator.pop(ctx);
              setState(() {});
              await _saveRecordInstantly(empId, record);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> record, RoleThemeData t) {
    final empId = record['employeeId']?.toString() ?? '';
    final name = record['name']?.toString() ?? '';
    final role = record['role']?.toString() ?? 'Employee';
    final createdBy = record['createdBy']?.toString() ?? 'System';
    final status = record['status']?.toString() ?? 'absent';
    final arrival = record['arrivalTime']?.toString() ?? '';
    final departure = record['departureTime']?.toString() ?? '';
    final note = record['note']?.toString() ?? '';
    final isSunday = widget.date.weekday == DateTime.sunday;
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);

    Color statusColor = Colors.grey;
    if (status == 'present') statusColor = Colors.green;
    else if (status == 'late') statusColor = Colors.orange;
    else if (status == 'leave') statusColor = Colors.blue;
    else if (status == 'half_day') statusColor = Colors.teal;
    else if (status == 'absent') statusColor = Colors.red;
    else if (status == 'holiday') statusColor = Colors.indigo;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                color: isSunday ? Colors.grey : statusColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showEmployeeDetailSheet(context, empId, t),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(name, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 6),
                            Icon(Icons.info_outline, size: 13, color: t.accent),
                            if (FinanceLocalStorage.isHoliday(
                              branchId: widget.branchId,
                              department: record['department']?.toString() ?? '',
                              dateStr: dateStr,
                            )) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                                ),
                                child: const Text(
                                  'Holiday',
                                  style: TextStyle(color: Colors.teal, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSunday ? '$role • Sunday Weekend' : '$role • Added by: $createdBy',
                          style: TextStyle(color: t.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isSunday)
                _buildSundayOvertimeControls(record, empId, t)
              else
                Row(
                  children: [
                    _buildStatusButton('P', 'present', status, Colors.green, t, empId, record),
                    _buildStatusButton('L', 'late', status, Colors.orange, t, empId, record),
                    _buildStatusButton('Lv', 'leave', status, Colors.blue, t, empId, record),
                    _buildStatusButton('HD', 'half_day', status, Colors.teal, t, empId, record),
                    _buildStatusButton('A', 'absent', status, Colors.red, t, empId, record),
                    if (FinanceLocalStorage.isHoliday(
                      branchId: widget.branchId,
                      department: record['department']?.toString() ?? '',
                      dateStr: dateStr,
                    ))
                      _buildStatusButton('H', 'holiday', status, Colors.indigo, t, empId, record),
                  ],
                )
            ],
          ),
          if (!isSunday && (status == 'present' || status == 'late')) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(context, (time) async {
                      setState(() {
                        record['arrivalTime'] = time;
                      });
                      await _saveRecordInstantly(empId, record);
                    }),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.bgRule)),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: t.textTertiary),
                          const SizedBox(width: 6),
                          Text(arrival.isNotEmpty ? 'In: $arrival' : 'Set Arrival', style: TextStyle(color: t.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(context, (time) async {
                      setState(() {
                        record['departureTime'] = time;
                      });
                      await _saveRecordInstantly(empId, record);
                    }),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.bgRule)),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: t.textTertiary),
                          const SizedBox(width: 6),
                          Text(departure.isNotEmpty ? 'Out: $departure' : 'Set Departure', style: TextStyle(color: t.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!isSunday && status == 'leave') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Leave type: ', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: record['leaveType'] ?? 'sick',
                  dropdownColor: t.bgCard,
                  style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  items: ['sick', 'casual', 'annual', 'unpaid'].map((lt) => DropdownMenuItem(value: lt, child: Text(lt.toUpperCase()))).toList(),
                  onChanged: (val) async {
                    setState(() {
                      record['leaveType'] = val;
                    });
                    await _saveRecordInstantly(empId, record);
                  },
                ),

              ],
            )
          ],
          if (!isSunday && status == 'half_day') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Half-day type: ', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: record['halfDayType'] ?? 'unpaid',
                  dropdownColor: t.bgCard,
                  style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  items: ['unpaid', 'paid'].map((lt) => DropdownMenuItem(value: lt, child: Text(lt.toUpperCase()))).toList(),
                  onChanged: (val) async {
                    setState(() {
                      record['halfDayType'] = val;
                    });
                    await _saveRecordInstantly(empId, record);
                  },
                ),
              ],
            )
          ],
          const SizedBox(height: 6),
          // Note field
          TextField(
            style: TextStyle(color: t.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Add remarks...',
              hintStyle: TextStyle(color: t.textTertiary, fontSize: 11),
              isDense: true,
              border: InputBorder.none,
            ),
            controller: TextEditingController(text: note)..selection = TextSelection.fromPosition(TextPosition(offset: note.length)),
            onChanged: (val) {
              record['note'] = val;
              _draftRecords[empId] = record;
            },
            onSubmitted: (val) async {
              record['note'] = val;
              await _saveRecordInstantly(empId, record);
            },
            onTapOutside: (event) async {
              await _saveRecordInstantly(empId, record);
            },
          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildStatusButton(
    String label,
    String targetStatus,
    String currentStatus,
    Color activeColor,
    RoleThemeData t,
    String empId,
    Map<String, dynamic> record,
  ) {
    final active = currentStatus == targetStatus;
    final tip = targetStatus == 'half_day' ? 'Half Day' : targetStatus[0].toUpperCase() + targetStatus.substring(1);
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: () async {
          setState(() {
            record['status'] = targetStatus;
            record['leaveType'] = targetStatus == 'leave' ? 'sick' : null;
            record['halfDayType'] = targetStatus == 'half_day' ? 'unpaid' : null;
            if (targetStatus != 'present' && targetStatus != 'late') {
              record['arrivalTime'] = null;
              record['departureTime'] = null;
            }
          });
          await _saveRecordInstantly(empId, record);
        },
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active ? activeColor : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? activeColor : const Color(0xFFE5E7EB), width: active ? 1.5 : 0.75),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime(BuildContext context, ValueChanged<String> onPicked) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      if (context.mounted) {
        onPicked(picked.format(context));
      }
    }
  }

  Widget _buildSaveButton(List<Map<String, dynamic>> records, RoleThemeData t) {
    return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.bgCard, border: Border(top: BorderSide(color: t.bgRule))),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () async {
          try {
            final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
            
            for (final r in _draftRecords.values) {
              await FinanceLocalStorage.saveAttendanceRecord(
                branchId: widget.branchId,
                data: r,
                performedBy: curUser,
              );
            }

            // Write summary Audit log
            await FinanceLocalStorage.logAction(
              branchId: widget.branchId,
              entityType: 'attendance',
              entityId: DateFormat('yyyy-MM-dd').format(widget.date),
              action: 'update',
              performedBy: curUser,
              reason: 'Marked daily attendance sheets for ${_draftRecords.length} employees.',
            );

            setState(() {
              _draftRecords.clear();
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Attendance sheet saved successfully!'),
                backgroundColor: t.accent,
                behavior: SnackBarBehavior.floating,
              ));
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Failed to save attendance: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ));
            }
          }
        },
        child: Text('Save Attendance Sheet (${_draftRecords.length} changes)', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showEmployeeDetailSheet(BuildContext context, String employeeId, RoleThemeData t) {
    final emp = FinanceLocalStorage.getEmployee(employeeId);
    if (emp == null) return;

    final name = emp['name']?.toString() ?? '';
    final role = emp['role']?.toString() ?? '';
    final dept = emp['department']?.toString() ?? '';
    final cnic = emp['cnic']?.toString() ?? '';
    final phone = emp['phone']?.toString() ?? '';
    final altPhone = emp['alternatePhone']?.toString() ?? '';
    final address = emp['currentAddress']?.toString() ?? '';
    final joiningDate = emp['joiningDate']?.toString() ?? 'N/A';
    final salary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
    final advance = (emp['currentAdvanceBalance'] as num?)?.toDouble() ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
                        Text('$role • $dept', style: TextStyle(fontSize: 12, color: t.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: t.bgRule, height: 1),
              const SizedBox(height: 16),
              _buildDetailItem('Phone Number', phone.isNotEmpty ? phone : 'N/A', Icons.phone, t),
              if (altPhone.isNotEmpty)
                _buildDetailItem('Alternate Phone', altPhone, Icons.phone_android, t),
              _buildDetailItem('CNIC Number', cnic.isNotEmpty ? cnic : 'N/A', Icons.badge, t),
              _buildDetailItem('Joining Date', joiningDate, Icons.calendar_today, t),
              _buildDetailItem('Current Base Salary', 'PKR ${NumberFormat('#,###').format(salary)}', Icons.payments, t),
              _buildDetailItem('Advance Balance Owed', 'PKR ${NumberFormat('#,###').format(advance)}', Icons.money_off, t),
              if (address.isNotEmpty)
                _buildDetailItem('Current Address', address, Icons.home, t),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveRecordInstantly(String empId, Map<String, dynamic> record) async {
    try {
      final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
      await FinanceLocalStorage.saveAttendanceRecord(
        branchId: widget.branchId,
        data: record,
        performedBy: curUser,
      );
      _draftRecords.remove(empId);
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(context, e.toString().replaceAll('Exception: ', ''), error: true);
        setState(() {});
      }
    }
  }

  void _openLeaveRangeDialog(BuildContext context, RoleThemeData t) {
    final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
    final employees = FinanceLocalStorage.getEmployees(widget.branchId).where((e) => e['isActive'] == true).toList();
    
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active employees available.')));
      return;
    }

    String selectedEmployeeId = employees.first['localId']?.toString() ?? '';
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    String selectedStatus = 'leave';
    String selectedLeaveType = 'sick';
    final remarksCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (diagCtx, setDiagState) {
            return AlertDialog(
              backgroundColor: t.bgCard,
              title: Text('Apply Leave / Absent Range', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select Employee:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      dropdownColor: t.bgCard,
                      value: selectedEmployeeId,
                      style: TextStyle(color: t.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: t.bgCardAlt,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                      ),
                      items: employees.map((emp) {
                        return DropdownMenuItem<String>(
                          value: emp['localId']?.toString() ?? '',
                          child: Text('${emp['name']} (${emp['role']})', style: TextStyle(color: t.textPrimary)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDiagState(() => selectedEmployeeId = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Status:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      dropdownColor: t.bgCard,
                      value: selectedStatus,
                      style: TextStyle(color: t.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: t.bgCardAlt,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        DropdownMenuItem(value: 'leave', child: Text('Leave', style: TextStyle(color: t.textPrimary))),
                        DropdownMenuItem(value: 'absent', child: Text('Absent', style: TextStyle(color: t.textPrimary))),
                      ],
                      onChanged: (val) {
                        if (val != null) setDiagState(() => selectedStatus = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (selectedStatus == 'leave') ...[
                      Text('Leave Type:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        dropdownColor: t.bgCard,
                        value: selectedLeaveType,
                        style: TextStyle(color: t.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: t.bgCardAlt,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        ),
                        items: [
                          DropdownMenuItem(value: 'sick', child: Text('SICK', style: TextStyle(color: t.textPrimary))),
                          DropdownMenuItem(value: 'casual', child: Text('CASUAL', style: TextStyle(color: t.textPrimary))),
                          DropdownMenuItem(value: 'annual', child: Text('ANNUAL', style: TextStyle(color: t.textPrimary))),
                          DropdownMenuItem(value: 'unpaid', child: Text('UNPAID', style: TextStyle(color: t.textPrimary))),
                        ],
                        onChanged: (val) {
                          if (val != null) setDiagState(() => selectedLeaveType = val);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Start Date:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2025),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDiagState(() {
                            startDate = picked;
                            if (endDate.isBefore(startDate)) {
                              endDate = startDate;
                            }
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(border: Border.all(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('yyyy-MM-dd').format(startDate), style: TextStyle(color: t.textPrimary, fontSize: 13)),
                            Icon(Icons.calendar_today, size: 16, color: t.textTertiary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('End Date:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endDate.isBefore(startDate) ? startDate : endDate,
                          firstDate: startDate,
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDiagState(() => endDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(border: Border.all(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('yyyy-MM-dd').format(endDate), style: TextStyle(color: t.textPrimary, fontSize: 13)),
                            Icon(Icons.calendar_today, size: 16, color: t.textTertiary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Remarks / Note:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarksCtrl,
                      style: TextStyle(color: t.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: t.bgCardAlt,
                        hintText: 'Enter reason or notes...',
                        hintStyle: TextStyle(color: t.textTertiary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: t.accent), borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: t.accent),
                  onPressed: () async {
                    try {
                      int count = 0;
                      var curr = DateTime(startDate.year, startDate.month, startDate.day);
                      final limit = DateTime(endDate.year, endDate.month, endDate.day);

                      while (curr.isBefore(limit) || curr.isAtSameMomentAs(limit)) {
                        final dateStr = DateFormat('yyyy-MM-dd').format(curr);
                        final record = {
                          'employeeId': selectedEmployeeId,
                          'date': dateStr,
                          'status': selectedStatus,
                          'leaveType': selectedStatus == 'leave' ? selectedLeaveType : null,
                          'note': remarksCtrl.text.trim().isNotEmpty ? remarksCtrl.text.trim() : 'Applied range leave',
                        };
                        await FinanceLocalStorage.saveAttendanceRecord(
                          branchId: widget.branchId,
                          data: record,
                          performedBy: curUser,
                        );
                        count++;
                        curr = curr.add(const Duration(days: 1));
                      }

                      await FinanceLocalStorage.logAction(
                        branchId: widget.branchId,
                        entityType: 'attendance',
                        entityId: selectedEmployeeId,
                        action: 'leave_range',
                        performedBy: curUser,
                        reason: 'Recorded $count days range ($selectedStatus) from ${DateFormat('yyyy-MM-dd').format(startDate)} to ${DateFormat('yyyy-MM-dd').format(endDate)}',
                      );

                      Navigator.pop(ctx);
                      if (mounted) {
                        setState(() {});
                        showCustomSnackBar(context, 'Successfully applied $count days range.');
                      }
                    } catch (e) {
                      showCustomSnackBar(ctx, e.toString().replaceAll('Exception: ', ''), error: true);
                    }
                  },
                  child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon, RoleThemeData t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: t.textTertiary)),
                Text(value, style: TextStyle(fontSize: 13, color: t.textPrimary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMobileBiometricCheckIn(Map<String, dynamic> record, RoleThemeData t) async {
    final empName = record['employeeName']?.toString() ?? 'Employee';
    final empId = record['employeeId']?.toString() ?? '';

    final isAuthenticated = await LocalBiometricService.authenticateUser(
      localizedReason: 'Scan fingerprint to verify attendance for $empName',
    );

    if (!isAuthenticated) {
      if (mounted) {
        showCustomSnackBar(context, 'Biometric verification cancelled or failed.', error: true);
      }
      return;
    }

    final now = DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(now);

    final updatedRecord = Map<String, dynamic>.from(record);
    if (updatedRecord['status'] != 'present') {
      updatedRecord['status'] = 'present';
      updatedRecord['checkInTime'] = timeStr;
      updatedRecord['source'] = 'Mobile App (Android Fingerprint)';
    } else {
      updatedRecord['checkOutTime'] = timeStr;
    }

    await FinanceLocalStorage.saveAttendanceRecord(
      branchId: widget.branchId,
      data: updatedRecord,
      performedBy: 'Mobile Biometric',
    );

    if (mounted) {
      setState(() {
        _draftRecords[empId] = updatedRecord;
      });
      showCustomSnackBar(context, '✅ Attendance marked for $empName via Mobile Fingerprint ($timeStr)');
    }
  }
}
