// lib/pages/office/xlsx_import_helper.dart

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_expenses_storage.dart';
import '../../services/local_storage_service.dart';
import 'package:uuid/uuid.dart';

class XlsxImportHelper {
  static void openImportDialog({
    required BuildContext context,
    required String branchId,
    required RoleThemeData theme,
    String? initialType,
    VoidCallback? onImported,
  }) {
    final t = theme;
    String importType = initialType ?? 'employees';
    List<List<String>> previewRows = [];
    Map<String, List<List<String>>> sheetsMap = {};
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
                sheetsMap = {};
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
                final excel = Excel.decodeBytes(_sanitizeExcelBytes(bytes));
                
                final Map<String, List<List<String>>> sMap = {};
                for (final name in excel.tables.keys) {
                  final s = excel.tables[name]!;
                  sMap[name] = s.rows.map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList()).toList();
                }

                setDiagState(() {
                  isParsing = false;
                  sheetsMap = sMap;
                  previewRows = sMap.values.isNotEmpty ? sMap.values.first : <List<String>>[];
                  statusMessage = 'Found ${previewRows.length > 1 ? previewRows.length - 1 : 0} data rows (excluding header) across ${sMap.length} sheet(s).';
                });
              } catch (e) {
                setDiagState(() { isParsing = false; statusMessage = 'Error reading file: $e'; });
              }
            }

            Future<void> runImport() async {
              if (previewRows.isEmpty) return;
              setDiagState(() { isImporting = true; statusMessage = 'Importing...'; });

              final curUserMap = LocalStorageService.getActiveUserData();
              final curUser = LocalStorageService.getActiveUsername();
              final performedByName = curUserMap['name']?.toString() ?? curUser;
              final performedBy = curUserMap['uid']?.toString() ?? curUserMap['id']?.toString() ?? 'admin';

              try {
                if (importType == 'school_students') {
                  final count = await _importSchoolStudents(sheetsMap.isNotEmpty ? sheetsMap : {'default': previewRows}, branchId);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported $count school students.';
                    previewRows = []; pickedFileName = null; sheetsMap = {};
                  });
                } else if (importType == 'madrassa_students') {
                  final count = await _importMadrassaStudents(sheetsMap.isNotEmpty ? sheetsMap : {'default': previewRows}, branchId);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported $count madrassa students.';
                    previewRows = []; pickedFileName = null; sheetsMap = {};
                  });
                } else if (importType == 'donations') {
                  final count = await _importDonations(sheetsMap.isNotEmpty ? sheetsMap : {'default': previewRows}, branchId);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported $count donation records.';
                    previewRows = []; pickedFileName = null; sheetsMap = {};
                  });
                } else if (importType == 'employees') {
                  final count = await _importEmployees(sheetsMap.isNotEmpty ? sheetsMap : {'default': previewRows}, branchId, curUser);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported $count employees.';
                    previewRows = []; pickedFileName = null; sheetsMap = {};
                  });
                } else if (importType == 'attendance') {
                  final count = await _importAttendance(sheetsMap.isNotEmpty ? sheetsMap : {'default': previewRows}, branchId, curUser);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported $count attendance records.';
                    previewRows = []; pickedFileName = null; sheetsMap = {};
                  });
                } else if (importType == 'expenses') {
                  final count = await _importExpenses(sheetsMap.isNotEmpty ? sheetsMap : {'default': previewRows}, branchId, performedBy, performedByName);
                  setDiagState(() {
                    isImporting = false;
                    statusMessage = '✓ Successfully imported $count expense records.';
                    previewRows = []; pickedFileName = null; sheetsMap = {};
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
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Type selector
                      Text('Import Type:', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          _typeChip(label: 'School Students', icon: Icons.school_outlined, selected: importType == 'school_students', theme: t,
                            onTap: () => setDiagState(() { importType = 'school_students'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
                          _typeChip(label: 'Madrassa', icon: Icons.menu_book_outlined, selected: importType == 'madrassa_students', theme: t,
                            onTap: () => setDiagState(() { importType = 'madrassa_students'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
                          _typeChip(label: 'Employees', icon: Icons.people_outline, selected: importType == 'employees', theme: t,
                            onTap: () => setDiagState(() { importType = 'employees'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
                          _typeChip(label: 'Donations', icon: Icons.volunteer_activism_outlined, selected: importType == 'donations', theme: t,
                            onTap: () => setDiagState(() { importType = 'donations'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
                          _typeChip(label: 'Attendance', icon: Icons.today_outlined, selected: importType == 'attendance', theme: t,
                            onTap: () => setDiagState(() { importType = 'attendance'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
                          _typeChip(label: 'Expenses', icon: Icons.receipt_long_outlined, selected: importType == 'expenses', theme: t,
                            onTap: () => setDiagState(() { importType = 'expenses'; previewRows = []; pickedFileName = null; statusMessage = ''; })),
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
    final isAtt = importType == 'attendance';
    final columns = isEmp
        ? ['name *', 'phone', 'cnic', 'role', 'department', 'salary *', 'joining_date\n(yyyy-MM-dd)', 'bank_name', 'bank_account', 'gender', 'marital_status']
        : isAtt
            ? ['employee_name *', 'date *\n(yyyy-MM-dd)', 'status *\n(P/A/L/HD/OT)', 'leave_type\n(sick/casual/annual/unpaid)', 'arrival_time', 'departure_time', 'note']
            : ['date *\n(yyyy-MM-dd)', 'category *', 'custom_category', 'amount *', 'description *'];

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

  static int _findColumnIndex(List<String> headers, List<String> synonyms) {
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase().trim();
      for (final syn in synonyms) {
        if (h == syn || h.contains(syn)) {
          return i;
        }
      }
    }
    return -1;
  }

  static bool _isDateHeader(String header) {
    final h = header.toLowerCase().trim();
    if (h.isEmpty) return false;
    final hasDay = RegExp(r'\d+').hasMatch(h);
    final hasMonth = RegExp(r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\d+)').hasMatch(h);
    return hasDay && hasMonth && !h.contains('working') && !h.contains('absent') && !h.contains('weekend') && !h.contains('total');
  }

  static String? _parseHeaderDate(String headerStr) {
    final h = headerStr.trim();
    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(h);
    if (isoMatch != null) {
      return '${isoMatch.group(1)}-${isoMatch.group(2)}-${isoMatch.group(3)}';
    }

    try {
      final parts = h.split(RegExp(r'[-/ ]'));
      if (parts.length >= 2) {
        if (parts[0].length == 4) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = parts.length > 2 ? int.tryParse(parts[2].replaceAll(RegExp(r'\D'), '')) : null;
          if (year != null && month != null && day != null && day <= 31) {
            return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          }
        }
        
        final dayStr = parts[0];
        final monthStr = parts[1];
        final day = int.tryParse(dayStr);
        if (day != null && day <= 31) {
          final monthsMap = {
            'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
            'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
          };
          int? month = int.tryParse(monthStr);
          if (month == null && monthStr.length >= 3) {
            month = monthsMap[monthStr.substring(0, 3).toLowerCase()];
          }
          if (month != null) {
            final year = parts.length > 2 ? (int.tryParse(parts[2].replaceAll(RegExp(r'\D'), '')) ?? DateTime.now().year) : DateTime.now().year;
            final mStr = month.toString().padLeft(2, '0');
            final dStr = day.toString().padLeft(2, '0');
            return '$year-$mStr-$dStr';
          }
        }
      }
    } catch (_) {}
    try {
      final date = DateFormat('d-MMM').parse(h);
      final year = DateTime.now().year;
      final mStr = date.month.toString().padLeft(2, '0');
      final dStr = date.day.toString().padLeft(2, '0');
      return '$year-$mStr-$dStr';
    } catch (_) {}
    try {
      final date = DateFormat('yyyy-MM-dd').parse(h);
      return DateFormat('yyyy-MM-dd').format(date);
    } catch (_) {}
    return null;
  }

  static Map<String, int>? _parseSheetMonthYear(String sheetName) {
    final cleanName = sheetName.toUpperCase().trim();
    final monthsMap = {
      'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
      'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12
    };
    int? month;
    for (final entry in monthsMap.entries) {
      if (cleanName.contains(entry.key)) {
        month = entry.value;
        break;
      }
    }
    int? year;
    final matches = RegExp(r'\d+').allMatches(cleanName);
    for (final m in matches) {
      final val = int.tryParse(m.group(0)!);
      if (val != null) {
        if (val >= 2000 && val <= 2100) {
          year = val;
        } else if (val >= 0 && val <= 99) {
          year = 2000 + val;
        }
      }
    }
    if (month != null && year != null) {
      return {'month': month, 'year': year};
    }
    return null;
  }

  static int? _parseDayFromHeader(String header) {
    final trimmed = header.trim();
    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (isoMatch != null) {
      return int.tryParse(isoMatch.group(3)!);
    }
    final match = RegExp(r'^(\d+)').firstMatch(trimmed);
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null && parsed <= 31) {
        return parsed;
      }
    }
    return null;
  }

  static Map<String, String> _parseBankAccount(String rawVal) {
    final val = rawVal.trim();
    if (val.isEmpty) return {'bankName': 'Cash', 'bankAccount': ''};

    final valUpper = val.toUpperCase();
    String bankName = 'Meezan Bank';
    String cleanAccount = val;

    if (valUpper.contains('EASY PAISA') || valUpper.contains('EASY PASA') || valUpper.contains('EASY PLASA')) {
      bankName = 'EasyPaisa';
      cleanAccount = val.replaceAll(RegExp(r'(EASY\s*PAISA|EASY\s*PASA|EASY\s*PLASA)', caseSensitive: false), '').trim();
    } else if (valUpper.contains('JAZZ CASH') || valUpper.contains('JAZZCASH')) {
      bankName = 'JazzCash';
      cleanAccount = val.replaceAll(RegExp(r'(JAZZ\s*CASH|JAZZCASH)', caseSensitive: false), '').trim();
    } else if (valUpper.contains('MEZN') || valUpper.contains('MEEZAN')) {
      bankName = 'Meezan Bank';
      cleanAccount = val.replaceAll(RegExp(r'(MEZN|MEEZAN)', caseSensitive: false), '').trim();
    } else if (valUpper.contains('UNIL') || valUpper.contains('UBL')) {
      bankName = 'UBL Bank';
      cleanAccount = val.replaceAll(RegExp(r'(UNIL|UBL)', caseSensitive: false), '').trim();
    } else if (valUpper.contains('NBP') || valUpper.contains('NBPA')) {
      bankName = 'National Bank of Punjab';
      cleanAccount = val.replaceAll(RegExp(r'(NBP|NBPA)', caseSensitive: false), '').trim();
    } else {
      final onlyDigits = RegExp(r'^\d+$').hasMatch(val);
      final isIban = RegExp(r'^PK\d+[A-Z]*\d+$', caseSensitive: false).hasMatch(val);
      if (onlyDigits || isIban) {
        bankName = 'Meezan Bank';
      }
    }

    return {
      'bankName': bankName,
      'bankAccount': cleanAccount,
    };
  }

  static String _generatePlaceholderCnic(String name) {
    final code = (name.hashCode.abs() % 10000000).toString().padLeft(7, '0');
    return '99999-$code-0';
  }

  static Future<int> _importEmployees(Map<String, List<List<String>>> sheetsMap, String branchId, String performedBy) async {
    final Set<String> processedNames = {};
    for (final sheetName in sheetsMap.keys) {
      final rows = sheetsMap[sheetName] ?? [];
      if (rows.isEmpty) continue;

      List<String>? headers;
      int headerRowIdx = -1;
      
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.any((cell) => cell.trim().isNotEmpty)) {
          headers = row.map((c) => c.trim()).toList();
          headerRowIdx = i;
          break;
        }
      }
      
      if (headers == null || headerRowIdx == -1) continue;

      final nameIdx = _findColumnIndex(headers, ['name', 'fullname', 'full name', 'employee name', 'employee_name']);
      
      if (nameIdx != -1) {
        final bankAccIdx = _findColumnIndex(headers, ['a/c #', 'ac #', 'account', 'bank_account', 'bank account', 'acc']);
        final salaryIdx = _findColumnIndex(headers, ['pay scale', 'pay_scale', 'salary', 'basic pay', 'gross salary', 'gross_salary', 'net payable', 'scale', 'basic']);
        final cnicIdx = _findColumnIndex(headers, ['cnic', 'identity']);
        final phoneIdx = _findColumnIndex(headers, ['phone', 'cell', 'contact', 'mobile']);
        final roleIdx = _findColumnIndex(headers, ['role', 'designation']);
        final deptIdx = _findColumnIndex(headers, ['department', 'dept']);
        final bankNameIdx = _findColumnIndex(headers, ['bank_name', 'bank name', 'bank', 'account type', 'account_type']);
        final joiningIdx = _findColumnIndex(headers, ['joining', 'joining_date', 'joined']);
        final genderIdx = _findColumnIndex(headers, ['gender', 'sex']);
        final maritalIdx = _findColumnIndex(headers, ['marital', 'marriage']);
        final refIdx = _findColumnIndex(headers, ['ref', 'reference']);

        final existingEmployees = FinanceLocalStorage.getEmployees('all');
        final empNameMap = <String, Map<String, dynamic>>{};
        for (final emp in existingEmployees) {
          final n = (emp['name']?.toString() ?? '').toLowerCase().trim();
          if (n.isNotEmpty) {
            empNameMap[n] = Map<String, dynamic>.from(emp);
          }
        }

        final dataRows = rows.sublist(headerRowIdx + 1);
        for (final row in dataRows) {
          if (row.length <= nameIdx) continue;
          final name = row[nameIdx].trim();
          if (name.isEmpty || name.toLowerCase() == 'total' || name.toLowerCase() == 'sr.#') continue;

          final rawBankAccount = bankAccIdx != -1 && bankAccIdx < row.length ? row[bankAccIdx].trim() : '';
          final parsedBank = _parseBankAccount(rawBankAccount);
          final bankAccount = parsedBank['bankAccount']!;
          final defaultBankName = parsedBank['bankName']!;

          final salary = salaryIdx != -1 && salaryIdx < row.length ? (double.tryParse(row[salaryIdx].replaceAll(',', '')) ?? 0.0) : 0.0;
          
          final rawCnic = cnicIdx != -1 && cnicIdx < row.length ? row[cnicIdx].trim() : '';
          final cnic = RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(rawCnic) 
              ? rawCnic 
              : _generatePlaceholderCnic(name);

          final phone = phoneIdx != -1 && phoneIdx < row.length ? row[phoneIdx].trim() : '';
          
          String employeeBranchId = branchId;
          String parsedRole = 'Office Boy';
          String parsedDept = 'Office';
          if (refIdx != -1 && refIdx < row.length) {
            final refVal = row[refIdx].trim().toUpperCase();
            final parts = refVal.split('/');
            if (parts.length >= 2) {
              final branchCode = parts[0].trim();
              if (branchCode == 'GRT') employeeBranchId = 'gujrat';
              else if (branchCode == 'SKT') employeeBranchId = 'sialkot';
              else if (branchCode == 'KHI') employeeBranchId = 'karachi';
              else if (branchCode == 'RWP') employeeBranchId = 'rawalpindi';
              
              final deptCode = parts[1].trim();
              if (deptCode == 'DAS') {
                parsedDept = 'Dasterkhwaan';
                parsedRole = 'Helper';
              } else if (deptCode == 'MAD') {
                parsedDept = 'Madrassa';
                parsedRole = 'Teacher';
              } else if (deptCode == 'DIS') {
                parsedDept = 'Dispensary';
                parsedRole = 'Dispenser';
              } else if (deptCode == 'OFF') {
                parsedDept = 'Office';
                parsedRole = 'Office Boy';
              } else if (deptCode == 'ADM') {
                parsedDept = 'Admin';
                parsedRole = 'Admin';
              } else if (deptCode == 'CEO') {
                parsedDept = 'CEO';
                parsedRole = 'CEO';
              } else if (deptCode == 'SCH') {
                parsedDept = 'School';
                parsedRole = 'Teacher';
              }
            }
          }
          
          final role = roleIdx != -1 && roleIdx < row.length && row[roleIdx].trim().isNotEmpty ? row[roleIdx].trim() : parsedRole;
          final dept = deptIdx != -1 && deptIdx < row.length && row[deptIdx].trim().isNotEmpty ? row[deptIdx].trim() : parsedDept;
          
          final bankName = bankNameIdx != -1 && bankNameIdx < row.length && row[bankNameIdx].trim().isNotEmpty 
              ? row[bankNameIdx].trim() 
              : (bankAccount.isNotEmpty ? defaultBankName : 'Cash');
              
          final joiningDate = joiningIdx != -1 && joiningIdx < row.length && row[joiningIdx].trim().isNotEmpty 
              ? row[joiningIdx].trim() 
              : DateFormat('yyyy-MM-dd').format(DateTime.now());
              
          final gender = genderIdx != -1 && genderIdx < row.length && row[genderIdx].trim().isNotEmpty ? row[genderIdx].trim() : 'Male';
          final maritalStatus = maritalIdx != -1 && maritalIdx < row.length && row[maritalIdx].trim().isNotEmpty ? row[maritalIdx].trim() : 'Single';

          final nameLower = name.toLowerCase().trim();
          final existing = empNameMap[nameLower];
          final Map<String, dynamic> data = existing != null ? Map<String, dynamic>.from(existing) : {};

          final existingCnic = existing?['cnic']?.toString() ?? '';
          final newCnicValid = RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(rawCnic);
          final mergedCnic = (newCnicValid)
              ? rawCnic
              : (existingCnic.isNotEmpty ? existingCnic : cnic);

          final mergedPhone = phone.isNotEmpty ? phone : (existing?['phone']?.toString() ?? '');
          final mergedRole = (roleIdx != -1 && roleIdx < row.length && row[roleIdx].trim().isNotEmpty)
              ? row[roleIdx].trim()
              : (existing?['role']?.toString() ?? role);
          final mergedDept = (deptIdx != -1 && deptIdx < row.length && row[deptIdx].trim().isNotEmpty)
              ? row[deptIdx].trim()
              : (existing?['department']?.toString() ?? dept);
          final mergedSalary = salary > 0 ? salary : (existing?['currentSalary'] as num? ?? 0.0).toDouble();
          final mergedJoining = (joiningIdx != -1 && joiningIdx < row.length && row[joiningIdx].trim().isNotEmpty)
              ? row[joiningIdx].trim()
              : (existing?['joiningDate']?.toString() ?? joiningDate);
          final mergedBankName = (bankNameIdx != -1 && bankNameIdx < row.length && row[bankNameIdx].trim().isNotEmpty)
              ? row[bankNameIdx].trim()
              : (bankAccount.isNotEmpty ? defaultBankName : (existing?['bankName']?.toString() ?? 'Cash'));
          final mergedBankAccount = bankAccount.isNotEmpty ? bankAccount : (existing?['bankAccount']?.toString() ?? '');
          final mergedGender = (genderIdx != -1 && genderIdx < row.length && row[genderIdx].trim().isNotEmpty)
              ? row[genderIdx].trim()
              : (existing?['gender']?.toString() ?? gender);
          final mergedMarital = (maritalIdx != -1 && maritalIdx < row.length && row[maritalIdx].trim().isNotEmpty)
              ? row[maritalIdx].trim()
              : (existing?['maritalStatus']?.toString() ?? maritalStatus);

          data.addAll({
            'name': name,
            'phone': mergedPhone,
            'cnic': mergedCnic,
            'role': mergedRole,
            'department': mergedDept,
            'currentSalary': mergedSalary,
            'joiningDate': mergedJoining,
            'bankName': mergedBankName,
            'bankAccount': mergedBankAccount,
            'gender': mergedGender,
            'maritalStatus': mergedMarital,
            'branchId': employeeBranchId,
            'isActive': true,
            'compensationType': 'monthly',
            'createdBy': performedBy,
          });

          if (existing != null) {
            data['localId'] = existing['localId'];
            data['id'] = existing['localId'];
          }

          await FinanceLocalStorage.saveEmployee(branchId: employeeBranchId, data: data, performedBy: performedBy);
          processedNames.add(nameLower);
        }
      } else {
        final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
        for (final row in dataRows) {
          String get(int i) => i < row.length ? row[i].trim() : '';
          final name = get(0);
          if (name.isEmpty) continue;
          final salary = double.tryParse(get(5).replaceAll(',', '')) ?? 0.0;
          final joiningDate = get(6).isNotEmpty ? get(6) : DateFormat('yyyy-MM-dd').format(DateTime.now());
          
          final existingEmployees = FinanceLocalStorage.getEmployees('all');
          final empNameMap = <String, Map<String, dynamic>>{};
          for (final emp in existingEmployees) {
            final n = (emp['name']?.toString() ?? '').toLowerCase().trim();
            if (n.isNotEmpty) {
              empNameMap[n] = Map<String, dynamic>.from(emp);
            }
          }

          final nameLower = name.toLowerCase().trim();
          final existing = empNameMap[nameLower];
          final Map<String, dynamic> data = existing != null ? Map<String, dynamic>.from(existing) : {};

          data.addAll({
            'name': name,
            'phone': get(1),
            'cnic': existing?['cnic']?.toString() ?? _generatePlaceholderCnic(name),
            'role': get(3).isNotEmpty ? get(3) : 'Office Boy',
            'department': get(4).isNotEmpty ? get(4) : 'Office',
            'currentSalary': salary > 0 ? salary : (existing?['currentSalary'] as num? ?? 0.0).toDouble(),
            'joiningDate': joiningDate,
            'bankName': get(7).isNotEmpty ? get(7) : 'Cash',
            'bankAccount': get(8),
            'gender': get(9).isNotEmpty ? get(9) : 'Male',
            'maritalStatus': get(10).isNotEmpty ? get(10) : 'Single',
            'branchId': branchId,
            'isActive': true,
            'compensationType': 'monthly',
            'createdBy': performedBy,
          });
          if (existing != null) {
            data['localId'] = existing['localId'];
            data['id'] = existing['localId'];
          }
          await FinanceLocalStorage.saveEmployee(branchId: branchId, data: data, performedBy: performedBy);
          processedNames.add(nameLower);
        }
      }
    }
    return processedNames.length;
  }

  static Future<int> _importAttendance(Map<String, List<List<String>>> sheetsMap, String branchId, String performedBy) async {
    final employees = FinanceLocalStorage.getEmployees('all');
    final nameMap = <String, String>{};
    final cnicMap = <String, String>{};
    
    void updateEmployeeMaps() {
      nameMap.clear();
      cnicMap.clear();
      final freshEmployees = FinanceLocalStorage.getEmployees('all');
      for (final emp in freshEmployees) {
        final id = emp['localId']?.toString() ?? '';
        final name = (emp['name']?.toString() ?? '').toLowerCase().trim();
        final cnic = emp['cnic']?.toString() ?? '';
        if (name.isNotEmpty) nameMap[name] = id;
        if (cnic.isNotEmpty) cnicMap[cnic] = id;
      }
    }

    updateEmployeeMaps();

    const statusMap = {
      'p': 'present', 'present': 'present', '1': 'present',
      'a': 'absent', 'absent': 'absent', '0': 'absent',
      'l': 'leave', 'leave': 'leave', 'lv': 'leave',
      'hd': 'half_day', 'half_day': 'half_day', 'half day': 'half_day',
      'ot': 'overtime', 'overtime': 'overtime',
    };

    int totalCount = 0;

    for (final sheetName in sheetsMap.keys) {
      final rows = sheetsMap[sheetName]!;
      List<String>? headers;
      int headerRowIdx = -1;
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.any((cell) => cell.trim().isNotEmpty)) {
          headers = row.map((c) => c.trim()).toList();
          headerRowIdx = i;
          break;
        }
      }

      if (headers == null || headerRowIdx == -1) continue;

      final nameColIdx = _findColumnIndex(headers, ['name', 'fullname', 'full name', 'employee', 'employee name']);
      final workedDaysColIdx = _findColumnIndex(headers, ['total working days', 'working days', 'worked days', 'presents', 'total working', 'working_days']);
      final refIdx = _findColumnIndex(headers, ['ref', 'reference']);
      
      final List<int> dateColIndices = [];
      final List<String> dateStrings = [];
      
      for (int idx = 0; idx < headers.length; idx++) {
        final h = headers[idx];
        if (_isDateHeader(h)) {
          dateColIndices.add(idx);
          dateStrings.add(h);
        }
      }

      final sheetCtx = _parseSheetMonthYear(sheetName);

      Future<String> getOrCreateEmployee(String rawName, String? refVal) async {
        final normName = rawName.toLowerCase().trim();
        String id = nameMap[normName] ?? '';
        if (id.isEmpty) {
          for (final entry in nameMap.entries) {
            if (normName.contains(entry.key) || entry.key.contains(normName)) {
              id = entry.value;
              break;
            }
          }
        }
        if (id.isEmpty) {
          final placeholderCnic = _generatePlaceholderCnic(rawName);
          
          String employeeBranchId = branchId;
          String parsedRole = 'Office Boy';
          String parsedDept = 'Office';
          
          if (refVal != null && refVal.isNotEmpty) {
            final refValUpper = refVal.toUpperCase().trim();
            final parts = refValUpper.split('/');
            if (parts.length >= 2) {
              final branchCode = parts[0].trim();
              if (branchCode == 'GRT') employeeBranchId = 'gujrat';
              else if (branchCode == 'SKT') employeeBranchId = 'sialkot';
              else if (branchCode == 'KHI') employeeBranchId = 'karachi';
              else if (branchCode == 'RWP') employeeBranchId = 'rawalpindi';
              
              final deptCode = parts[1].trim();
              if (deptCode == 'DAS') {
                parsedDept = 'Dasterkhwaan';
                parsedRole = 'Helper';
              } else if (deptCode == 'MAD') {
                parsedDept = 'Madrassa';
                parsedRole = 'Teacher';
              } else if (deptCode == 'DIS') {
                parsedDept = 'Dispensary';
                parsedRole = 'Dispenser';
              } else if (deptCode == 'OFF') {
                parsedDept = 'Office';
                parsedRole = 'Office Boy';
              } else if (deptCode == 'ADM') {
                parsedDept = 'Admin';
                parsedRole = 'Admin';
              } else if (deptCode == 'CEO') {
                parsedDept = 'CEO';
                parsedRole = 'CEO';
              } else if (deptCode == 'SCH') {
                parsedDept = 'School';
                parsedRole = 'Teacher';
              }
            }
          }

          final newEmpData = {
            'name': rawName,
            'cnic': placeholderCnic,
            'role': parsedRole,
            'department': parsedDept,
            'currentSalary': 0.0,
            'joiningDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
            'bankName': 'Cash',
            'bankAccount': '',
            'branchId': employeeBranchId,
            'isActive': true,
            'compensationType': 'monthly',
            'createdBy': performedBy,
          };
          try {
            final newId = await FinanceLocalStorage.saveEmployee(
              branchId: employeeBranchId,
              data: newEmpData,
              performedBy: performedBy,
            );
            id = newId;
            updateEmployeeMaps();
          } catch (e) {
            debugPrint('Failed to auto-register employee $rawName: $e');
          }
        }
        return id;
      }

      if (dateColIndices.length > 2 && nameColIdx != -1) {
        final dataRows = rows.sublist(headerRowIdx + 1);
        for (final row in dataRows) {
          if (row.length <= nameColIdx) continue;
          final rawName = row[nameColIdx].trim();
          if (rawName.isEmpty || rawName.toLowerCase() == 'total' || rawName.toLowerCase() == 'sr.#') continue;

          final refVal = refIdx != -1 && refIdx < row.length ? row[refIdx].trim() : null;
          final empId = await getOrCreateEmployee(rawName, refVal);
          if (empId.isEmpty) continue;

          final empObj = FinanceLocalStorage.getEmployee(empId);
          final empBranchId = empObj?['branchId']?.toString() ?? branchId;

          for (int idx = 0; idx < dateColIndices.length; idx++) {
            final colIdx = dateColIndices[idx];
            if (colIdx >= row.length) continue;
            
            final val = row[colIdx].trim().toLowerCase();
            if (val.isEmpty) continue;

            final day = _parseDayFromHeader(dateStrings[idx]);
            String? dateStr;
            if (sheetCtx != null && day != null) {
              final y = sheetCtx['year']!;
              final m = sheetCtx['month']!;
              dateStr = '$y-${m.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
            } else {
              dateStr = _parseHeaderDate(dateStrings[idx]);
            }
            if (dateStr == null) continue;

            final status = statusMap[val] ?? 'absent';
            final record = {
              'employeeId': empId,
              'date': dateStr,
              'status': status,
              'leaveType': status == 'leave' ? 'sick' : null,
              'arrivalTime': null,
              'departureTime': null,
              'note': 'Excel Matrix Import',
            };
            await FinanceLocalStorage.saveAttendanceRecord(branchId: empBranchId, data: record, performedBy: performedBy);
            totalCount++;
          }
        }
      } else if (workedDaysColIdx != -1 && nameColIdx != -1) {
        final y = sheetCtx != null ? sheetCtx['year']! : DateTime.now().year;
        final m = sheetCtx != null ? sheetCtx['month']! : DateTime.now().month;
        final daysInMonth = DateTime(y, m + 1, 0).day;
        
        final allDays = <DateTime>[];
        for (int d = 1; d <= daysInMonth; d++) {
          allDays.add(DateTime(y, m, d));
        }

        final dataRows = rows.sublist(headerRowIdx + 1);
        for (final row in dataRows) {
          if (row.length <= nameColIdx) continue;
          final rawName = row[nameColIdx].trim();
          if (rawName.isEmpty || rawName.toLowerCase() == 'total' || rawName.toLowerCase() == 'sr.#') continue;

          final refVal = refIdx != -1 && refIdx < row.length ? row[refIdx].trim() : null;
          final empId = await getOrCreateEmployee(rawName, refVal);
          if (empId.isEmpty) continue;

          final empObj = FinanceLocalStorage.getEmployee(empId);
          final empBranchId = empObj?['branchId']?.toString() ?? branchId;
          final empDept = empObj?['department']?.toString() ?? 'Office';

          final List<DateTime> workingDays = [];
          final List<DateTime> weekendDays = [];
          for (final d in allDays) {
            final dateStr = DateFormat('yyyy-MM-dd').format(d);
            final isHol = FinanceLocalStorage.isHoliday(branchId: empBranchId, department: empDept, dateStr: dateStr);
            if (d.weekday == DateTime.sunday || isHol) {
              weekendDays.add(d);
            } else {
              workingDays.add(d);
            }
          }

          final workedDaysVal = workedDaysColIdx < row.length ? row[workedDaysColIdx].trim() : '0';
          final workedDays = int.tryParse(workedDaysVal.replaceAll(RegExp(r'\D'), '')) ?? 0;

          final List<DateTime> presentDates = [];
          final List<DateTime> absentDates = [];

          if (workedDays <= workingDays.length) {
            presentDates.addAll(workingDays.sublist(0, workedDays));
            absentDates.addAll(workingDays.sublist(workedDays));
          } else {
            presentDates.addAll(workingDays);
            final extraNeed = workedDays - workingDays.length;
            if (extraNeed > 0) {
              presentDates.addAll(weekendDays.sublist(0, extraNeed < weekendDays.length ? extraNeed : weekendDays.length));
            }
          }

          for (final d in allDays) {
            final dateStr = DateFormat('yyyy-MM-dd').format(d);
            final key = '${empId}_$dateStr';
            await FinanceLocalStorage.attendanceBox.delete(key);
          }

          for (final d in presentDates) {
            final dateStr = DateFormat('yyyy-MM-dd').format(d);
            await FinanceLocalStorage.saveAttendanceRecord(
              branchId: empBranchId,
              data: {
                'employeeId': empId,
                'date': dateStr,
                'status': 'present',
                'note': 'Excel Summary Import',
              },
              performedBy: performedBy,
            );
            totalCount++;
          }

          for (final d in absentDates) {
            final dateStr = DateFormat('yyyy-MM-dd').format(d);
            await FinanceLocalStorage.saveAttendanceRecord(
              branchId: empBranchId,
              data: {
                'employeeId': empId,
                'date': dateStr,
                'status': 'absent',
                'note': 'Excel Summary Import',
              },
              performedBy: performedBy,
            );
            totalCount++;
          }
        }
      } else {
        final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
        for (final row in dataRows) {
          String get(int i) => i < row.length ? row[i].trim() : '';
          final lookupKey = get(0).toLowerCase();
          final dateStr = get(1);
          final rawStatus = get(2).toLowerCase();
          if (lookupKey.isEmpty || dateStr.isEmpty || rawStatus.isEmpty) continue;
          
          final empId = await getOrCreateEmployee(lookupKey, null);
          if (empId.isEmpty) continue;

          final empObj = FinanceLocalStorage.getEmployee(empId);
          final empBranchId = empObj?['branchId']?.toString() ?? branchId;
          
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
          await FinanceLocalStorage.saveAttendanceRecord(branchId: empBranchId, data: record, performedBy: performedBy);
          totalCount++;
        }
      }
    }
    return totalCount;
  }

  static Future<int> _importExpenses(Map<String, List<List<String>>> sheetsMap, String branchId, String performedBy, String performedByName) async {
    int totalCount = 0;
    for (final sheetName in sheetsMap.keys) {
      final rows = sheetsMap[sheetName] ?? [];
      if (rows.isEmpty) continue;
      
      final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
      for (final row in dataRows) {
        String get(int i) => i < row.length ? row[i].trim() : '';

        final dateStr = get(0);
        final rawCategory = get(1);
        final customCategory = get(2);
        final amount = double.tryParse(get(3).replaceAll(',', '')) ?? 0.0;
        final description = get(4);

        if (dateStr.isEmpty || rawCategory.isEmpty || amount <= 0 || description.isEmpty) continue;

        DateTime date;
        try {
          date = DateFormat('yyyy-MM-dd').parse(dateStr);
        } catch (_) {
          date = DateTime.now();
        }

        final bId = branchId == 'all' ? 'hq' : branchId;

        await FinanceExpensesStorage.saveExpense(
          branchId: bId,
          amount: amount,
          category: rawCategory,
          customCategory: customCategory.isNotEmpty ? customCategory : null,
          description: description,
          performedBy: performedBy,
          performedByName: performedByName,
          date: date,
        );
        totalCount++;
      }
    }
    return totalCount;
  }

  static Future<int> _importSchoolStudents(Map<String, List<List<String>>> sheetsMap, String branchId) async {
    int totalCount = 0;
    if (!Hive.isBoxOpen(LocalStorageService.schoolStudentsBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.schoolStudentsBox);
    }
    if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.biometricCredentialsBox);
    }
    final box = Hive.box(LocalStorageService.schoolStudentsBox);
    final credBox = Hive.box(LocalStorageService.biometricCredentialsBox);

    for (final sheetName in sheetsMap.keys) {
      final rows = sheetsMap[sheetName] ?? [];
      if (rows.length < 2) continue;

      final headers = rows.first.map((e) => e.toLowerCase().trim()).toList();
      final nameIdx = _findColumnIndex(headers, ['name', 'student name', 'full name', 'naam']);
      final grIdx = _findColumnIndex(headers, ['gr_no', 'gr no', 'gr', 'roll_no', 'roll no', 'id']);
      final classIdx = _findColumnIndex(headers, ['class', 'grade', 'standard']);
      final secIdx = _findColumnIndex(headers, ['section', 'sec']);
      final fatherIdx = _findColumnIndex(headers, ['father name', 'father_name', 'walid ka naam']);
      final phoneIdx = _findColumnIndex(headers, ['phone', 'mobile', 'contact']);

      final dataRows = rows.sublist(1);
      for (final row in dataRows) {
        String get(int idx) => idx != -1 && idx < row.length ? row[idx].trim() : '';
        final name = nameIdx != -1 ? get(nameIdx) : (row.isNotEmpty ? get(0) : '');
        if (name.isEmpty) continue;

        final grNo = grIdx != -1 && get(grIdx).isNotEmpty ? get(grIdx) : DateTime.now().millisecondsSinceEpoch.toString().substring(6);
        final studentObj = {
          'id': grNo,
          'grNo': grNo,
          'name': name,
          'fatherName': fatherIdx != -1 && get(fatherIdx).isNotEmpty ? get(fatherIdx) : 'N/A',
          'grade': classIdx != -1 && get(classIdx).isNotEmpty ? get(classIdx) : 'Class 1',
          'section': secIdx != -1 && get(secIdx).isNotEmpty ? get(secIdx) : 'A',
          'phone': phoneIdx != -1 ? get(phoneIdx) : '',
          'branchId': branchId,
          'status': 'Active',
          'updatedAt': DateTime.now().toIso8601String(),
        };

        await box.put(grNo, studentObj);

        // Biometric Mapping
        await credBox.put(grNo, {
          'pin': grNo,
          'entityId': grNo,
          'entityName': name,
          'entityType': 'school_student',
          'branchId': branchId,
        });

        totalCount++;
      }
    }
    return totalCount;
  }

  static Future<int> _importMadrassaStudents(Map<String, List<List<String>>> sheetsMap, String branchId) async {
    int totalCount = 0;
    if (!Hive.isBoxOpen(LocalStorageService.madrassaStudentsBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.madrassaStudentsBox);
    }
    if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.biometricCredentialsBox);
    }
    final box = Hive.box(LocalStorageService.madrassaStudentsBox);
    final credBox = Hive.box(LocalStorageService.biometricCredentialsBox);

    for (final sheetName in sheetsMap.keys) {
      final rows = sheetsMap[sheetName] ?? [];
      if (rows.length < 2) continue;

      final headers = rows.first.map((e) => e.toLowerCase().trim()).toList();
      final nameIdx = _findColumnIndex(headers, ['name', 'student name', 'full name', 'naam', 'taalib ilam']);
      final regIdx = _findColumnIndex(headers, ['reg_no', 'registration no', 'roll_no', 'roll no', 'id']);
      final deptIdx = _findColumnIndex(headers, ['department', 'dept', 'darja', 'class']);
      final secIdx = _findColumnIndex(headers, ['section', 'sec']);
      final fatherIdx = _findColumnIndex(headers, ['father name', 'father_name', 'walid ka naam']);
      final phoneIdx = _findColumnIndex(headers, ['phone', 'mobile', 'contact']);

      final dataRows = rows.sublist(1);
      for (final row in dataRows) {
        String get(int idx) => idx != -1 && idx < row.length ? row[idx].trim() : '';
        final name = nameIdx != -1 ? get(nameIdx) : (row.isNotEmpty ? get(0) : '');
        if (name.isEmpty) continue;

        final regNo = regIdx != -1 && get(regIdx).isNotEmpty ? get(regIdx) : DateTime.now().millisecondsSinceEpoch.toString().substring(6);
        final studentObj = {
          'id': regNo,
          'registrationNo': regNo,
          'name': name,
          'fatherName': fatherIdx != -1 && get(fatherIdx).isNotEmpty ? get(fatherIdx) : 'N/A',
          'department': deptIdx != -1 && get(deptIdx).isNotEmpty ? get(deptIdx) : 'Hifz',
          'section': secIdx != -1 && get(secIdx).isNotEmpty ? get(secIdx) : 'A',
          'phone': phoneIdx != -1 ? get(phoneIdx) : '',
          'branchId': branchId,
          'status': 'Active',
          'updatedAt': DateTime.now().toIso8601String(),
        };

        await box.put(regNo, studentObj);

        // Biometric Mapping
        await credBox.put(regNo, {
          'pin': regNo,
          'entityId': regNo,
          'entityName': name,
          'entityType': 'madrassa_student',
          'branchId': branchId,
        });

        totalCount++;
      }
    }
    return totalCount;
  }

  static Future<int> _importDonations(Map<String, List<List<String>>> sheetsMap, String branchId) async {
    int totalCount = 0;
    if (!Hive.isBoxOpen(LocalStorageService.donationsBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.donationsBox);
    }
    final box = Hive.box(LocalStorageService.donationsBox);

    for (final sheetName in sheetsMap.keys) {
      final rows = sheetsMap[sheetName] ?? [];
      if (rows.length < 2) continue;

      final headers = rows.first.map((e) => e.toLowerCase().trim()).toList();
      final nameIdx = _findColumnIndex(headers, ['donor name', 'name', 'full name', 'donor']);
      final amountIdx = _findColumnIndex(headers, ['amount', 'rs', 'rupees', 'total', 'rakam']);
      final typeIdx = _findColumnIndex(headers, ['type', 'category', 'zakat/sadqah', 'fund']);
      final dateIdx = _findColumnIndex(headers, ['date', 'receipt date', 'tareekh']);
      final rcptIdx = _findColumnIndex(headers, ['receipt no', 'receipt_no', 'rcpt no', 'slip no']);
      final modeIdx = _findColumnIndex(headers, ['mode', 'payment mode', 'cash/bank']);

      final dataRows = rows.sublist(1);
      for (final row in dataRows) {
        String get(int idx) => idx != -1 && idx < row.length ? row[idx].trim() : '';
        final name = nameIdx != -1 && get(nameIdx).isNotEmpty ? get(nameIdx) : 'Anonymous Donor';
        final amount = amountIdx != -1 ? (double.tryParse(get(amountIdx).replaceAll(',', '')) ?? 0.0) : 0.0;
        if (amount <= 0 && name == 'Anonymous Donor') continue;

        final id = const Uuid().v4();
        final donationObj = {
          'id': id,
          'receiptNo': rcptIdx != -1 && get(rcptIdx).isNotEmpty ? get(rcptIdx) : 'RCP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
          'donorName': name,
          'amount': amount,
          'donationType': typeIdx != -1 && get(typeIdx).isNotEmpty ? get(typeIdx) : 'General',
          'paymentMode': modeIdx != -1 && get(modeIdx).isNotEmpty ? get(modeIdx) : 'Cash',
          'date': dateIdx != -1 && get(dateIdx).isNotEmpty ? get(dateIdx) : DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'branchId': branchId,
          'createdAt': DateTime.now().toIso8601String(),
        };

        await box.put(id, donationObj);
        totalCount++;
      }
    }
    return totalCount;
  }

  static Uint8List _sanitizeExcelBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();
      bool sanitized = false;

      for (final file in archive) {
        if (file.name == 'xl/styles.xml') {
          final contentBytes = file.content as List<int>;
          var xmlText = utf8.decode(contentBytes);
          
          final declRx = RegExp(r'<numFmt\s+[^>]*numFmtId="([0-9]+)"[^>]*>');
          final customIds = declRx.allMatches(xmlText)
              .map((m) => int.tryParse(m.group(1) ?? ''))
              .whereType<int>()
              .where((id) => id < 164)
              .toSet();

          if (customIds.isNotEmpty) {
            // Delete the low-ID custom format declarations
            xmlText = xmlText.replaceAllMapped(declRx, (match) {
              final idStr = match.group(1);
              if (idStr != null) {
                final id = int.tryParse(idStr) ?? 0;
                if (id < 164) {
                  return '';
                }
              }
              return match.group(0)!;
            });

            // Map all references referencing these custom low-IDs to General standard format 0
            for (final id in customIds) {
              xmlText = xmlText.replaceAll('numFmtId="$id"', 'numFmtId="0"');
            }
            sanitized = true;
          }
          final sanitizedBytes = utf8.encode(xmlText);
          newArchive.addFile(ArchiveFile('xl/styles.xml', sanitizedBytes.length, sanitizedBytes));
        } else {
          newArchive.addFile(file);
        }
      }

      if (sanitized) {
        final encoder = ZipEncoder();
        final newBytes = encoder.encode(newArchive);
        if (newBytes != null) {
          return Uint8List.fromList(newBytes);
        }
      }
    } catch (e) {
      debugPrint("Error sanitizing excel bytes: $e");
    }
    return bytes;
  }
}
