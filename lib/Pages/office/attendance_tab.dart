// lib/pages/office/attendance_tab.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import 'bulk_attendance_dialog.dart';

class AttendanceTab extends StatefulWidget {
  final String branchId;
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onAddEmployee;

  const AttendanceTab({
    super.key,
    required this.branchId,
    required this.date,
    required this.onDateChanged,
    required this.onAddEmployee,
  });

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  // Store local modifications before saving to DB
  final Map<String, Map<String, dynamic>> _draftRecords = {};

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildDatePickerStrip(t),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: FinanceLocalStorage.attendanceBox.listenable(),
              builder: (ctx, Box box, _) {
                final activeEmployees = FinanceLocalStorage.getEmployees(widget.branchId).where((e) {
                  if (e['isActive'] != true) return false;
                  
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
                if (activeEmployees.isEmpty) {
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
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            itemCount: records.length,
                            itemBuilder: (c, idx) {
                              return isWide
                                  ? _buildCompactAttendanceRow(records[idx], t)
                                  : _buildAttendanceCard(records[idx], t);
                            },
                          );
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
      floatingActionButton: _draftRecords.isEmpty
          ? FloatingActionButton.extended(
              onPressed: widget.onAddEmployee,
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Employee', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildDatePickerStrip(RoleThemeData t) {
    return Container(
      color: t.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: t.textPrimary),
            onPressed: () {
              _draftRecords.clear();
              widget.onDateChanged(widget.date.subtract(const Duration(days: 1)));
            },
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: widget.date,
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    _draftRecords.clear();
                    widget.onDateChanged(picked);
                  }
                },
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: t.accent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEEE, dd MMMM yyyy').format(widget.date),
                      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Builder(builder: (context) {
                final today = DateTime.now();
                final isToday = widget.date.year == today.year &&
                    widget.date.month == today.month &&
                    widget.date.day == today.day;
                if (isToday) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: t.accent.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text('Today', style: TextStyle(color: t.accent, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5)),
                      ],
                    ),
                  );
                }
                return InkWell(
                  onTap: () {
                    _draftRecords.clear();
                    widget.onDateChanged(DateTime.now());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: t.accent.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.today_outlined, size: 10, color: t.accent),
                        const SizedBox(width: 4),
                        Text('GO TO TODAY', style: TextStyle(color: t.accent, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => _openLeaveRangeDialog(context, t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.date_range, size: 10, color: Colors.blue),
                      SizedBox(width: 4),
                      Text(
                        'LEAVE RANGE',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => BulkAttendanceDialog.open(
                  context: context,
                  branchId: widget.branchId,
                  theme: t,
                  onSaved: () => setState(() {}),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.fact_check_outlined, size: 10, color: Colors.purple),
                      SizedBox(width: 4),
                      Text(
                        'BULK MONTH ENTRY',
                        style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: t.textPrimary),
            onPressed: () {
              _draftRecords.clear();
              widget.onDateChanged(widget.date.add(const Duration(days: 1)));
            },
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: t.bgCardAlt,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: isSunday
            ? [
                _buildSummaryItem('Weekend Off', p + lat + lv + a, t.textSecondary, t),
                _buildSummaryItem('Working Overtime', ot, Colors.teal, t),
              ]
            : [
                _buildSummaryItem('Present', p, Colors.green, t),
                _buildSummaryItem('Late', lat, Colors.orange, t),
                _buildSummaryItem('Leave', lv, Colors.blue, t),
                _buildSummaryItem('Absent', a, Colors.red, t),
                if (hol > 0) _buildSummaryItem('Holiday Off', hol, Colors.teal, t),
              ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int val, Color color, RoleThemeData t) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: t.textTertiary, fontSize: 11)),
        const SizedBox(height: 2),
        Text('$val', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
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
    final status = record['status']?.toString() ?? 'absent';
    final isSunday = widget.date.weekday == DateTime.sunday;
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
    final note = record['note']?.toString() ?? '';

    Color statusColor = Colors.grey;
    if (status == 'present') statusColor = Colors.green;
    else if (status == 'late') statusColor = Colors.orange;
    else if (status == 'leave') statusColor = Colors.blue;
    else if (status == 'half_day') statusColor = Colors.teal;
    else if (status == 'absent') statusColor = Colors.red;
    else if (status == 'holiday') statusColor = Colors.indigo;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.bgRule, width: 0.5),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 32, color: isSunday ? Colors.grey : statusColor, margin: const EdgeInsets.only(right: 10)),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => _showEmployeeDetailSheet(context, empId, t),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(role, style: TextStyle(color: t.textTertiary, fontSize: 10)),
                ],
              ),
            ),
          ),
          if (FinanceLocalStorage.isHoliday(branchId: widget.branchId, department: record['department']?.toString() ?? '', dateStr: dateStr))
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: const Text('Holiday', style: TextStyle(color: Colors.teal, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          Expanded(
            flex: 4,
            child: isSunday
                ? _buildSundayOvertimeControls(record, empId, t)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusButton('P', 'present', status, Colors.green, t, empId, record),
                      _buildStatusButton('L', 'late', status, Colors.orange, t, empId, record),
                      _buildStatusButton('Lv', 'leave', status, Colors.blue, t, empId, record),
                      _buildStatusButton('HD', 'half_day', status, Colors.teal, t, empId, record),
                      _buildStatusButton('A', 'absent', status, Colors.red, t, empId, record),
                      if (FinanceLocalStorage.isHoliday(branchId: widget.branchId, department: record['department']?.toString() ?? '', dateStr: dateStr))
                        _buildStatusButton('H', 'holiday', status, Colors.indigo, t, empId, record),
                    ],
                  ),
          ),
          IconButton(
            icon: Icon(note.isNotEmpty ? Icons.sticky_note_2 : Icons.note_add_outlined, size: 16, color: note.isNotEmpty ? t.accent : t.textTertiary),
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
    return Container(
      margin: const EdgeInsets.only(left: 6),
      height: 32,
      width: 36,
      child: Tooltip(
        message: targetStatus == 'half_day' ? 'Half Day' : targetStatus.toUpperCase(),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: active ? activeColor : t.bgCardAlt,
            foregroundColor: active ? Colors.white : t.textSecondary,
            padding: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: active ? activeColor : t.bgRule, width: 0.5),
            ),
          ),
          onPressed: () async {
            setState(() {
              record['status'] = targetStatus;
              if (targetStatus == 'leave') {
                record['leaveType'] = 'sick';
              } else {
                record['leaveType'] = null;
              }
              if (targetStatus == 'half_day') {
                record['halfDayType'] = 'unpaid';
              } else {
                record['halfDayType'] = null;
              }
              if (targetStatus != 'present' && targetStatus != 'late') {
                record['arrivalTime'] = null;
                record['departureTime'] = null;
              }
            });
            await _saveRecordInstantly(empId, record);
          },
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
    } catch (_) {}
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
                    Navigator.pop(ctx);
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
                      action: 'update',
                      performedBy: curUser,
                      reason: 'Marked $count days as $selectedStatus for employee: $selectedEmployeeId.',
                    );

                    setState(() {});
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Successfully applied $count days $selectedStatus!'),
                        backgroundColor: t.accent,
                        behavior: SnackBarBehavior.floating,
                      ));
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
}
