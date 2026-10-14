// lib/pages/office/bulk_individual_attendance_dialog.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/design_system.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/sync_service.dart';
import '../../services/local_storage_service.dart';

class BulkIndividualAttendanceDialog {
  static void open({
    required BuildContext context,
    required String branchId,
    required RoleThemeData theme,
    VoidCallback? onSaved,
  }) {
    final t = theme;
    DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    String? selectedEmployeeId;
    
    final TextEditingController presentCtrl = TextEditingController(text: '0');
    final TextEditingController absentCtrl = TextEditingController(text: '0');
    final TextEditingController leaveCtrl = TextEditingController(text: '0');
    final TextEditingController weekendCtrl = TextEditingController(text: '0');
    String leaveType = 'sick';
    
    bool isSaving = false;
    String statusMessage = '';

    // Modern Color Palette Overrides
    final dialogBg = context.adapt(SoftPalette.gray50);
    final cardBg = context.adapt(SoftPalette.gray50);
    final cardBorder = context.adapt(SoftPalette.slate150);
    final inputBg = context.adapt(SoftPalette.gray50);
    final inputBorder = context.adapt(SoftPalette.slate200);
    final textPrimary = context.adapt(SoftPalette.slate900);
    final textSecondary = context.adapt(SoftPalette.slate600);
    final textTertiary = context.adapt(SoftPalette.slate350);

    final employees = FinanceLocalStorage.getEmployees(branchId).where((e) => e['isActive'] == true).toList();
    if (employees.isNotEmpty) {
      selectedEmployeeId = employees.first['localId']?.toString();
    }

    void recalculateDefaultDays(String empId, DateTime month, void Function(void Function()) setDiagState) {
      final emp = employees.firstWhere((e) => e['localId']?.toString() == empId);
      final dept = emp['department']?.toString() ?? '';
      
      final monthStart = DateTime(month.year, month.month, 1);
      final monthEnd = DateTime(month.year, month.month + 1, 0);
      final totalDays = monthEnd.day;
      
      int sundays = 0;
      int holidays = 0;
      
      for (int d = 1; d <= totalDays; d++) {
        final date = DateTime(month.year, month.month, d);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        
        if (date.weekday == DateTime.sunday) {
          sundays++;
        } else if (FinanceLocalStorage.isHoliday(branchId: branchId, department: dept, dateStr: dateStr)) {
          holidays++;
        }
      }
      
      final totalWeekends = sundays + holidays;
      final workingDays = totalDays - totalWeekends;
      
      setDiagState(() {
        presentCtrl.text = workingDays.toString();
        absentCtrl.text = '0';
        leaveCtrl.text = '0';
        weekendCtrl.text = totalWeekends.toString();
      });
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: StatefulBuilder(
            builder: (diagCtx, setDiagState) {
              
              if (selectedEmployeeId != null && presentCtrl.text == '0' && absentCtrl.text == '0') {
                recalculateDefaultDays(selectedEmployeeId!, selectedMonth, setDiagState);
              }

              Future<void> saveBulk() async {
                if (selectedEmployeeId == null) {
                  setDiagState(() => statusMessage = 'Please select an employee.');
                  return;
                }

                setDiagState(() {
                  isSaving = true;
                  statusMessage = 'Saving Attendance...';
                });

                try {
                  final curUser = LocalStorageService.getActiveUsername();
                  final emp = employees.firstWhere((e) => e['localId']?.toString() == selectedEmployeeId);
                  final empId = emp['localId']?.toString() ?? '';
                  final dept = emp['department']?.toString() ?? '';

                  final presentN = int.tryParse(presentCtrl.text.trim()) ?? 0;
                  final absentN = int.tryParse(absentCtrl.text.trim()) ?? 0;
                  final leaveN = int.tryParse(leaveCtrl.text.trim()) ?? 0;
                  final weekendN = int.tryParse(weekendCtrl.text.trim()) ?? 0;

                  final monthStart = DateTime(selectedMonth.year, selectedMonth.month, 1);
                  final monthEnd = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
                  final totalDays = monthEnd.day;

                  if (presentN + absentN + leaveN + weekendN > totalDays) {
                    throw Exception(
                      'Total entered days (${presentN + absentN + leaveN + weekendN}) exceeds total days in this month ($totalDays).'
                    );
                  }

                  // Get all days of the month
                  final allDays = <DateTime>[];
                  for (int d = 1; d <= totalDays; d++) {
                    allDays.add(DateTime(selectedMonth.year, selectedMonth.month, d));
                  }

                  // Classify standard weekends (Sundays and official holidays)
                  final List<DateTime> standardWeekends = [];
                  final List<DateTime> standardWorkingDays = [];

                  for (final d in allDays) {
                    final dateStr = DateFormat('yyyy-MM-dd').format(d);
                    final isHol = FinanceLocalStorage.isHoliday(branchId: branchId, department: dept, dateStr: dateStr);
                    if (d.weekday == DateTime.sunday || isHol) {
                      standardWeekends.add(d);
                    } else {
                      standardWorkingDays.add(d);
                    }
                  }

                  // Distribute weekends/holidays
                  final List<DateTime> assignedWeekends = [];
                  if (weekendN >= standardWeekends.length) {
                    assignedWeekends.addAll(standardWeekends);
                    final extraWeekendsCount = weekendN - standardWeekends.length;
                    if (extraWeekendsCount > 0 && standardWorkingDays.length >= extraWeekendsCount) {
                      assignedWeekends.addAll(standardWorkingDays.sublist(standardWorkingDays.length - extraWeekendsCount));
                      standardWorkingDays.removeRange(standardWorkingDays.length - extraWeekendsCount, standardWorkingDays.length);
                    }
                  } else {
                    assignedWeekends.addAll(standardWeekends.sublist(0, weekendN));
                  }

                  // Distribute present, leave, absent days over remaining working days
                  if (presentN + leaveN + absentN > standardWorkingDays.length) {
                    throw Exception(
                      'Not enough working days left after assigning weekends. Available: ${standardWorkingDays.length} working days.'
                    );
                  }

                  final presentDates = standardWorkingDays.sublist(0, presentN);
                  final leaveDates = standardWorkingDays.sublist(presentN, presentN + leaveN);
                  final absentDates = standardWorkingDays.sublist(presentN + leaveN, presentN + leaveN + absentN);

                  // Delete existing attendance records for this month first
                  for (final d in allDays) {
                    final dateStr = DateFormat('yyyy-MM-dd').format(d);
                    final key = '${empId}_$dateStr';
                    await FinanceLocalStorage.attendanceBox.delete(key);
                  }

                  // Write records
                  for (final d in presentDates) {
                    await FinanceLocalStorage.saveAttendanceRecord(
                      branchId: branchId,
                      data: {
                        'employeeId': empId,
                        'date': DateFormat('yyyy-MM-dd').format(d),
                        'status': 'present',
                        'note': 'Bulk Individual present-entry',
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
                        'leaveType': leaveType,
                        'note': 'Bulk Individual leave-entry',
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
                        'note': 'Bulk Individual absent-entry',
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
                    reason: 'Bulk Individual entry for ${DateFormat('MMMM yyyy').format(selectedMonth)}: '
                        '$presentN present, $absentN absent, $leaveN leave, $weekendN weekends.',
                  );

                  // Trigger upload instantly
                  SyncService().triggerUpload();

                  setDiagState(() {
                    isSaving = false;
                    statusMessage = '✓ Successfully saved attendance for ${emp['name']}.';
                  });
                  onSaved?.call();
                } catch (e) {
                  setDiagState(() {
                    isSaving = false;
                    statusMessage = 'Failed: $e';
                  });
                }
              }

              return Container(
                width: 480,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: dialogBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.accent.withOpacity(0.18), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: SoftPalette.gray900.withOpacity(0.1),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_add_alt_1_outlined, color: t.accent, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              'Individual Bulk Attendance',
                              style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left, color: textPrimary, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                onPressed: () => setDiagState(() {
                                  selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
                                  if (selectedEmployeeId != null) {
                                    recalculateDefaultDays(selectedEmployeeId!, selectedMonth, setDiagState);
                                  }
                                }),
                              ),
                              Text(
                                DateFormat('MMM yyyy').format(selectedMonth),
                                style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              IconButton(
                                icon: Icon(Icons.chevron_right, color: textPrimary, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                onPressed: DateFormat('yyyy-MM').format(selectedMonth) == DateFormat('yyyy-MM').format(DateTime.now())
                                    ? null
                                    : () => setDiagState(() {
                                          selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
                                          if (selectedEmployeeId != null) {
                                            recalculateDefaultDays(selectedEmployeeId!, selectedMonth, setDiagState);
                                          }
                                        }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Employee Dropdown
                    Text('Select Employee', style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedEmployeeId,
                      dropdownColor: dialogBg,
                      style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: inputBg,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: inputBorder, width: 1.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: t.accent, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: employees
                          .map((emp) => DropdownMenuItem(
                                value: emp['localId']?.toString(),
                                child: Text(emp['name']?.toString() ?? '', style: TextStyle(color: textPrimary)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDiagState(() => selectedEmployeeId = val);
                          recalculateDefaultDays(val, selectedMonth, setDiagState);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    if (statusMessage.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: statusMessage.startsWith('✓') ? SoftPalette.green400.withOpacity(0.08) : SoftPalette.red400.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusMessage.startsWith('✓') ? SoftPalette.green400.withOpacity(0.2) : SoftPalette.red400.withOpacity(0.2)),
                        ),
                        child: Text(
                          statusMessage,
                          style: TextStyle(
                            color: statusMessage.startsWith('✓') ? SoftPalette.green550 : SoftPalette.red550,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Day Input Fields
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Working/Presents', style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: presentCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  filled: true,
                                  fillColor: inputBg,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: inputBorder, width: 1.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: t.accent, width: 1.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Weekends/Holidays', style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: weekendCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  filled: true,
                                  fillColor: inputBg,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: inputBorder, width: 1.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: t.accent, width: 1.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Absent Days', style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: absentCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  filled: true,
                                  fillColor: inputBg,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: inputBorder, width: 1.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: t.accent, width: 1.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Leave Days', style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: leaveCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  filled: true,
                                  fillColor: inputBg,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: inputBorder, width: 1.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: t.accent, width: 1.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Leave Type Dropdown
                    Text('Leave Type (if leaves > 0)', style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: leaveType,
                      dropdownColor: dialogBg,
                      style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: inputBg,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: inputBorder, width: 1.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: t.accent, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: ['sick', 'casual', 'annual', 'unpaid']
                          .map((lt) => DropdownMenuItem(
                                value: lt,
                                child: Text(lt.toUpperCase(), style: TextStyle(color: textPrimary, fontSize: 11)),
                              ))
                          .toList(),
                      onChanged: (val) => setDiagState(() => leaveType = val ?? 'sick'),
                    ),
                    const SizedBox(height: 24),

                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.pop(ctx),
                          child: Text('Cancel', style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.accent,
                            foregroundColor: SoftPalette.gray50,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: isSaving ? null : saveBulk,
                          child: Text(isSaving ? 'Saving...' : 'Save', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
