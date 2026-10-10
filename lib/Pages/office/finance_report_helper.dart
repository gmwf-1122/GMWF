import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import '../../widgets/file_action_helper.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_expenses_storage.dart';

class FinanceReportHelper {
  // Helper to format currency
  static String _fmtCurrency(double amt) {
    if (amt == 0) return '0';
    return NumberFormat('#,##0').format(amt);
  }

  static pw.ImageProvider? _cachedLogo;

  /// Loads the official GMWF logo for inclusion in PDF document headers
  static Future<pw.ImageProvider?> _loadGmwfLogo() async {
    if (_cachedLogo != null) return _cachedLogo;
    try {
      final data = await rootBundle.load('assets/logo/gmwf-1.png');
      final bytes = data.buffer.asUint8List();
      _cachedLogo = pw.MemoryImage(bytes);
      return _cachedLogo;
    } catch (e) {
      debugPrint('[FinanceReportHelper] Failed to load gmwf-1.png: $e, trying webp');
      try {
        final data = await rootBundle.load('assets/logo/gmwf-1.webp');
        final bytes = data.buffer.asUint8List();
        _cachedLogo = pw.MemoryImage(bytes);
        return _cachedLogo;
      } catch (_) {
        return null;
      }
    }
  }

  /// Converts month key like '2026-10' to readable 'October 2026'
  static String _formatMonthKeyFull(String monthKey) {
    try {
      final parts = monthKey.split('-');
      if (parts.length >= 2) {
        final yr = int.tryParse(parts[0]);
        final mo = int.tryParse(parts[1]);
        if (yr != null && mo != null) {
          final dt = DateTime(yr, mo);
          return DateFormat('MMMM yyyy').format(dt);
        }
      }
    } catch (_) {}
    return monthKey;
  }

  /// Clean, easily understandable attendance text for PDF cells
  static String _formatCleanAttendance({
    required double pCount,
    required double aCount,
    required double lCount,
    required List absentDates,
    required List leaveDates,
  }) {
    final pStr = (pCount % 1 == 0) ? '${pCount.toInt()}' : pCount.toStringAsFixed(1);
    final aStr = (aCount % 1 == 0) ? '${aCount.toInt()}' : aCount.toStringAsFixed(1);
    final lStr = (lCount % 1 == 0) ? '${lCount.toInt()}' : lCount.toStringAsFixed(1);

    final buffer = StringBuffer();
    buffer.write('$pStr Present');

    if (aCount > 0) {
      buffer.write('\n$aStr Absent');
      if (absentDates.isNotEmpty) {
        buffer.write(' (${FinanceLocalStorage.formatDayRanges(absentDates)})');
      }
    } else {
      buffer.write(' • 0 Absent');
    }

    if (lCount > 0) {
      buffer.write('\n$lStr Leave');
      if (leaveDates.isNotEmpty) {
        buffer.write(' (${FinanceLocalStorage.formatDayRanges(leaveDates)})');
      }
    }

    return buffer.toString();
  }

