// lib/pages/office/bulk_attendance_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/sync_service.dart';
import '../../services/local_storage_service.dart';

class BulkAttendanceDialog {
  static void open({
    required BuildContext context,
    required String branchId,
    required RoleThemeData theme,
    VoidCallback? onSaved,
  }) {
    final t = theme;
    DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final Map<String, TextEditingController> presentCtrls = {};
    final Map<String, TextEditingController> absentCtrls = {};
    final Map<String, TextEditingController> leaveCtrls = {};
    final Map<String, String> leaveTypes = {};
    final Map<String, FocusNode> presentFocus = {};
    final Map<String, FocusNode> absentFocus = {};
    final Map<String, FocusNode> leaveFocus = {};

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

    final employees = FinanceLocalStorage.getEmployees(branchId).where((e) => e['isActive'] == true).toList();
    for (final e in employees) {
      final id = e['localId']?.toString() ?? '';
      final dept = e['department']?.toString() ?? '';
      
      presentCtrls[id] = TextEditingController();
      absentCtrls[id] = TextEditingController();
      leaveCtrls[id] = TextEditingController();
      leaveTypes[id] = 'sick';
      presentFocus[id] = FocusNode();
      absentFocus[id] = FocusNode();
      leaveFocus[id] = FocusNode();

      presentCtrls[id]!.addListener(() {
        if (presentFocus[id]!.hasFocus) {
          final total = eligibleDays(dept).length;
          final presVal = int.tryParse(presentCtrls[id]!.text.trim()) ?? 0;
          final leaveVal = int.tryParse(leaveCtrls[id]!.text.trim()) ?? 0;
          if (presVal > total) {
            presentCtrls[id]!.text = '$total';
            absentCtrls[id]!.text = '0';
            leaveCtrls[id]!.text = '0';
          } else {
            final rem = total - presVal - leaveVal;
            absentCtrls[id]!.text = '${rem >= 0 ? rem : 0}';
            if (rem < 0) {
              leaveCtrls[id]!.text = '${total - presVal}';
            }
          }
        }
      });

      absentCtrls[id]!.addListener(() {
        if (absentFocus[id]!.hasFocus) {
          final total = eligibleDays(dept).length;
          final absVal = int.tryParse(absentCtrls[id]!.text.trim()) ?? 0;
          final leaveVal = int.tryParse(leaveCtrls[id]!.text.trim()) ?? 0;
          if (absVal > total) {
            absentCtrls[id]!.text = '$total';
            presentCtrls[id]!.text = '0';
            leaveCtrls[id]!.text = '0';
          } else {
            final rem = total - absVal - leaveVal;
            presentCtrls[id]!.text = '${rem >= 0 ? rem : 0}';
            if (rem < 0) {
              leaveCtrls[id]!.text = '${total - absVal}';
            }
          }
        }
      });

      leaveCtrls[id]!.addListener(() {
        if (leaveFocus[id]!.hasFocus) {
          final total = eligibleDays(dept).length;
          final leaveVal = int.tryParse(leaveCtrls[id]!.text.trim()) ?? 0;
          final absVal = int.tryParse(absentCtrls[id]!.text.trim()) ?? 0;
          if (leaveVal > total) {
            leaveCtrls[id]!.text = '$total';
            presentCtrls[id]!.text = '0';
            absentCtrls[id]!.text = '0';
          } else {
            final rem = total - leaveVal - absVal;
            presentCtrls[id]!.text = '${rem >= 0 ? rem : 0}';
            if (rem < 0) {
              absentCtrls[id]!.text = '${total - leaveVal}';
            }
          }
        }
      });
    }

    void resetControllersForMonth() {
      for (final e in employees) {
        final id = e['localId']?.toString() ?? '';
        final dept = e['department']?.toString() ?? '';
        final total = eligibleDays(dept).length;
        
        presentCtrls[id]?.text = '$total';
        absentCtrls[id]?.text = '0';
        leaveCtrls[id]?.text = '0';
      }
    }

    resetControllersForMonth();

    bool isSaving = false;
    String statusMessage = '';

    // Modern Light Theme Color System Overrides
    const dialogBg = Colors.white;
    const cardBg = Color(0xFFF8FAFC);
    const cardBorder = Color(0xFFE2E8F0);
    const inputBg = Colors.white;
    const inputBorder = Color(0xFFCBD5E1);
    const textPrimary = Color(0xFF0F172A);
    const textSecondary = Color(0xFF475569);
    const textTertiary = Color(0xFF94A3B8);

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: StatefulBuilder(
            builder: (diagCtx, setDiagState) {
              Future<void> saveAll() async {
                setDiagState(() {
                  isSaving = true;
                  statusMessage = 'Saving Attendance...';
                });
                try {
                  final curUser = LocalStorageService.getActiveUsername();
                  int employeesUpdated = 0;

                  for (final emp in employees) {
                    final empId = emp['localId']?.toString() ?? '';
                    final dept = emp['department']?.toString() ?? '';
                    final absentN = int.tryParse(absentCtrls[empId]!.text.trim()) ?? 0;
                    final leaveN = int.tryParse(leaveCtrls[empId]!.text.trim()) ?? 0;

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

                  // Trigger upload instantly
                  SyncService().triggerUpload();

                  setDiagState(() {
                    isSaving = false;
                    statusMessage = '✓ Updated $employeesUpdated employee(s).';
                  });
                  onSaved?.call();
                } catch (e) {
                  setDiagState(() {
                    isSaving = false;
                    statusMessage = 'Failed: $e';
                  });
                }
              }

              Future<void> saveBulkPresent() async {
                setDiagState(() {
                  isSaving = true;
                  statusMessage = 'Saving Bulk Present...';
                });
                try {
                  final curUser = LocalStorageService.getActiveUsername();
                  int employeesUpdated = 0;

                  for (final emp in employees) {
                    final empId = emp['localId']?.toString() ?? '';
                    final dept = emp['department']?.toString() ?? '';
                    final days = eligibleDays(dept);

                    for (final d in days) {
                      await FinanceLocalStorage.saveAttendanceRecord(
                        branchId: branchId,
                        data: {
                          'employeeId': empId,
                          'date': DateFormat('yyyy-MM-dd').format(d),
                          'status': 'present',
                          'note': 'Bulk present-entry',
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
                      reason: 'Bulk present entry for ${DateFormat('MMMM yyyy').format(selectedMonth)}: all days marked present.',
                    );
                    employeesUpdated++;
                  }

                  // Reset controllers to 0
                  for (final e in employees) {
                    final id = e['localId']?.toString() ?? '';
                    final dept = e['department']?.toString() ?? '';
                    final total = eligibleDays(dept).length;
                    presentCtrls[id]?.text = '$total';
                    absentCtrls[id]?.text = '0';
                    leaveCtrls[id]?.text = '0';
                  }

                  // Trigger upload instantly
                  SyncService().triggerUpload();

                  setDiagState(() {
                    isSaving = false;
                    statusMessage = '✓ Bulk marked $employeesUpdated employee(s) present.';
                  });
                  onSaved?.call();
                } catch (e) {
                  setDiagState(() {
                    isSaving = false;
                    statusMessage = 'Failed: $e';
                  });
                }
              }

              Widget buildHeader() {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.fact_check_outlined, color: t.accent, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'Bulk Month Attendance',
                          style: const TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left, color: textPrimary, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                onPressed: () => setDiagState(() {
                                  selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
                                  resetControllersForMonth();
                                }),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  DateFormat('MMMM yyyy').format(selectedMonth),
                                  style: const TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right, color: textPrimary, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                onPressed: DateFormat('yyyy-MM').format(selectedMonth) == DateFormat('yyyy-MM').format(DateTime.now())
                                    ? null
                                    : () => setDiagState(() {
                                          selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
                                          resetControllersForMonth();
                                        }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.withOpacity(0.08),
                            foregroundColor: Colors.teal.shade800,
                            side: BorderSide(color: Colors.teal.withOpacity(0.2)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.done_all_rounded, size: 14),
                          label: const Text('Bulk Present All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final confirm = await showDialog<bool>(
                                    context: diagCtx,
                                    builder: (confirmCtx) => AlertDialog(
                                      backgroundColor: dialogBg,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      title: const Text('Bulk Mark Present', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                                      content: Text(
                                        'Mark all eligible working days of ${DateFormat('MMMM yyyy').format(selectedMonth)} as Present for all active employees? This will overwrite existing records for this month.',
                                        style: const TextStyle(color: textSecondary, fontSize: 13),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(confirmCtx, false),
                                          child: const Text('Cancel', style: TextStyle(color: textSecondary)),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                                          onPressed: () => Navigator.pop(confirmCtx, true),
                                          child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await saveBulkPresent();
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                );
              }

              Widget buildInfoPanel() {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.accent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(left: BorderSide(color: t.accent, width: 4)),
                  ),
                  child: const Text(
                    'Enter absent or leave days for the month. All remaining eligible working days (excluding Sundays and holidays) will be automatically marked as Present. Entering data overwrites the month\'s attendance.',
                    style: TextStyle(color: textSecondary, fontSize: 11, height: 1.4),
                  ),
                );
              }

              Widget buildStatusMessage() {
                final isSuccess = statusMessage.startsWith('✓');
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isSuccess ? Colors.green.withOpacity(0.08) : Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSuccess ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2)),
                  ),
                  child: Text(
                    statusMessage,
                    style: TextStyle(
                      color: isSuccess ? Colors.green[800] : Colors.red[800],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }

              Widget buildColumnHeaders() {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: const [
                      Expanded(
                        flex: 4,
                        child: Text('EMPLOYEE', style: TextStyle(color: textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(child: Text('PRESENT', style: TextStyle(color: textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Center(child: Text('ABSENT', style: TextStyle(color: textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Center(child: Text('LEAVE', style: TextStyle(color: textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text('LEAVE TYPE', style: TextStyle(color: textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ],
                  ),
                );
              }

              Widget buildEmployeeRow(Map<String, dynamic> emp) {
                final empId = emp['localId']?.toString() ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: t.accent.withOpacity(0.08),
                              child: Text(
                                (emp['name']?.toString() ?? 'E').substring(0, 1).toUpperCase(),
                                style: TextStyle(color: t.accent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                emp['name']?.toString() ?? '',
                                style: const TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: presentCtrls[empId],
                            focusNode: presentFocus[empId],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: inputBg,
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: inputBorder, width: 1.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: t.accent, width: 1.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: absentCtrls[empId],
                            focusNode: absentFocus[empId],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: inputBg,
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: inputBorder, width: 1.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: t.accent, width: 1.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: leaveCtrls[empId],
                            focusNode: leaveFocus[empId],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: inputBg,
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: inputBorder, width: 1.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: t.accent, width: 1.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          value: leaveTypes[empId],
                          dropdownColor: dialogBg,
                          style: const TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            filled: true,
                            fillColor: inputBg,
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: inputBorder, width: 1.2),
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
                                    child: Text(lt.toUpperCase(), style: const TextStyle(color: textPrimary, fontSize: 11)),
                                  ))
                              .toList(),
                          onChanged: (val) => setDiagState(() => leaveTypes[empId] = val ?? 'sick'),
                        ),
                      ),
                    ],
                  ),
                );
              }

              Widget buildFooter() {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSaving ? null : () => Navigator.pop(ctx),
                      child: const Text('Close', style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : saveAll,
                      child: Text(
                        isSaving ? 'Saving...' : 'Save All',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                );
              }

              return Container(
                width: 680,
                height: 600,
                decoration: BoxDecoration(
                  color: dialogBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.accent.withOpacity(0.18), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildHeader(),
                    const SizedBox(height: 16),
                    buildInfoPanel(),
                    const SizedBox(height: 16),
                    if (statusMessage.isNotEmpty) buildStatusMessage(),
                    buildColumnHeaders(),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.builder(
                        itemCount: employees.length,
                        itemBuilder: (c, i) => buildEmployeeRow(employees[i]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    buildFooter(),
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
