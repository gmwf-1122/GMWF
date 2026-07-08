// lib/pages/office/xlsx_import_helper.dart

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';

class XlsxImportHelper {
  static void openImportDialog({
    required BuildContext context,
    required String branchId,
    required RoleThemeData theme,
    VoidCallback? onImported,
  }) {
    final t = theme;
    String importType = 'employees';
    List<List<String>> previewRows = [];
    String? pickedFileName;
    bool isParsing = false;
    bool isImporting = false;
    String statusMessage = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (diagCtx, setDiagState) {
            Future<void> pickAndParseFile() async {
              setDiagState(() {
                isParsing = true;
                statusMessage = 'Picking file...';
                previewRows = [];
              });

              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['xlsx', 'xls'],
                  withData: true,
                );

                if (result == null || result.files.isEmpty) {
                  setDiagState(() { isParsing = false; statusMessage = 'No file selected.'; });
                  return;
                }

                final bytes = result.files.first.bytes;
                if (bytes == null) {
                  setDiagState(() { isParsing = false; statusMessage = 'Could not read file data.'; });
                  return;
                }

                pickedFileName = result.files.first.name;
                final excel = Excel.decodeBytes(bytes);
                final sheet = excel.tables.values.first;
                final List<List<String>> parsed = sheet.rows
                    .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
                    .toList();

                setDiagState(() {
                  isParsing = false;
                  previewRows = parsed;
                  statusMessage = 'Found ${parsed.length > 1 ? parsed.length - 1 : 0} data rows (excluding header).';
                });
              } catch (e) {
                setDiagState(() { isParsing = false; statusMessage = 'Error reading file: $e'; });
              }
            }

