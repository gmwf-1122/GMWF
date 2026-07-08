// lib/pages/office/bulk_attendance_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';

class BulkAttendanceDialog {
  static void open({
    required BuildContext context,
    required String branchId,
    required RoleThemeData theme,
    VoidCallback? onSaved,
  }) {
    final t = theme;
    DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final Map<String, TextEditingController> absentCtrls = {};
    final Map<String, TextEditingController> leaveCtrls = {};
    final Map<String, String> leaveTypes = {};
    bool isSaving = false;
    String statusMessage = '';

    final employees = FinanceLocalStorage.getEmployees(branchId).where((e) => e['isActive'] == true).toList();
    for (final e in employees) {
      final id = e['localId']?.toString() ?? '';
      absentCtrls[id] = TextEditingController(text: '0');
      leaveCtrls[id] = TextEditingController(text: '0');
      leaveTypes[id] = 'sick';
    }

    List<DateTime> eligibleDays(String department) {
      final monthStart = DateTime(selectedMonth.year, selectedMonth.month, 1);
      final monthEnd = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
      final today = DateTime.now();
      final todayLimit = DateTime(today.year, today.month, today.day);
      final days = <DateTime>[];
      var d = monthStart;
      while (!d.isAfter(monthEnd)) {
        final dateStr = DateFormat('yyyy-MM-dd').format(d);
        final isFuture = d.isAfter(todayLimit);
        final isSunday = d.weekday == DateTime.sunday;
        final isHol = FinanceLocalStorage.isHoliday(branchId: branchId, department: department, dateStr: dateStr);
        if (!isFuture && !isSunday && !isHol) days.add(d);
        d = d.add(const Duration(days: 1));
      }
      return days;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (diagCtx, setDiagState) {
            Future<void> saveAll() async {
              setDiagState(() { isSaving = true; statusMessage = 'Saving...'; });
              try {
                final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
                int employeesUpdated = 0;

                for (final emp in employees) {
                  final empId = emp['localId']?.toString() ?? '';
                  final dept = emp['department']?.toString() ?? '';
                  final absentN = int.tryParse(absentCtrls[empId]!.text.trim()) ?? 0;
                  final leaveN = int.tryParse(leaveCtrls[empId]!.text.trim()) ?? 0;
                  if (absentN == 0 && leaveN == 0) continue;

                  final days = eligibleDays(dept);
                  if (absentN + leaveN > days.length) {
                    throw Exception(
                        '${emp['name']}: entered ${absentN + leaveN} days off but only ${days.length} eligible working days exist this month.');
                  }

                  final total = days.length;
                  final absentDates = days.sublist(total - absentN, total);
                  final leaveDates = days.sublist(total - absentN - leaveN, total - absentN);
                  final presentDates = days.sublist(0, total - absentN - leaveN);

                  for (final d in presentDates) {
                    await FinanceLocalStorage.saveAttendanceRecord(
                      branchId: branchId,
                      data: {
                        'employeeId': empId,
                        'date': DateFormat('yyyy-MM-dd').format(d),
                        'status': 'present',
                        'note': 'Bulk month-entry',
                      },
                      performedBy: curUser,
                    );
                  }
                  for (final d in leaveDates) {
                    await FinanceLocalStorage.saveAttendanceRecord(
                      branchId: branchId,
                      data: {
                        'employeeId': empId,
                        'date': DateFormat('yyyy-MM-dd').format(d),
                        'status': 'leave',
                        'leaveType': leaveTypes[empId],
                        'note': 'Bulk month-entry',
                      },
                      performedBy: curUser,
                    );
                  }
                  for (final d in absentDates) {
                    await FinanceLocalStorage.saveAttendanceRecord(
                      branchId: branchId,
                      data: {
                        'employeeId': empId,
                        'date': DateFormat('yyyy-MM-dd').format(d),
                        'status': 'absent',
                        'note': 'Bulk month-entry',
                      },
                      performedBy: curUser,
                    );
                  }

                  await FinanceLocalStorage.logAction(
                    branchId: branchId,
                    entityType: 'attendance',
                    entityId: empId,
                    action: 'update',
                    performedBy: curUser,
                    reason: 'Bulk month entry for ${DateFormat('MMMM yyyy').format(selectedMonth)}: '
                        '$absentN absent, $leaveN leave, ${presentDates.length} present.',
                  );
                  employeesUpdated++;
                }

                setDiagState(() {
                  isSaving = false;
                  statusMessage = '\u2713 Updated $employeesUpdated employee(s).';
                });
                onSaved?.call();
              } catch (e) {
                setDiagState(() {
                  isSaving = false;
                  statusMessage = 'Failed: $e';
                });
              }
            }

            return AlertDialog(
              backgroundColor: t.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.fact_check_outlined, color: t.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Bulk Month Attendance Entry',
                        style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 620,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setDiagState(() {
                            selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
                          }),
                        ),
                        Text(DateFormat('MMMM yyyy').format(selectedMonth),
                            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: DateFormat('yyyy-MM').format(selectedMonth) == DateFormat('yyyy-MM').format(DateTime.now())
                              ? null
                              : () => setDiagState(() {
                                    selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
                                  }),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: t.accent.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        'Enter how many days each employee was absent or on leave this month. '
                        'Everything else is marked present automatically. Sundays and holidays are '
                        'skipped \u2014 they don\'t need to be entered. This overwrites this month\'s '
                        'attendance for any employee you enter a number for.',
                        style: TextStyle(color: t.textSecondary, fontSize: 11),
                      ),
                    ),
                    if (statusMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(statusMessage,
                            style: TextStyle(
                                color: statusMessage.startsWith('\u2713') ? Colors.green : Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: employees.length,
                        itemBuilder: (c, i) {
                          final emp = employees[i];
                          final empId = emp['localId']?.toString() ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(emp['name']?.toString() ?? '', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: absentCtrls[empId],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: InputDecoration(labelText: 'Absent', isDense: true, labelStyle: TextStyle(color: t.textTertiary, fontSize: 11)),
                                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: leaveCtrls[empId],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: InputDecoration(labelText: 'Leave', isDense: true, labelStyle: TextStyle(color: t.textTertiary, fontSize: 11)),
                                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: DropdownButton<String>(
                                    value: leaveTypes[empId],
                                    isExpanded: true,
                                    items: ['sick', 'casual', 'annual', 'unpaid']
                                        .map((lt) => DropdownMenuItem(value: lt, child: Text(lt.toUpperCase(), style: const TextStyle(fontSize: 11))))
                                        .toList(),
                                    onChanged: (val) => setDiagState(() => leaveTypes[empId] = val ?? 'sick'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: Text('Close', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: t.accent),
                  onPressed: isSaving ? null : saveAll,
                  child: Text(isSaving ? 'Saving...' : 'Save All', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