  static pw.Widget _buildKpiCard(String title, String value, PdfColor valueColor, {bool isHighlight = false}) {
    return pw.Container(
      padding: isHighlight ? const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4) : pw.EdgeInsets.zero,
      decoration: isHighlight
          ? pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFE0F2F1),
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: const PdfColor.fromInt(0xFF00695C), width: 0.8),
            )
          : null,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureLine(String label, String designation) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 20),
        pw.Container(
          width: 140,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey600, width: 0.8)),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
        pw.Text(designation, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ],
    );
  }

  /// Fast file picker on desktop that defaults to local Downloads/Documents directory
  /// to avoid Microsoft OneDrive / cloud folder network sync freezing on Desktop.
  static Future<String?> pickSavePathFast({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
    Uint8List? bytes,
  }) async {
    String? initialDir;
    if (Platform.isWindows) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null && downloads.existsSync()) {
          initialDir = downloads.path;
        } else {
          final docs = await getApplicationDocumentsDirectory();
          if (docs.existsSync()) initialDir = docs.path;
        }
      } catch (_) {}
    }

    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: initialDir,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
    } catch (e) {
      debugPrint('[FinanceReportHelper] pickSavePathFast error: $e');
    }

    if (path != null && bytes != null && bytes.isNotEmpty) {
      try {
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('[FinanceReportHelper] writeAsBytes error: $e');
      }
    }
    return path;
  }

  // ── 1. Individual Employee PDF Report ──────────────────────────────────────
  static Future<void> exportIndividualPdf(String employeeId) async {
    try {
      final emp = FinanceLocalStorage.getEmployee(employeeId);
      if (emp == null) throw Exception('Employee not found');

      final name = emp['name']?.toString() ?? 'N/A';
      final role = emp['role']?.toString() ?? 'N/A';
      final dept = emp['department']?.toString() ?? 'N/A';
      final branchId = emp['branchId']?.toString() ?? 'N/A';
      final cnic = emp['cnic']?.toString() ?? 'N/A';
      final phone = emp['phone']?.toString() ?? 'N/A';
      final salary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
      final advance = (emp['currentAdvanceBalance'] as num?)?.toDouble() ?? 0.0;

      final history = FinanceLocalStorage.getSalaryHistory(employeeId);
      final transfers = FinanceLocalStorage.getTransfersForEmployee(employeeId);

      // Load official GMWF Logo
      final logoImage = await _loadGmwfLogo();

      // Create PDF Document
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null) ...[
                      pw.Container(
                        width: 44,
                        height: 44,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: const PdfColor.fromInt(0xFF00695C), width: 1.2),
                        ),
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.ClipOval(
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('GULZAR MADINA WELFARE FOUNDATION',
                            style: pw.TextStyle(
                                fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF004D40))),
                        pw.Text('EMPLOYEE DOSSIER & RECORD SHEET',
                            style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF00796B))),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generated: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    pw.Text('Status: ${emp['status']?.toString().toUpperCase() ?? 'ACTIVE'}',
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: emp['isActive'] == true ? PdfColors.green700 : PdfColors.red700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF00695C)),
            pw.SizedBox(height: 14),

            // Profile Summary Grid
            pw.Text('PERSONAL & ACCOUNT PROFILE',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _buildPdfRow('Full Name', name, 'CNIC Number', cnic),
                _buildPdfRow('Phone Number', phone, 'Alternative Phone', emp['alternatePhone']?.toString() ?? 'N/A'),
                _buildPdfRow('Gender', emp['gender']?.toString() ?? 'N/A', 'Date of Birth', emp['dob']?.toString() ?? 'N/A'),
                _buildPdfRow('Marital Status', emp['maritalStatus']?.toString() ?? 'N/A', 'Relation Details', '${emp['relationshipType'] ?? "Father/Spouse"}: ${emp['relationshipName'] ?? "N/A"}'),
                _buildPdfRow('Education', emp['education']?.toString() ?? 'N/A', 'Current Address', emp['currentAddress']?.toString() ?? 'N/A'),
              ],
            ),
            pw.SizedBox(height: 20),

            // Job & Financial
            pw.Text('JOB & FINANCIAL DETAILS',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _buildPdfRow('Job Role', role, 'Department', dept),
                _buildPdfRow('Current Branch', branchId.toUpperCase(), 'Joining Date', emp['joiningDate'] ?? 'N/A'),
                _buildPdfRow('Base Salary (PKR)', 'PKR ${_fmtCurrency(salary)}', 'Advance Balance', 'PKR ${_fmtCurrency(advance)}'),
                _buildPdfRow('Bank Name', emp['bankName']?.toString() ?? 'N/A', 'Account / IBAN', emp['bankAccount']?.toString() ?? 'N/A'),
              ],
            ),
            pw.SizedBox(height: 20),

            // Salary Adjustments Log
            pw.Text('SALARY ADJUSTMENTS HISTORY',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700)),
            pw.SizedBox(height: 6),
            if (history.isEmpty)
              pw.Text('No salary adjustments recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                headers: ['Effective Date', 'Adjustment Amount', 'Reason', 'Retroactive', 'Approved By'],
                data: history.map((h) => [
                  h['effectiveDate'] != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(h['effectiveDate'])) : 'N/A',
                  'PKR ${_fmtCurrency((h['amount'] as num?)?.toDouble() ?? 0.0)}',
                  h['reason']?.toString() ?? 'N/A',
                  h['isRetroactive'] == true ? 'YES' : 'NO',
                  h['approvedBy']?.toString() ?? 'N/A',
                ]).toList(),
              ),
            pw.SizedBox(height: 20),

            // Branch Transfers
            pw.Text('BRANCH TRANSFERS LOG',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700)),
            pw.SizedBox(height: 6),
            if (transfers.isEmpty)
              pw.Text('No branch transfer logs recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                headers: ['Transfer Date', 'From Branch', 'To Branch', 'Transfer Reason', 'Approved By'],
                data: transfers.map((tr) => [
                  tr['effectiveDate'] != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(tr['effectiveDate'])) : 'N/A',
                  tr['fromBranchId']?.toString().toUpperCase() ?? 'N/A',
                  tr['toBranchId']?.toString().toUpperCase() ?? 'N/A',
                  tr['reason']?.toString() ?? 'N/A',
                  tr['approvedBy']?.toString() ?? 'N/A',
                ]).toList(),
              ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final safeName = name.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_').toLowerCase();

      await pickSavePathFast(
        dialogTitle: 'Save Employee PDF Profile',
        fileName: 'dossier_${safeName}_$dateStr.pdf',
        bytes: pdfBytes,
        allowedExtensions: ['pdf'],
      );
    } catch (_) {}
  }

  // ── 1b. Individual Employee Payment Report PDF ────────────────────────────────
  static Future<void> exportPaymentReportPdf(String employeeId) async {
    try {
      final emp = FinanceLocalStorage.getEmployee(employeeId);
      if (emp == null) throw Exception('Employee not found');

      final name = emp['name']?.toString() ?? 'N/A';
      final role = emp['role']?.toString() ?? 'N/A';
      final dept = emp['department']?.toString() ?? 'N/A';
      final branchId = emp['branchId']?.toString() ?? 'N/A';
      final salary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;

      // Get all payouts
      final payouts = FinanceLocalStorage.salaryLedgerBox.values.where((val) {
        if (val is! Map) return false;
        final entry = Map<String, dynamic>.from(val);
        return entry['employeeId'] == employeeId && entry['isVoided'] != true;
      }).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Sort payouts by date descending
      payouts.sort((a, b) {
        final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(1970);
        final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(1970);
        return db.compareTo(da);
      });

      // Get all loans and calculate outstanding
      final loansBox = Hive.box('local_finance_loans');
      final loans = loansBox.values.where((val) {
        if (val is! Map) return false;
        final entry = Map<String, dynamic>.from(val);
        return entry['employeeId'] == employeeId && entry['isVoided'] != true;
      }).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      double outstandingBalance = 0.0;
      for (final loan in loans) {
        final principal = (loan['principal'] as num?)?.toDouble() ?? 0.0;
        double paid = 0.0;
        final payments = loan['payments'] as List? ?? [];
        for (final p in payments) {
          if (p is Map && p['isVoided'] != true) {
            paid += (p['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
        final balance = (principal - paid).clamp(0.0, double.infinity);
        if (loan['status'] != 'closed' && balance > 0) {
          outstandingBalance += balance;
        }
      }

      // Group payments by Year
      final Map<int, Map<String, double>> yearlySummary = {};
      for (final p in payouts) {
        final dateStr = p['date']?.toString() ?? '';
        final parsedDate = DateTime.tryParse(dateStr);
        if (parsedDate == null) continue;
        final yr = parsedDate.year;

        yearlySummary.putIfAbsent(yr, () => {
          'baseEarned': 0.0,
          'deductions': 0.0,
          'bonuses': 0.0,
          'netPaid': 0.0,
        });

        final yrMap = yearlySummary[yr]!;
        if (p['type'] == 'payout') {
          yrMap['baseEarned'] = (yrMap['baseEarned'] ?? 0.0) + ((p['baseSalaryEarned'] as num?)?.toDouble() ?? 0.0);
          yrMap['deductions'] = (yrMap['deductions'] ?? 0.0) + ((p['absenceDeductions'] as num?)?.toDouble() ?? 0.0) + ((p['otherDeductions'] as num?)?.toDouble() ?? 0.0);
          yrMap['bonuses'] = (yrMap['bonuses'] ?? 0.0) + ((p['holidayBonus'] as num?)?.toDouble() ?? 0.0) + ((p['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0);
          yrMap['netPaid'] = (yrMap['netPaid'] ?? 0.0) + ((p['amount'] as num?)?.toDouble() ?? 0.0);
        } else if (p['type'] == 'arrears_payment') {
          yrMap['bonuses'] = (yrMap['bonuses'] ?? 0.0) + ((p['amount'] as num?)?.toDouble() ?? 0.0);
          yrMap['netPaid'] = (yrMap['netPaid'] ?? 0.0) + ((p['amount'] as num?)?.toDouble() ?? 0.0);
        }
      }

      // Load official GMWF Logo
      final logoImage = await _loadGmwfLogo();

      // Compile PDF
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null) ...[
                      pw.Container(
                        width: 44,
                        height: 44,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: const PdfColor.fromInt(0xFF00695C), width: 1.2),
                        ),
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.ClipOval(
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('GULZAR MADINA WELFARE FOUNDATION',
                            style: pw.TextStyle(
                                fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF004D40))),
                        pw.Text('EMPLOYEE PAYMENT HISTORY REPORT',
                            style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF00796B))),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generated: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    pw.Text('Branch: ${branchId.toUpperCase()}',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF004D40))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF00695C)),
            pw.SizedBox(height: 14),

            // Profile Summary Grid
            pw.Text('EMPLOYEE PROFILE INFORMATION',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _buildPdfRow('Full Name', name, 'Job Role / Dept', '$role • $dept'),
                _buildPdfRow('Base Salary Rate', 'PKR ${_fmtCurrency(salary)}', 'Outstanding Loan', 'PKR ${_fmtCurrency(outstandingBalance)}'),
              ],
            ),
            pw.SizedBox(height: 20),

            // Monthly Payroll Ledger Section
            pw.Text('MONTHLY PAYROLL LEDGER HISTORY',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            if (payouts.isEmpty)
              pw.Text('No payment records found in the ledger.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                headers: ['Month', 'Date Paid', 'Base Earned', 'Deductions', 'OT/Bonus', 'Net Paid', 'Method', 'Remarks'],
                data: payouts.map((p) {
                  final mParsed = DateFormat('yyyy-MM').parse(p['monthKey'] ?? '');
                  final mStr = DateFormat('MMM yyyy').format(mParsed);
                  final dPaid = p['date'] != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(p['date'])) : 'N/A';
                  final base = (p['baseSalaryEarned'] as num?)?.toDouble() ?? 0.0;
                  
                  final dedAbs = (p['absenceDeductions'] as num?)?.toDouble() ?? 0.0;
                  final dedOth = (p['otherDeductions'] as num?)?.toDouble() ?? 0.0;
                  final totalDed = dedAbs + dedOth;

                  final bonHol = (p['holidayBonus'] as num?)?.toDouble() ?? 0.0;
                  final bonSun = (p['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;
                  final totalBon = bonHol + bonSun;

                  final net = (p['amount'] as num?)?.toDouble() ?? 0.0;
                  final note = p['note']?.toString() ?? '';

                  return [
                    mStr,
                    dPaid,
                    'PKR ${_fmtCurrency(base)}',
                    totalDed > 0 ? '-PKR ${_fmtCurrency(totalDed)}' : 'PKR 0',
                    totalBon > 0 ? '+PKR ${_fmtCurrency(totalBon)}' : 'PKR 0',
                    'PKR ${_fmtCurrency(net)}',
                    p['paymentMethod']?.toString().toUpperCase() ?? 'N/A',
                    note.length > 25 ? '${note.substring(0, 22)}...' : note,
                  ];
                }).toList(),
              ),
            pw.SizedBox(height: 20),

            // Yearly Summary Section
            pw.Text('YEARLY FINANCIAL SUMMARY',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            if (yearlySummary.isEmpty)
              pw.Text('No yearly aggregated stats available.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                headers: ['Year', 'Total Base Earned', 'Total Deductions', 'Total Bonuses', 'Net Paid Out'],
                data: yearlySummary.entries.map((e) {
                  return [
                    e.key.toString(),
                    'PKR ${_fmtCurrency(e.value['baseEarned'] ?? 0.0)}',
                    '-PKR ${_fmtCurrency(e.value['deductions'] ?? 0.0)}',
                    '+PKR ${_fmtCurrency(e.value['bonuses'] ?? 0.0)}',
                    'PKR ${_fmtCurrency(e.value['netPaid'] ?? 0.0)}',
                  ];
                }).toList(),
              ),
            pw.SizedBox(height: 20),

            // Loans Section
            pw.Text('LOANS & ADVANCES RECORD',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            if (loans.isEmpty)
              pw.Text('No loans or salary advances recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                headers: ['Date Issued', 'Principal', 'Repay Method', 'Status', 'Payments Received', 'Remaining Balance'],
                data: loans.map((loan) {
                  final dIssued = loan['date'] != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(loan['date'])) : 'N/A';
                  final principal = (loan['principal'] as num?)?.toDouble() ?? 0.0;
                  
                  double paid = 0.0;
                  final payments = loan['payments'] as List? ?? [];
                  for (final p in payments) {
                    if (p is Map && p['isVoided'] != true) {
                      paid += (p['amount'] as num?)?.toDouble() ?? 0.0;
                    }
                  }
                  final balance = (principal - paid).clamp(0.0, double.infinity);
                  final status = loan['status']?.toString().toUpperCase() ?? 'ACTIVE';

                  return [
                    dIssued,
                    'PKR ${_fmtCurrency(principal)}',
                    loan['repaymentType']?.toString().toUpperCase() ?? 'N/A',
                    status,
                    'PKR ${_fmtCurrency(paid)}',
                    'PKR ${_fmtCurrency(balance)}',
                  ];
                }).toList(),
              ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final safeName = name.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_').toLowerCase();

      await pickSavePathFast(
        dialogTitle: 'Save Employee Payment Report',
        fileName: 'payment_report_${safeName}_$dateStr.pdf',
        bytes: pdfBytes,
        allowedExtensions: ['pdf'],
      );
    } catch (_) {}
  }

  // ── 1c. Individual Loan Statement PDF ────────────────────────────────────────
  static Future<void> exportLoanStatementPdf(Map<String, dynamic> loan) async {
    try {
      final empName = loan['employeeName']?.toString() ?? 'Employee';
      final empId = loan['employeeId']?.toString() ?? '';
      final emp = FinanceLocalStorage.getEmployee(empId);
      final branchId = loan['branchId']?.toString() ?? emp?['branchId']?.toString() ?? 'HQ';
      final role = emp?['role']?.toString() ?? 'Staff';
      final dept = emp?['department']?.toString() ?? 'N/A';

      final principalMinor = (loan['principalMinor'] as num?)?.toInt() ?? ((loan['principal'] as num?)?.toDouble() ?? 0.0 * 100).round();
      final payments = List<Map<String, dynamic>>.from(
        (loan['payments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final activePayments = payments.where((p) => p['isVoided'] != true).toList();
      final activeRepayments = activePayments.where((p) => p['type'] != 'topup' && p['type'] != 'loan_issue').toList();

      int paidMinor = 0;
      for (final p in activeRepayments) {
        paidMinor += (p['amountMinor'] as num?)?.toInt() ?? ((p['amount'] as num?)?.toDouble() ?? 0.0 * 100).round();
      }
      final outstandingMinor = (principalMinor - paidMinor).clamp(0, 9999999999);
      final isClosed = loan['status'] == 'closed' || outstandingMinor <= 0;

      // Load official GMWF Logo
      final logoImage = await _loadGmwfLogo();

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null) ...[
                      pw.Container(
                        width: 44,
                        height: 44,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: const PdfColor.fromInt(0xFF00695C), width: 1.2),
                        ),
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.ClipOval(
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('GULZAR MADINA WELFARE FOUNDATION',
                            style: pw.TextStyle(
                                fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF004D40))),
                        pw.Text('LOAN & REPAYMENT STATEMENT',
                            style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF00796B))),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generated: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    pw.Text('Status: ${isClosed ? "PAID OFF / CLOSED" : "ACTIVE LOAN"}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: isClosed ? PdfColors.green700 : PdfColors.orange800,
                        )),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF00695C)),
            pw.SizedBox(height: 14),

            // Profile Summary Grid
            pw.Text('BORROWER PROFILE & LOAN DETAILS',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _buildPdfRow('Employee Name', empName, 'Branch / Dept', '${branchId.toUpperCase()} • $dept'),
                _buildPdfRow('Job Role', role, 'Repayment Structure', loan['repaymentType'] == 'fixed' ? 'Fixed Monthly Installments' : 'Flexible Repayments'),
                _buildPdfRow('Date Issued', loan['dateIssued'] != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(loan['dateIssued'])) : 'N/A', 'Loan Reference ID', loan['id']?.toString() ?? 'N/A'),
              ],
            ),
            pw.SizedBox(height: 16),

            // Metrics Grid
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.teal700, width: 1),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal50),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        children: [
                          pw.Text('TOTAL PRINCIPAL', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
                          pw.SizedBox(height: 4),
                          pw.Text('PKR ${_fmtCurrency(principalMinor / 100)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        children: [
                          pw.Text('TOTAL REPAID', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                          pw.SizedBox(height: 4),
                          pw.Text('PKR ${_fmtCurrency(paidMinor / 100)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        children: [
                          pw.Text('OUTSTANDING BALANCE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: outstandingMinor > 0 ? PdfColors.orange900 : PdfColors.grey700)),
                          pw.SizedBox(height: 4),
                          pw.Text('PKR ${_fmtCurrency(outstandingMinor / 100)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: outstandingMinor > 0 ? PdfColors.orange900 : PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Ledger Transactions History Table
            pw.Text('COMPLETE PAYMENT & REPAYMENT HISTORY LOG',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            if (activePayments.isEmpty)
              pw.Text('No payment transactions logged.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                headers: ['Transaction Date', 'Type', 'Amount (PKR)', 'Reference / Note', 'Recorded By'],
                data: activePayments.map((p) {
                  final pDate = p['date'] != null ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(p['date'])) : 'N/A';
                  final amt = (p['amountMinor'] as num?)?.toInt() ?? ((p['amount'] as num?)?.toDouble() ?? 0.0 * 100).round();
                  final isTopup = p['type'] == 'topup' || p['type'] == 'loan_issue';
                  final note = p['note']?.toString() ?? '';

                  return [
                    pDate,
                    isTopup ? 'Loan Top-up (+)' : 'Repayment (-)',
                    'PKR ${_fmtCurrency(amt / 100)}',
                    note.isEmpty ? 'N/A' : note,
                    p['recordedBy']?.toString() ?? 'System',
                  ];
                }).toList(),
              ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final safeName = empName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_').toLowerCase();

      await pickSavePathFast(
        dialogTitle: 'Save Loan Statement PDF',
        fileName: 'loan_statement_${safeName}_$dateStr.pdf',
        bytes: pdfBytes,
        allowedExtensions: ['pdf'],
      );
    } catch (_) {}
  }


  static pw.TableRow _buildPdfRow(String label1, String val1, String label2, String val2) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(label1, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(val1, style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(label2, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(val2, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    );
  }

  // ── 1d. Individual Employee Monthly Attendance Calendar PDF ───────────────────
  static Future<Map<String, dynamic>?> exportAttendanceCalendarPdf({
    required String employeeId,
    required String monthKey,
    BuildContext? context,
  }) async {
    try {
      final emp = FinanceLocalStorage.getEmployee(employeeId);
      if (emp == null) throw Exception('Employee not found');

      final logoImage = await _loadGmwfLogo();

      final name = emp['name']?.toString() ?? 'Employee';
      final pin = (emp['biometricPin'] ?? emp['pin'] ?? '').toString().trim();
      final role = emp['role']?.toString() ?? 'Staff';
      final dept = emp['department']?.toString() ?? 'General';
      final branchId = emp['branchId']?.toString() ?? 'HQ';
      final camp = FinanceLocalStorage.getEmployeeCamp(emp);

      final summary = FinanceLocalStorage.getPayrollAttendanceSummary(employeeId, monthKey);
      final presentDays = (summary['workingDays'] as num?)?.toDouble() ?? 0.0;
      final absentDays = (summary['absentDays'] as num?)?.toDouble() ?? 0.0;
      final lateDays = (summary['lateDays'] as num?)?.toDouble() ?? 0.0;
      final paidLeaves = (summary['paidLeaves'] as num?)?.toDouble() ?? 0.0;
      final unpaidLeaves = (summary['unpaidLeaves'] as num?)?.toDouble() ?? 0.0;
      final totalLeaves = paidLeaves + unpaidLeaves;
      final holidayCount = (summary['holidayCount'] as num?)?.toInt() ?? 0;
      final totalEmployed = (summary['totalEmployedDays'] as num?)?.toInt() ?? 0;
      final pct = totalEmployed > 0 ? (presentDays / totalEmployed * 100) : 0.0;

      final dailyStatus = (summary['dailyStatus'] as Map?)?.cast<int, Map<String, dynamic>>() ?? <int, Map<String, dynamic>>{};

      final parts = monthKey.split('-');
      final yr = int.parse(parts[0]);
      final mo = int.parse(parts[1]);
      final daysInMonth = FinanceLocalStorage.getDaysInMonth(monthKey);

      final pdf = pw.Document();

      final List<List<String>> ledgerRows = [];

      for (var d = 1; d <= daysInMonth; d++) {
        final date = DateTime(yr, mo, d);
        final dateStr = DateFormat('dd MMM yyyy (EEE)').format(date);
        final st = dailyStatus[d] ?? {};
        final statusRaw = st['status']?.toString().toLowerCase() ?? '';
        final isSunday = date.weekday == DateTime.sunday;
        final isHoliday = st['isHoliday'] == true;

        String statusLabel = '—';
        if (statusRaw == 'present') {
          statusLabel = 'Present';
        } else if (statusRaw == 'late') {
          statusLabel = 'Late';
        } else if (statusRaw == 'leave' || statusRaw == 'paid_leave' || statusRaw == 'half_day') {
          statusLabel = 'On Leave';
        } else if (statusRaw == 'absent') {
          statusLabel = 'Absent';
        } else if (isHoliday) {
          statusLabel = 'Holiday';
        } else if (isSunday) {
          statusLabel = 'Sunday Off';
        }

        final inTime = st['checkInTime']?.toString() ?? '';
        final outTime = st['checkOutTime']?.toString() ?? '';
        final isRunning = st['isRunning'] == true;
        final rawDur = st['workDurationFormatted']?.toString() ?? '';

        String timeDisplay = '—';
        if (inTime.isNotEmpty) {
          if (isRunning) {
            timeDisplay = '$inTime (Running)';
          } else if (outTime.isNotEmpty) {
            timeDisplay = '$inTime - $outTime';
          } else {
            timeDisplay = inTime;
          }
        }

        String durDisplay = rawDur.isNotEmpty ? rawDur : '—';
        final notes = st['notes']?.toString() ?? '';

        ledgerRows.add([
          '$d',
          dateStr,
          statusLabel,
          timeDisplay,
          durDisplay,
          notes.isNotEmpty ? notes : (isSunday ? 'Weekly Rest Day' : '—'),
        ]);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          build: (context) => [
            // Institutional Header
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) ...[
                  pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFF00695C), width: 1.5),
                    ),
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.ClipOval(
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.SizedBox(width: 14),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'GULZAR MADINA WELFARE FOUNDATION',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF004D40),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'MONTHLY ATTENDANCE STATEMENT & DUTY LOG',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF00796B),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Employee: $name ${pin.isNotEmpty ? '(PIN: $pin)' : ''} • Role: $role • Dept: $dept${camp.isNotEmpty ? ' • [$camp]' : ''}',
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFE0F2F1),
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFF80CBC4), width: 1),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        _formatMonthKeyFull(monthKey).toUpperCase(),
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF004D40)),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Branch: ${branchId.toUpperCase()}',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF00695C)),
            pw.SizedBox(height: 8),

            // KPI Badges Summary
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF4FBF9),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFB2DFDB), width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildKpiCard('Present Days', '${presentDays.toInt()} Days', PdfColors.green800),
                  _buildKpiCard('Late Days', '${lateDays.toInt()} Days', lateDays > 0 ? PdfColors.orange800 : PdfColors.grey700),
                  _buildKpiCard('Paid / Leaves', '${totalLeaves.toInt()} Days', totalLeaves > 0 ? PdfColors.blue800 : PdfColors.grey700),
                  _buildKpiCard('Public Holidays', '$holidayCount Days', PdfColors.purple800),
                  _buildKpiCard('Absent Days', '${absentDays.toInt()} Days', absentDays > 0 ? PdfColors.red800 : PdfColors.grey700),
                  _buildKpiCard('Duty Fulfillment', '${pct.toStringAsFixed(0)}% (${presentDays.toInt()}/$totalEmployed)', const PdfColor.fromInt(0xFF00695C), isHighlight: true),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Daily Punch Table
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder(
                horizontalInside: const pw.BorderSide(color: PdfColor.fromInt(0xFFCFD8DC), width: 0.5),
                verticalInside: const pw.BorderSide(color: PdfColor.fromInt(0xFFCFD8DC), width: 0.5),
                top: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
                bottom: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
                left: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
                right: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
              ),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF004D40)),
              headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7FAFA)),
              headers: ['Day', 'Date', 'Status', 'Check-In / Out Times', 'Duty Duration', 'Notes / Remarks'],
              data: ledgerRows,
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.centerLeft,
              },
              headerAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.centerLeft,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(1.8),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(2.2),
                4: const pw.FlexColumnWidth(1.4),
                5: const pw.FlexColumnWidth(2.0),
              },
            ),
            pw.SizedBox(height: 14),

            // Signatures block
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFCFD8DC), width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildSignatureLine('Employee Signature', name),
                  _buildSignatureLine('Verified By', 'Admin / HR Manager'),
                  _buildSignatureLine('Approved By', 'Branch Incharge / Director'),
                ],
              ),
            ),
          ],
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Gulzar Madina Welfare Foundation • Official Attendance & Biometric Duty Record',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      final pdfBytes = await pdf.save();
      final safeName = name.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_').toLowerCase();
      final fileName = 'attendance_${safeName}_$monthKey.pdf';

      String? path;
      try {
        path = await pickSavePathFast(
          dialogTitle: 'Save Attendance Statement PDF',
          fileName: fileName,
          bytes: pdfBytes,
          allowedExtensions: ['pdf'],
        );
      } catch (_) {}

      final result = {'path': path, 'bytes': pdfBytes, 'name': fileName};
      if (context != null && context.mounted) {
        FileActionHelper.showFileOptions(
          context,
          filePath: path,
          bytes: pdfBytes,
          fileName: fileName,
          title: 'Attendance Statement Ready',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[FinanceReportHelper] exportAttendanceCalendarPdf error: $e');
      return null;
    }
  }

  // ── 2. Excel Monthly Payroll & Attendance Sheet (Branch / Department / Camp) ──────
  static Future<Map<String, dynamic>?> exportMonthlyExcel({
    required String branchId,
    required String monthKey,
    String? department,
    String? camp,
    List<String>? employeeIds,
    BuildContext? context,
  }) async {
    try {
      try {
        await FinanceLocalStorage.downloadAttendance(branchId, monthKey: monthKey, force: false, camp: camp)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}

      final employees = FinanceLocalStorage.getEmployees(branchId).where((emp) {
        // Exclude executive level (CEO, Chairman, Directors, etc.)
        if (FinanceLocalStorage.isExecutiveEmployee(emp)) return false;

        // Filter specific department if requested
        if (department != null && department.isNotEmpty && department != 'All' && department != 'All Departments') {
          final d1 = FinanceLocalStorage.normalizeDepartment(emp['department']?.toString());
          final d2 = FinanceLocalStorage.normalizeDepartment(department);
          if (d1.toLowerCase() != d2.toLowerCase()) return false;
        }

        // Filter specific camp if requested
        if (camp != null && camp.isNotEmpty && camp != 'All' && camp != 'All Camps') {
          final empCamp = FinanceLocalStorage.getEmployeeCamp(emp);
          if (empCamp.toLowerCase() != camp.toLowerCase()) return false;
        }

        // Filter specific people if selected
        if (employeeIds != null && employeeIds.isNotEmpty) {
          final id = emp['localId']?.toString() ?? '';
          final rId = emp['remoteId']?.toString() ?? '';
          if (!employeeIds.contains(id) && !employeeIds.contains(rId)) return false;
        }

        return true;
      }).toList();

      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Payroll Sheet');

      final sheet = excel['Payroll Sheet'];

      // Header info
      sheet.appendRow([xl.TextCellValue('GULZAR MADINA WELFARE FOUNDATION')]);
      sheet.appendRow([xl.TextCellValue('Payroll & Attendance Monthly Sheet')]);
      final headerMeta = <xl.CellValue>[
        xl.TextCellValue('Branch: ${branchId.toUpperCase()}'),
        xl.TextCellValue('Month: $monthKey'),
        xl.TextCellValue(department != null && department != 'All' && department != 'All Departments' ? 'Department: $department' : 'Department: All Departments'),
      ];
      if (camp != null && camp.isNotEmpty && camp != 'All' && camp != 'All Camps') {
        headerMeta.add(xl.TextCellValue('Camp: $camp'));
      }
      sheet.appendRow(headerMeta);
      sheet.appendRow([]); // empty spacing

      // Table Headers
      final headers = [
        'ID',
        'Employee Name',
        'CNIC',
        'Role',
        'Department',
        'Camp / Location',
        'Joining Date',
        'Status',
        'Base Salary',
        'Present Days',
        'Present Dates',
        'Absent Days',
        'Absent Dates',
        'Paid Leaves',
        'Leave Dates',
        'Unpaid Leaves',
        'Unmarked Days',
        'Earned Base Pay',
        'Absence Deductions',
        'Advance Recovered',
        'Holiday Bonus',
        'Sunday Overtime Bonus',
        'Net Payable Salary',
        'Payment Method',
        'Bank Name',
        'Account / IBAN'
      ];
      sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

      // Design: Style Headers Row
      final headerStyle = xl.CellStyle(
        bold: true,
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
      );
      final headerRowIndex = 4;
      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRowIndex));
        cell.cellStyle = headerStyle;
      }

      // Design: Configure Cell/Column sizes properly to avoid truncation
      final Map<int, double> colWidths = {
        0: 12,  // ID
        1: 25,  // Employee Name
        2: 18,  // CNIC
        3: 22,  // Role
        4: 18,  // Department
        5: 18,  // Camp / Location
        6: 15,  // Joining Date
        7: 12,  // Status
        8: 15,  // Base Salary
        9: 12,  // Present Days
        10: 20, // Present Dates
        11: 12, // Absent Days
        12: 18, // Absent Dates
        13: 12, // Paid Leaves
        14: 18, // Leave Dates
        15: 12, // Unpaid Leaves
        16: 14, // Unmarked Days
        17: 16, // Earned Base Pay
        18: 16, // Absence Deductions
        19: 16, // Advance Recovered
        20: 16, // Holiday Bonus
        21: 18, // Sunday Overtime Bonus
        22: 18, // Net Payable Salary
        23: 16, // Payment Method
        24: 20, // Bank Name
        25: 24, // Account / IBAN
      };
      colWidths.forEach((colIndex, width) {
        sheet.setColumnWidth(colIndex, width);
      });

      final advanceDeductionsByEmp = <String, double>{};
      for (final val in FinanceLocalStorage.salaryLedgerBox.values) {
        if (val is Map) {
          final entry = Map<String, dynamic>.from(val);
          if (entry['monthKey'] == monthKey && entry['type'] == 'payout' && entry['isVoided'] != true) {
            final eId = entry['employeeId']?.toString();
            if (eId != null && !advanceDeductionsByEmp.containsKey(eId)) {
              advanceDeductionsByEmp[eId] = (entry['advanceDeductions'] as num?)?.toDouble() ?? 0.0;
            }
          }
        }
      }

      // Row Data
      for (final emp in employees) {
        final empId = emp['localId']?.toString() ?? '';
        final name = emp['name']?.toString() ?? 'N/A';
        final cnic = emp['cnic']?.toString() ?? 'N/A';
        final role = emp['role']?.toString() ?? 'N/A';
        final dept = emp['department']?.toString() ?? 'N/A';
        final empCamp = FinanceLocalStorage.getEmployeeCamp(emp);
        final joining = emp['joiningDate']?.toString() ?? 'N/A';
        final activeStatus = emp['status']?.toString() ?? 'Active';

        final summary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, monthKey);
        final baseSalary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
        final advanceRecovered = advanceDeductionsByEmp[empId] ?? 0.0;

        final earnedBase = (summary['baseSalaryEarned'] as num?)?.toDouble() ?? 0.0;
        final absenceDed = (summary['absenceDeductions'] as num?)?.toDouble() ?? 0.0;
        final holBonus = (summary['holidayBonus'] as num?)?.toDouble() ?? 0.0;
        final sunBonus = (summary['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;

        final netPayable = (earnedBase - absenceDed - advanceRecovered + holBonus + sunBonus).clamp(0.0, double.infinity);

        final row = [
          xl.TextCellValue(empId.substring(0, min(empId.length, 8))),
          xl.TextCellValue(name),
          xl.TextCellValue(cnic),
          xl.TextCellValue(role),
          xl.TextCellValue(dept),
          xl.TextCellValue(empCamp.isNotEmpty ? empCamp : (branchId.toLowerCase().contains('karachi') ? 'Main Branch' : '-')),
          xl.TextCellValue(joining),
          xl.TextCellValue(activeStatus),
          xl.DoubleCellValue(baseSalary),
          xl.DoubleCellValue((summary['workingDays'] as num?)?.toDouble() ?? 0.0),
          xl.TextCellValue(FinanceLocalStorage.formatDayRanges(summary['presentDates'] as List? ?? [])),
          xl.DoubleCellValue((summary['absentDays'] as num?)?.toDouble() ?? 0.0),
          xl.TextCellValue(FinanceLocalStorage.formatDayRanges(summary['absentDates'] as List? ?? [])),
          xl.DoubleCellValue((summary['paidLeaves'] as num?)?.toDouble() ?? 0.0),
          xl.TextCellValue(FinanceLocalStorage.formatDayRanges(summary['paidLeaveDates'] as List? ?? [])),
          xl.DoubleCellValue((summary['unpaidLeaves'] as num?)?.toDouble() ?? 0.0),
          xl.IntCellValue((summary['unmarkedDays'] as num?)?.toInt() ?? 0),
          xl.DoubleCellValue(earnedBase),
          xl.DoubleCellValue(absenceDed),
          xl.DoubleCellValue(advanceRecovered),
          xl.DoubleCellValue(holBonus),
          xl.DoubleCellValue(sunBonus),
          xl.DoubleCellValue(netPayable),
          xl.TextCellValue(emp['paymentMethod']?.toString() ?? 'Cash'),
          xl.TextCellValue(emp['bankName']?.toString() ?? 'N/A'),
          xl.TextCellValue(emp['bankAccount']?.toString() ?? 'N/A'),
        ];
        sheet.appendRow(row);
      }

      final excelBytes = excel.encode() != null ? Uint8List.fromList(excel.encode()!) : Uint8List(0);
      final dateStr = DateFormat('yyyy-MM').format(DateTime.now());
      final deptStr = department != null ? '_${department.toLowerCase()}' : '';
      final fileName = 'payroll_${branchId}_$monthKey${deptStr}_$dateStr.xlsx';

      String? path;
      try {
        path = await pickSavePathFast(
          dialogTitle: 'Save Excel Report',
          fileName: fileName,
          bytes: excelBytes,
          allowedExtensions: ['xlsx'],
        );
      } catch (_) {}

      final result = {'path': path, 'bytes': excelBytes, 'name': fileName};
      if (context != null && context.mounted) {
        FileActionHelper.showFileOptions(
          context,
          filePath: path,
          bytes: excelBytes,
          fileName: fileName,
          title: 'Monthly Excel Sheet Ready',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[FinanceReportHelper] exportMonthlyExcel error: $e');
      return null;
    }
  }

  // ── 3. Excel Consolidated Report: All Branches categorized branch-wise ──────
  static Future<Map<String, dynamic>?> exportConsolidatedAllBranchesExcel({
    required List<Map<String, dynamic>> branches,
    required String monthKey,
    BuildContext? context,
  }) async {
    try {
      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Summary Overview');

      final summarySheet = excel['Summary Overview'];
      summarySheet.appendRow([xl.TextCellValue('GULZAR MADINA WELFARE FOUNDATION')]);
      summarySheet.appendRow([xl.TextCellValue('CONSOLIDATED ALL-BRANCHES PAYROLL SHEET')]);
      summarySheet.appendRow([xl.TextCellValue('Month context: $monthKey'), xl.TextCellValue('Exported: ${DateTime.now()}')]);
      summarySheet.appendRow([]);

      final summaryHeaders = ['Branch Code', 'Branch Name', 'Active Employees', 'Total Base Salaries (PKR)'];
      summarySheet.appendRow(summaryHeaders.map((h) => xl.TextCellValue(h)).toList());

      final headerStyle = xl.CellStyle(
        bold: true,
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
      );

      // Format Summary Headers
      for (int c = 0; c < summaryHeaders.length; c++) {
        summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 4)).cellStyle = headerStyle;
      }
      summarySheet.setColumnWidth(0, 16); // Branch Code
      summarySheet.setColumnWidth(1, 25); // Branch Name
      summarySheet.setColumnWidth(2, 20); // Active Employees
      summarySheet.setColumnWidth(3, 28); // Total Base Salaries

      // Fetch employees across all branches and dynamically create sheets
      for (final b in branches) {
        final bId = b['id']?.toString() ?? '';
        final bName = b['name']?.toString() ?? bId;
        if (bId == 'all' || bId.isEmpty) continue;

        final list = FinanceLocalStorage.getEmployees(bId)
            .where((e) => !FinanceLocalStorage.isExecutiveEmployee(e))
            .toList();
        final activeList = list.where((e) => e['isActive'] == true).toList();
        final totalBaseSalary = activeList.map((e) => (e['currentSalary'] as num?)?.toDouble() ?? 0.0).sum;

        // Append to summary sheet
        summarySheet.appendRow([
          xl.TextCellValue(bId.toUpperCase()),
          xl.TextCellValue(bName),
          xl.IntCellValue(activeList.length),
          xl.DoubleCellValue(totalBaseSalary),
        ]);

        // Create individual tab for this branch
        final tabName = bName.replaceAll(RegExp(r'[^\w\s]'), '');
        final sheetName = tabName.substring(0, min(tabName.length, 30));

        final brSheet = excel[sheetName];

        brSheet.appendRow([xl.TextCellValue('BRANCH STAFF REGISTER: ${bName.toUpperCase()}')]);
        brSheet.appendRow([xl.TextCellValue('Status details: Active vs Offboarded')]);
        brSheet.appendRow([]);

        final headers = [
          'ID',
          'Name',
          'CNIC',
          'Role',
          'Department',
          'Camp / Location',
          'Status',
          'Joining Date',
          'Current Salary Rate',
          'Advance Balance'
        ];
        brSheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

        // Style Branch Headers
        for (int c = 0; c < headers.length; c++) {
          brSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 3)).cellStyle = headerStyle;
        }
        // Set Branch Sheet Column Widths
        final Map<int, double> brColWidths = {
          0: 12,  // ID
          1: 25,  // Name
          2: 18,  // CNIC
          3: 22,  // Role
          4: 18,  // Department
          5: 18,  // Camp / Location
          6: 12,  // Status
          7: 15,  // Joining Date
          8: 20,  // Current Salary Rate
          9: 20,  // Advance Balance
        };
        brColWidths.forEach((colIndex, width) {
          brSheet.setColumnWidth(colIndex, width);
        });

        for (final emp in list) {
          final empCamp = FinanceLocalStorage.getEmployeeCamp(emp);
          brSheet.appendRow([
            xl.TextCellValue(emp['localId']?.toString().substring(0, min((emp['localId']?.toString() ?? '').length, 8)) ?? 'N/A'),
            xl.TextCellValue(emp['name']?.toString() ?? 'N/A'),
            xl.TextCellValue(emp['cnic']?.toString() ?? 'N/A'),
            xl.TextCellValue(emp['role']?.toString() ?? 'N/A'),
            xl.TextCellValue(emp['department']?.toString() ?? 'N/A'),
            xl.TextCellValue(empCamp.isNotEmpty ? empCamp : (bId.toLowerCase().contains('karachi') ? 'Main Branch' : '-')),
            xl.TextCellValue(emp['status']?.toString() ?? 'Active'),
            xl.TextCellValue(emp['joiningDate']?.toString() ?? 'N/A'),
            xl.DoubleCellValue((emp['currentSalary'] as num?)?.toDouble() ?? 0.0),
            xl.DoubleCellValue((emp['currentAdvanceBalance'] as num?)?.toDouble() ?? 0.0),
          ]);
        }
      }

      final excelBytes = excel.encode() != null ? Uint8List.fromList(excel.encode()!) : Uint8List(0);
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final fileName = 'consolidated_payroll_${monthKey}_$dateStr.xlsx';

      String? path;
      try {
        path = await pickSavePathFast(
          dialogTitle: 'Save Consolidated Report',
          fileName: fileName,
          bytes: excelBytes,
          allowedExtensions: ['xlsx'],
        );
      } catch (_) {}

      final result = {'path': path, 'bytes': excelBytes, 'name': fileName};
      if (context != null && context.mounted) {
        FileActionHelper.showFileOptions(
          context,
          filePath: path,
          bytes: excelBytes,
          fileName: fileName,
          title: 'Consolidated Payroll Sheet Ready',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[FinanceReportHelper] exportConsolidatedAllBranchesExcel error: $e');
      return null;
    }
  }

  // ── 4. PDF Monthly Payroll & Attendance Sheet (Branch / Department / Camp) ────────
  static Future<Map<String, dynamic>?> exportMonthlyPdf({
    required String branchId,
    required String monthKey,
    String? department,
    String? camp,
    List<String>? employeeIds,
    BuildContext? context,
  }) async {
    try {
      try {
        await FinanceLocalStorage.downloadAttendance(branchId, monthKey: monthKey, force: false, camp: camp)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}

      final employees = FinanceLocalStorage.getEmployees(branchId).where((emp) {
        // Exclude executive level (CEO, Chairman, Directors, etc.)
        if (FinanceLocalStorage.isExecutiveEmployee(emp)) return false;

        // Filter specific department if requested
        if (department != null && department.isNotEmpty && department != 'All' && department != 'All Departments') {
          final d1 = FinanceLocalStorage.normalizeDepartment(emp['department']?.toString());
          final d2 = FinanceLocalStorage.normalizeDepartment(department);
          if (d1.toLowerCase() != d2.toLowerCase()) return false;
        }

        // Filter specific camp if requested
        if (camp != null && camp.isNotEmpty && camp != 'All' && camp != 'All Camps') {
          final empCamp = FinanceLocalStorage.getEmployeeCamp(emp);
          if (empCamp.toLowerCase() != camp.toLowerCase()) return false;
        }

        // Filter specific people if selected
        if (employeeIds != null && employeeIds.isNotEmpty) {
          final id = emp['localId']?.toString() ?? '';
          final rId = emp['remoteId']?.toString() ?? '';
          if (!employeeIds.contains(id) && !employeeIds.contains(rId)) return false;
        }

        return true;
      }).toList();

      // 1. Load official GMWF Logo
      final logoImage = await _loadGmwfLogo();

      final pdf = pw.Document();

      final List<List<String>> tableData = [];
      double totalBase = 0.0;
      double totalDeductions = 0.0;
      double totalBonuses = 0.0;
      double totalNet = 0.0;
      double totalPresentDays = 0.0;
      double totalAbsentDays = 0.0;

      final advanceDeductionsByEmp = <String, double>{};
      for (final val in FinanceLocalStorage.salaryLedgerBox.values) {
        if (val is Map) {
          final entry = Map<String, dynamic>.from(val);
          if (entry['monthKey'] == monthKey && entry['type'] == 'payout' && entry['isVoided'] != true) {
            final eId = entry['employeeId']?.toString();
            if (eId != null && !advanceDeductionsByEmp.containsKey(eId)) {
              advanceDeductionsByEmp[eId] = (entry['advanceDeductions'] as num?)?.toDouble() ?? 0.0;
            }
          }
        }
      }

      int sr = 1;
      for (final emp in employees) {
        final empId = emp['localId']?.toString() ?? '';
        final name = emp['name']?.toString() ?? 'N/A';
        final pin = (emp['biometricPin'] ?? emp['pin'] ?? '').toString().trim();
        final role = emp['role']?.toString() ?? 'N/A';
        final dept = emp['department']?.toString() ?? 'N/A';
        final empCamp = FinanceLocalStorage.getEmployeeCamp(emp);

        final summary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, monthKey);
        final baseSalary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
        final advanceRecovered = advanceDeductionsByEmp[empId] ?? 0.0;

        final earnedBase = (summary['baseSalaryEarned'] as num?)?.toDouble() ?? 0.0;
        final absenceDed = (summary['absenceDeductions'] as num?)?.toDouble() ?? 0.0;
        final holBonus = (summary['holidayBonus'] as num?)?.toDouble() ?? 0.0;
        final sunBonus = (summary['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;

        final deductions = absenceDed + advanceRecovered;
        final bonuses = holBonus + sunBonus;
        final netPayable = (earnedBase - deductions + bonuses).clamp(0.0, double.infinity);

        totalBase += baseSalary;
        totalDeductions += deductions;
        totalBonuses += bonuses;
        totalNet += netPayable;

        final pCount = (summary['workingDays'] as num?)?.toDouble() ?? 0.0;
        final aCount = (summary['absentDays'] as num?)?.toDouble() ?? 0.0;
        final lCount = (summary['paidLeaves'] as num?)?.toDouble() ?? 0.0;
        final absentDates = summary['absentDates'] as List? ?? [];
        final leaveDates = summary['paidLeaveDates'] as List? ?? [];

        totalPresentDays += pCount;
        totalAbsentDays += aCount;

        // Clean, easily understandable attendance display
        final attDisplay = _formatCleanAttendance(
          pCount: pCount,
          aCount: aCount,
          lCount: lCount,
          absentDates: absentDates,
          leaveDates: leaveDates,
        );

        final pinTag = pin.isNotEmpty ? '\nPIN: $pin' : '';
        final campTag = empCamp.isNotEmpty ? ' • $empCamp' : '';

        tableData.add([
          '$sr',
          '$name$pinTag',
          '$role\n$dept$campTag',
          attDisplay,
          _fmtCurrency(baseSalary),
          deductions > 0 ? _fmtCurrency(deductions) : '-',
          bonuses > 0 ? _fmtCurrency(bonuses) : '-',
          _fmtCurrency(netPayable),
        ]);
        sr++;
      }

      // Add Grand Totals Row
      final pTotalStr = (totalPresentDays % 1 == 0) ? '${totalPresentDays.toInt()}' : totalPresentDays.toStringAsFixed(1);
      final aTotalStr = (totalAbsentDays % 1 == 0) ? '${totalAbsentDays.toInt()}' : totalAbsentDays.toStringAsFixed(1);
      tableData.add([
        '',
        'GRAND TOTALS',
        '${employees.length} Staff Members',
        '$pTotalStr P • $aTotalStr A',
        _fmtCurrency(totalBase),
        _fmtCurrency(totalDeductions),
        _fmtCurrency(totalBonuses),
        _fmtCurrency(totalNet),
      ]);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          build: (context) => [
            // 1. Official Institutional Header with GMWF Logo
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) ...[
                  pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFF00695C), width: 1.5),
                    ),
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.ClipOval(
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.SizedBox(width: 14),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'GULZAR MADINA WELFARE FOUNDATION',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF004D40),
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'MONTHLY STAFF PAYROLL & ATTENDANCE STATEMENT',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF00796B),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Branch: ${branchId.toUpperCase()}${camp != null && camp.isNotEmpty && camp != 'All' && camp != 'All Camps' ? ' • Camp: $camp' : ''}${department != null && department.isNotEmpty && department != 'All' && department != 'All Departments' ? ' • Dept: $department' : ''}',
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFE0F2F1),
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFF80CBC4), width: 1),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        _formatMonthKeyFull(monthKey).toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF004D40),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Total Staff: ${employees.length} Members',
                        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF00695C)),
            pw.SizedBox(height: 8),

            // 2. Executive Financial KPI Summary Cards
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF4FBF9),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFB2DFDB), width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildKpiCard('Total Employees', '${employees.length} Staff', const PdfColor.fromInt(0xFF004D40)),
                  _buildKpiCard('Gross Base Salary', 'PKR ${_fmtCurrency(totalBase)}', const PdfColor.fromInt(0xFF004D40)),
                  _buildKpiCard('Total Deductions', 'PKR ${_fmtCurrency(totalDeductions)}', totalDeductions > 0 ? PdfColors.red800 : PdfColors.grey700),
                  _buildKpiCard('Total Bonuses / OT', 'PKR ${_fmtCurrency(totalBonuses)}', totalBonuses > 0 ? PdfColors.green800 : PdfColors.grey700),
                  _buildKpiCard('Net Disbursement Payable', 'PKR ${_fmtCurrency(totalNet)}', const PdfColor.fromInt(0xFF00695C), isHighlight: true),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // 3. Clear, Institutional Payroll Table
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder(
                horizontalInside: const pw.BorderSide(color: PdfColor.fromInt(0xFFCFD8DC), width: 0.5),
                verticalInside: const pw.BorderSide(color: PdfColor.fromInt(0xFFCFD8DC), width: 0.5),
                top: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
                bottom: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
                left: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
                right: const pw.BorderSide(color: PdfColor.fromInt(0xFF004D40), width: 1.2),
              ),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF004D40)),
              headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7FAFA)),
              cellDecoration: (int colIndex, dynamic cellData, int rowIndex) {
                if (rowIndex == tableData.length - 1) {
                  return const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0F2F1));
                }
                return const pw.BoxDecoration();
              },
              headers: [
                'Sr.',
                'Employee Details',
                'Designation & Dept',
                'Attendance Summary',
                'Base Salary\n(PKR)',
                'Deductions\n(PKR)',
                'Bonuses\n(PKR)',
                'Net Payable\n(PKR)',
              ],
              data: tableData,
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
              },
              headerAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FlexColumnWidth(2.0),
                3: const pw.FlexColumnWidth(1.9),
                4: const pw.FlexColumnWidth(1.3),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(1.1),
                7: const pw.FlexColumnWidth(1.6),
              },
            ),

            pw.SizedBox(height: 14),
            // 4. Official Sign-off and Authorization Signatures
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFCFD8DC), width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildSignatureLine('Prepared By', 'Accountant / Data Operator'),
                  _buildSignatureLine('Verified By', 'Admin / HR Manager'),
                  _buildSignatureLine('Approved By', 'Finance Secretary / President'),
                ],
              ),
            ),
          ],
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Gulzar Madina Welfare Foundation • Confidential Official Payroll Record',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      final pdfBytes = await pdf.save();
      final dateStr = DateFormat('yyyy-MM').format(DateTime.now());
      final deptStr = department != null && department != 'All' && department != 'All Departments' ? '_${department.toLowerCase().replaceAll(' ', '_')}' : '';
      final campStr = camp != null && camp != 'All' && camp != 'All Camps' ? '_${camp.toLowerCase().replaceAll(' ', '_')}' : '';
      final fileName = 'payroll_${branchId}_$monthKey$deptStr${campStr}_$dateStr.pdf';

      String? path;
      try {
        path = await pickSavePathFast(
          dialogTitle: 'Save Monthly PDF Report',
          fileName: fileName,
          bytes: pdfBytes,
          allowedExtensions: ['pdf'],
        );
      } catch (_) {}

      final result = {'path': path, 'bytes': pdfBytes, 'name': fileName};
      if (context != null && context.mounted) {
        FileActionHelper.showFileOptions(
          context,
          filePath: path,
          bytes: pdfBytes,
          fileName: fileName,
          title: 'Monthly PDF Report Ready',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[FinanceReportHelper] exportMonthlyPdf error: $e');
      return null;
    }
  }

  static int min(int a, int b) => a < b ? a : b;

  // ── 5. Excel Monthly Expenses Log ──────────────────────────────────────────
  static Future<Map<String, dynamic>?> exportExpensesExcel({
    required String branchId,
    required String monthKey, // format: 'yyyy-MM'
    BuildContext? context,
  }) async {
    try {
      // Parse month range
      final monthStart = DateFormat('yyyy-MM').parse(monthKey);
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1)
          .subtract(const Duration(seconds: 1));

      // Fetch all expenses for range from local box
      final allExpenses = FinanceExpensesStorage.getExpensesForRange(
        branchId,
        monthStart,
        monthEnd,
      );

      // Group by dateKey
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final exp in allExpenses) {
        final key = exp['dateKey']?.toString() ?? DateFormat('yyyy-MM-dd').format(monthStart);
        grouped.putIfAbsent(key, () => []).add(exp);
      }

      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Expense Log');
      final sheet = excel['Expense Log'];

      // Header block
      sheet.appendRow([xl.TextCellValue('GULZAR MADINA WELFARE FOUNDATION')]);
      sheet.appendRow([xl.TextCellValue('DAILY EXPENSES LOG')]);
      sheet.appendRow([
        xl.TextCellValue('Branch: ${branchId == "all" ? "All Branches" : branchId.toUpperCase()}'),
        xl.TextCellValue('Period: $monthKey'),
        xl.TextCellValue('Exported: ${DateFormat("yyyy-MM-dd HH:mm").format(DateTime.now())}'),
      ]);
      sheet.appendRow([]); // spacer

      // Table headers
      final headers = [
        'Date',
        'Category',
        'Description',
        'Amount (PKR)',
        'Logged By',
        'Branch',
        'Status',
        'Void Reason',
      ];
      sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

      final headerStyle = xl.CellStyle(
        bold: true,
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
      );
      const headerRowIndex = 4;
      for (int c = 0; c < headers.length; c++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRowIndex)).cellStyle = headerStyle;
      }

      // Column widths
      sheet.setColumnWidth(0, 14); // Date
      sheet.setColumnWidth(1, 18); // Category
      sheet.setColumnWidth(2, 36); // Description
      sheet.setColumnWidth(3, 16); // Amount
      sheet.setColumnWidth(4, 22); // Logged By
      sheet.setColumnWidth(5, 14); // Branch
      sheet.setColumnWidth(6, 10); // Status
      sheet.setColumnWidth(7, 32); // Void Reason

      // Data rows grouped by date
      final sortedDates = grouped.keys.toList()..sort();
      double grandTotal = 0.0;

      for (final dateKey in sortedDates) {
        final dayExpenses = grouped[dateKey]!;
        double dayTotal = 0.0;

        // Day sub-header
        final dayLabel = DateFormat('EEEE, d MMM yyyy')
            .format(DateTime.parse(dateKey));
        sheet.appendRow([xl.TextCellValue('── $dayLabel ──')]);

        for (final exp in dayExpenses) {
          final isVoided = exp['isVoided'] == true;
          final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
          var cat = exp['category']?.toString() ?? 'Other';
          if (cat == 'Other' && (exp['customCategory']?.toString().isNotEmpty ?? false)) {
            cat = exp['customCategory'].toString();
          }

          if (!isVoided) {
            dayTotal += amt;
            grandTotal += amt;
          }

          sheet.appendRow([
            xl.TextCellValue(exp['dateKey']?.toString() ?? dateKey),
            xl.TextCellValue(cat),
            xl.TextCellValue(exp['description']?.toString() ?? ''),
            xl.DoubleCellValue(amt),
            xl.TextCellValue(exp['performedByName']?.toString() ?? 'N/A'),
            xl.TextCellValue(exp['branchId']?.toString().toUpperCase() ?? 'N/A'),
            xl.TextCellValue(isVoided ? 'VOIDED' : 'Active'),
            xl.TextCellValue(isVoided ? (exp['voidReason']?.toString() ?? '') : ''),
          ]);
        }

        // Day totals sub-footer
        sheet.appendRow([
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue('Day Total'),
          xl.DoubleCellValue(dayTotal),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
        ]);
        sheet.appendRow([]); // spacer between days
      }

      // Grand Total footer row
      sheet.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue(''),
        xl.TextCellValue('GRAND TOTAL'),
        xl.DoubleCellValue(grandTotal),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
      ]);

      // Category Summary sheet
      excel['Category Summary'];
      final summarySheet = excel['Category Summary'];
      summarySheet.appendRow([xl.TextCellValue('CATEGORY SUMMARY — $monthKey')]);
      summarySheet.appendRow([xl.TextCellValue('Branch: ${branchId == "all" ? "All Branches" : branchId.toUpperCase()}')]);
      summarySheet.appendRow([]);

      final catSummaryHeaders = ['Category', 'Total Spent (PKR)', 'No. of Entries'];
      summarySheet.appendRow(catSummaryHeaders.map((h) => xl.TextCellValue(h)).toList());
      for (int c = 0; c < catSummaryHeaders.length; c++) {
        summarySheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 3))
            .cellStyle = headerStyle;
      }
      summarySheet.setColumnWidth(0, 22);
      summarySheet.setColumnWidth(1, 20);
      summarySheet.setColumnWidth(2, 16);

      // Build category totals
      final catTotals = <String, double>{};
      final catCounts = <String, int>{};
      for (final exp in allExpenses) {
        if (exp['isVoided'] == true) continue;
        var cat = exp['category']?.toString() ?? 'Other';
        if (cat == 'Other' && (exp['customCategory']?.toString().isNotEmpty ?? false)) {
          cat = exp['customCategory'].toString();
        }
        catTotals[cat] = (catTotals[cat] ?? 0.0) + ((exp['amount'] as num?)?.toDouble() ?? 0.0);
        catCounts[cat] = (catCounts[cat] ?? 0) + 1;
      }

      final sortedCats = catTotals.keys.toList()
        ..sort((a, b) => catTotals[b]!.compareTo(catTotals[a]!));

      for (final cat in sortedCats) {
        summarySheet.appendRow([
          xl.TextCellValue(cat),
          xl.DoubleCellValue(catTotals[cat]!),
          xl.IntCellValue(catCounts[cat] ?? 0),
        ]);
      }

      // Grand total row in category summary
      summarySheet.appendRow([
        xl.TextCellValue('TOTAL'),
        xl.DoubleCellValue(grandTotal),
        xl.IntCellValue(allExpenses.where((e) => e['isVoided'] != true).length),
      ]);

      final excelBytes = excel.encode() != null
          ? Uint8List.fromList(excel.encode()!)
          : Uint8List(0);
      final branchStr = branchId == 'all' ? 'all_branches' : branchId;
      final fileName = 'expenses_${branchStr}_$monthKey.xlsx';

      String? path;
      try {
        path = await pickSavePathFast(
          dialogTitle: 'Save Expenses Report',
          fileName: fileName,
          bytes: excelBytes,
          allowedExtensions: ['xlsx'],
        );
      } catch (_) {}

      final result = {'path': path, 'bytes': excelBytes, 'name': fileName};
      if (context != null && context.mounted) {
        FileActionHelper.showFileOptions(
          context,
          filePath: path,
          bytes: excelBytes,
          fileName: fileName,
          title: 'Expenses Excel Report Ready',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[FinanceReportHelper] exportExpensesExcel error: $e');
      return null;
    }
  }

  // ── 6. Bank Reconciliation Audit PDF ──────────────────────────────────────
  static Future<Map<String, dynamic>?> exportReconciliationPdf({
    required String branchId,
    required String monthKey,
    required List<Map<String, dynamic>> items,
    BuildContext? context,
  }) async {
    try {
      // Load official GMWF Logo
      final logoImage = await _loadGmwfLogo();

      final pdf = pw.Document();

      final reconciledCount = items.where((i) => i['isReconciled'] == true).length;
      final totalCount = items.length;
      final pendingCount = totalCount - reconciledCount;

      int totalReconciledPaisa = 0;
      int totalPendingPaisa = 0;

      for (final item in items) {
        final amt = (item['amountMinor'] as num?)?.toInt() ?? 0;
        if (item['isReconciled'] == true) {
          totalReconciledPaisa += amt;
        } else {
          totalPendingPaisa += amt;
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pwContext) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null) ...[
                      pw.Container(
                        width: 44,
                        height: 44,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: const PdfColor.fromInt(0xFF00695C), width: 1.2),
                        ),
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.ClipOval(
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('GULZAR MADINA WELFARE FOUNDATION',
                            style: pw.TextStyle(
                                fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF004D40))),
                        pw.Text('BANK & CASH RECONCILIATION AUDIT REPORT',
                            style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF00796B))),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Branch: ${branchId.toUpperCase()}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF004D40))),
                    pw.Text('Period: $monthKey', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                    pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF00695C)),
            pw.SizedBox(height: 10),

            // Summary Grid
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Transactions: $totalCount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Reconciled: $reconciledCount (PKR ${NumberFormat('#,###').format(totalReconciledPaisa / 100)})', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green700, fontSize: 9))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Pending: $pendingCount (PKR ${NumberFormat('#,###').format(totalPendingPaisa / 100)})', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red700, fontSize: 9))),
                ]),
              ],
            ),
            pw.SizedBox(height: 14),

            pw.Text('LEDGER TRANSACTIONS AUDIT TRAIL',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),

            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              headers: ['Type / Source', 'Date', 'Description', 'Amount (PKR)', 'Reconciliation Status'],
              data: items.map((i) {
                final isRec = i['isReconciled'] == true;
                final amt = (i['amountMinor'] as num?)?.toInt() ?? 0;
                return [
                  i['type']?.toString() ?? 'N/A',
                  i['date']?.toString() ?? 'N/A',
                  i['description']?.toString() ?? 'N/A',
                  'PKR ${NumberFormat('#,###').format(amt / 100)}',
                  isRec ? 'RECONCILED ✓' : 'PENDING ❌',
                ];
              }).toList(),
            ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      final fileName = 'reconciliation_${branchId}_$monthKey.pdf';

      String? path;
      try {
        path = await pickSavePathFast(
          dialogTitle: 'Save Bank Reconciliation Report',
          fileName: fileName,
          bytes: pdfBytes,
          allowedExtensions: ['pdf'],
        );
      } catch (_) {}

      final result = {'path': path, 'bytes': pdfBytes, 'name': fileName};
      if (context != null && context.mounted) {
        FileActionHelper.showFileOptions(
          context,
          filePath: path,
          bytes: pdfBytes,
          fileName: fileName,
          title: 'Reconciliation PDF Ready',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[FinanceReportHelper] exportReconciliationPdf error: $e');
      return null;
    }
  }
}