            Future<void> runImport() async {
              if (previewRows.isEmpty) return;
              setDiagState(() { isImporting = true; statusMessage = 'Importing...'; });

              final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
              try {
                if (importType == 'employees') {
                  await _importEmployees(previewRows, branchId, curUser);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported ${previewRows.length - 1} employees.';
                    previewRows = []; pickedFileName = null;
                  });
                } else {
                  final count = await _importAttendance(previewRows, branchId, curUser);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported $count attendance records.';
                    previewRows = []; pickedFileName = null;
                  });
                }
                onImported?.call();
              } catch (e) {
                setDiagState(() { isImporting = false; statusMessage = 'Import failed: $e'; });
              }
            }

            return AlertDialog(
              backgroundColor: t.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.upload_file_outlined, color: t.accent, size: 20),
                  const SizedBox(width: 10),
                  Text('Import from XLSX', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Type selector
                      Text('Import Type:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _typeChip(label: 'Employees', icon: Icons.people_outline, selected: importType == 'employees', theme: t,
                            onTap: () => setDiagState(() { importType = 'employees'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
                          const SizedBox(width: 10),
                          _typeChip(label: 'Attendance', icon: Icons.today_outlined, selected: importType == 'attendance', theme: t,
                            onTap: () => setDiagState(() { importType = 'attendance'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Format guide
                      _formatGuide(importType, t),
                      const SizedBox(height: 16),

                      // Pick file button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.bgCardAlt, foregroundColor: t.textPrimary,
                          side: BorderSide(color: t.bgRule),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isParsing || isImporting ? null : pickAndParseFile,
                        icon: isParsing
                            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.accent))
                            : Icon(Icons.folder_open_outlined, color: t.accent, size: 18),
                        label: Text(pickedFileName ?? 'Pick XLSX File',
                          style: TextStyle(color: t.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis),
                      ),

                      // Status
                      if (statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: statusMessage.startsWith('✓') ? Colors.green.withOpacity(0.08)
                                : (statusMessage.startsWith('Error') || statusMessage.startsWith('Import failed')) ? Colors.red.withOpacity(0.08)
                                : t.bgCardAlt,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusMessage.startsWith('✓') ? Colors.green.withOpacity(0.3)
                                : (statusMessage.startsWith('Error') || statusMessage.startsWith('Import failed')) ? Colors.red.withOpacity(0.3)
                                : t.bgRule),
                          ),
                          child: Text(statusMessage, style: TextStyle(fontSize: 11,
                            color: statusMessage.startsWith('✓') ? Colors.green
                                : (statusMessage.startsWith('Error') || statusMessage.startsWith('Import failed')) ? Colors.red
                                : t.textSecondary)),
                        ),
                      ],

                      // Preview table
                      if (previewRows.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text('Preview (first 5 rows):', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildPreviewTable(previewRows.take(6).toList(), t),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isImporting ? null : () => Navigator.pop(ctx),
                  child: Text('Close', style: TextStyle(color: t.textSecondary)),
                ),
                if (previewRows.length > 1)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isImporting ? null : runImport,
                    icon: isImporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_outlined, size: 16),
                    label: Text(isImporting ? 'Importing...' : 'Import ${previewRows.length - 1} Records',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static Widget _typeChip({
    required String label, required IconData icon, required bool selected,
    required RoleThemeData theme, required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.accent.withOpacity(0.15) : theme.bgCardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? theme.accent : theme.bgRule, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? theme.accent : theme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: selected ? theme.accent : theme.textSecondary, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  static Widget _formatGuide(String importType, RoleThemeData t) {
    final isEmp = importType == 'employees';
    final columns = isEmp
        ? ['name *', 'phone', 'cnic', 'role', 'department', 'salary *', 'joining_date\n(yyyy-MM-dd)', 'bank_name', 'bank_account', 'gender', 'marital_status']
        : ['employee_name *', 'date *\n(yyyy-MM-dd)', 'status *\n(P/A/L/HD/OT)', 'leave_type\n(sick/casual/annual/unpaid)', 'arrival_time', 'departure_time', 'note'];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: t.accent),
              const SizedBox(width: 6),
              Text('Expected Columns (Row 1 = Headers):', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: columns.asMap().entries.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(4), border: Border.all(color: t.bgRule)),
              child: Text('Col ${e.key + 1}: ${e.value}', style: TextStyle(color: t.textSecondary, fontSize: 10)),
            )).toList(),
          ),
        ],
      ),
    );
  }

  static Widget _buildPreviewTable(List<List<String>> rows, RoleThemeData t) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final headers = rows.first;
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];

    return Container(
      decoration: BoxDecoration(border: Border.all(color: t.bgRule), borderRadius: BorderRadius.circular(8)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(t.bgCardAlt),
            dataRowColor: WidgetStateProperty.all(t.bgCard),
            columnSpacing: 16,
            headingTextStyle: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.bold),
            dataTextStyle: TextStyle(color: t.textPrimary, fontSize: 11),
            columns: headers.map((h) => DataColumn(label: Text(h.isEmpty ? '—' : h, overflow: TextOverflow.ellipsis))).toList(),
            rows: dataRows.map((row) => DataRow(
              cells: List.generate(headers.length,
                (i) => DataCell(Text(i < row.length ? row[i] : '', overflow: TextOverflow.ellipsis))),
            )).toList(),
          ),
        ),
      ),
    );
  }

  static Future<void> _importEmployees(List<List<String>> rows, String branchId, String performedBy) async {
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
    for (final row in dataRows) {
      String get(int i) => i < row.length ? row[i].trim() : '';
      final name = get(0);
      if (name.isEmpty) continue;
      final salary = double.tryParse(get(5).replaceAll(',', '')) ?? 0.0;
      final joiningDate = get(6).isNotEmpty ? get(6) : DateFormat('yyyy-MM-dd').format(DateTime.now());
      final data = {
        'name': name,
        'phone': get(1),
        'cnic': get(2),
        'role': get(3).isNotEmpty ? get(3) : 'Office Boy',
        'department': get(4).isNotEmpty ? get(4) : 'Office',
        'currentSalary': salary,
        'joiningDate': joiningDate,
        'bankName': get(7).isNotEmpty ? get(7) : 'Cash',
        'bankAccount': get(8),
        'gender': get(9).isNotEmpty ? get(9) : 'Male',
        'maritalStatus': get(10).isNotEmpty ? get(10) : 'Single',
        'branchId': branchId,
        'isActive': true,
        'compensationType': 'monthly',
        'createdBy': performedBy,
      };
      await FinanceLocalStorage.saveEmployee(branchId: branchId, data: data, performedBy: performedBy);
    }
  }

  static Future<int> _importAttendance(List<List<String>> rows, String branchId, String performedBy) async {
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
    final employees = FinanceLocalStorage.getEmployees(branchId);
    final nameMap = <String, String>{};
    final cnicMap = <String, String>{};
    for (final emp in employees) {
      final id = emp['localId']?.toString() ?? '';
      final name = (emp['name']?.toString() ?? '').toLowerCase().trim();
      final cnic = emp['cnic']?.toString() ?? '';
      if (name.isNotEmpty) nameMap[name] = id;
      if (cnic.isNotEmpty) cnicMap[cnic] = id;
    }

    const statusMap = {
      'p': 'present', 'present': 'present',
      'a': 'absent', 'absent': 'absent',
      'l': 'leave', 'leave': 'leave', 'lv': 'leave',
      'hd': 'half_day', 'half_day': 'half_day', 'half day': 'half_day',
      'ot': 'overtime', 'overtime': 'overtime',
    };

    int count = 0;
    for (final row in dataRows) {
      String get(int i) => i < row.length ? row[i].trim() : '';
      final lookupKey = get(0).toLowerCase();
      final dateStr = get(1);
      final rawStatus = get(2).toLowerCase();
      if (lookupKey.isEmpty || dateStr.isEmpty || rawStatus.isEmpty) continue;
      final empId = nameMap[lookupKey] ?? cnicMap[lookupKey] ?? '';
      if (empId.isEmpty) continue;
      final status = statusMap[rawStatus] ?? 'absent';
      final record = {
        'employeeId': empId,
        'date': dateStr,
        'status': status,
        'leaveType': status == 'leave' ? (get(3).isNotEmpty ? get(3).toLowerCase() : 'sick') : null,
        'arrivalTime': (status == 'present' || status == 'late') && get(4).isNotEmpty ? get(4) : null,
        'departureTime': (status == 'present' || status == 'late') && get(5).isNotEmpty ? get(5) : null,
        'note': get(6).isNotEmpty ? get(6) : null,
      };
      await FinanceLocalStorage.saveAttendanceRecord(branchId: branchId, data: record, performedBy: performedBy);
      count++;
    }
    return count;
  }
}
