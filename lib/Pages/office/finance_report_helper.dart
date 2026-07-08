// lib/pages/office/finance_report_helper.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../services/finance_local_storage.dart';
import '../../services/local_storage_service.dart';

class FinanceReportHelper {
  // Helper to format currency
  static String _fmtCurrency(double amt) {
    return NumberFormat('#,###').format(amt);
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
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GULAB DEVI MEMORIAL WELFARE FOUNDATION',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('EMPLOYEE DOSSIER & RECORD SHEET',
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generated: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
                    pw.Text('Status: ${emp['status']?.toString().toUpperCase() ?? 'ACTIVE'}',
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: emp['isActive'] == true ? PdfColors.green : PdfColors.red)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
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

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Employee PDF Profile',
        fileName: 'dossier_${safeName}_$dateStr.pdf',
        bytes: pdfBytes,
        type: FileType.custom,
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

  // ── 2. Excel Monthly Payroll & Attendance Sheet (Branch / Department) ──────
  static Future<void> exportMonthlyExcel({
    required String branchId,
    required String monthKey,
    String? department,
  }) async {
    try {
      final employees = FinanceLocalStorage.getEmployees(branchId).where((emp) {
        if (department != null && emp['department'] != department) return false;
        return true;
      }).toList();

      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Payroll Sheet');

      final sheet = excel['Payroll Sheet'];

      // Header info
      sheet.appendRow([xl.TextCellValue('GULAB DEVI MEMORIAL WELFARE FOUNDATION')]);
      sheet.appendRow([xl.TextCellValue('Payroll & Attendance Monthly Sheet')]);
      sheet.appendRow([
        xl.TextCellValue('Branch: ${branchId.toUpperCase()}'),
        xl.TextCellValue('Month: $monthKey'),
        xl.TextCellValue(department != null ? 'Department: $department' : 'Department: All Departments'),
      ]);
      sheet.appendRow([]); // empty spacing

      // Table Headers
      final headers = [
        'ID',
        'Employee Name',
        'CNIC',
        'Role',
        'Department',
        'Joining Date',
        'Status',
        'Base Salary',
        'Present Days',
        'Absent Days',
        'Paid Leaves',
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
        5: 15,  // Joining Date
        6: 12,  // Status
        7: 15,  // Base Salary
        8: 12,  // Present Days
        9: 12,  // Absent Days
        10: 12, // Paid Leaves
        11: 12, // Unpaid Leaves
        12: 14, // Unmarked Days
        13: 16, // Earned Base Pay
        14: 16, // Absence Deductions
        15: 16, // Advance Recovered
        16: 16, // Holiday Bonus
        17: 18, // Sunday Overtime Bonus
        18: 18, // Net Payable Salary
        19: 16, // Payment Method
        20: 20, // Bank Name
        21: 24, // Account / IBAN
      };
      colWidths.forEach((colIndex, width) {
        sheet.setColumnWidth(colIndex, width);
      });

      // Row Data
      for (final emp in employees) {
        final empId = emp['localId']?.toString() ?? '';
        final name = emp['name']?.toString() ?? 'N/A';
        final cnic = emp['cnic']?.toString() ?? 'N/A';
        final role = emp['role']?.toString() ?? 'N/A';
        final dept = emp['department']?.toString() ?? 'N/A';
        final joining = emp['joiningDate']?.toString() ?? 'N/A';
        final activeStatus = emp['status']?.toString() ?? 'Active';

        final summary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, monthKey);
        final baseSalary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;

        double advanceRecovered = 0.0;
        final monthPayments = FinanceLocalStorage.salaryLedgerBox.values.where((val) {
          if (val is! Map) return false;
          final entry = Map<String, dynamic>.from(val);
          return entry['employeeId'] == empId &&
              entry['monthKey'] == monthKey &&
              entry['type'] == 'payout' &&
              entry['isVoided'] != true;
        }).toList();

        if (monthPayments.isNotEmpty) {
          advanceRecovered = (monthPayments.first['advanceDeductions'] as num?)?.toDouble() ?? 0.0;
        }

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
          xl.TextCellValue(joining),
          xl.TextCellValue(activeStatus),
          xl.DoubleCellValue(baseSalary),
          xl.DoubleCellValue((summary['workingDays'] as num?)?.toDouble() ?? 0.0),
          xl.DoubleCellValue((summary['absentDays'] as num?)?.toDouble() ?? 0.0),
          xl.DoubleCellValue((summary['paidLeaves'] as num?)?.toDouble() ?? 0.0),
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
      final fileName = 'payroll_${branchId}_${monthKey}${deptStr}_$dateStr.xlsx';

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel Report',
        fileName: fileName,
        bytes: excelBytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
    } catch (_) {}
  }

  // ── 3. Excel Consolidated Report: All Branches categorized branch-wise ──────
  static Future<void> exportConsolidatedAllBranchesExcel({
    required List<Map<String, dynamic>> branches,
    required String monthKey,
  }) async {
    try {
      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Summary Overview');

      final summarySheet = excel['Summary Overview'];
      summarySheet.appendRow([xl.TextCellValue('GULAB DEVI MEMORIAL WELFARE FOUNDATION')]);
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

        final list = FinanceLocalStorage.getEmployees(bId);
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
          5: 12,  // Status
          6: 15,  // Joining Date
          7: 20,  // Current Salary Rate
          8: 20,  // Advance Balance
        };
        brColWidths.forEach((colIndex, width) {
          brSheet.setColumnWidth(colIndex, width);
        });

        for (final emp in list) {
          brSheet.appendRow([
            xl.TextCellValue(emp['localId']?.toString().substring(0, 8) ?? 'N/A'),
            xl.TextCellValue(emp['name']?.toString() ?? 'N/A'),
            xl.TextCellValue(emp['cnic']?.toString() ?? 'N/A'),
            xl.TextCellValue(emp['role']?.toString() ?? 'N/A'),
            xl.TextCellValue(emp['department']?.toString() ?? 'N/A'),
            xl.TextCellValue(emp['status']?.toString() ?? 'Active'),
            xl.TextCellValue(emp['joiningDate']?.toString() ?? 'N/A'),
            xl.DoubleCellValue((emp['currentSalary'] as num?)?.toDouble() ?? 0.0),
            xl.DoubleCellValue((emp['currentAdvanceBalance'] as num?)?.toDouble() ?? 0.0),
          ]);
        }
      }

      final excelBytes = excel.encode() != null ? Uint8List.fromList(excel.encode()!) : Uint8List(0);
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Consolidated Report',
        fileName: 'consolidated_payroll_${monthKey}_$dateStr.xlsx',
        bytes: excelBytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
    } catch (_) {}
  }

  // ── 4. PDF Monthly Payroll & Attendance Sheet (Branch / Department) ────────
  static Future<void> exportMonthlyPdf({
    required String branchId,
    required String monthKey,
    String? department,
  }) async {
    try {
      final employees = FinanceLocalStorage.getEmployees(branchId).where((emp) {
        if (department != null && emp['department'] != department) return false;
        return true;
      }).toList();

      final pdf = pw.Document();

      final List<List<String>> tableData = [];
      double totalBase = 0.0;
      double totalDeductions = 0.0;
      double totalBonuses = 0.0;
      double totalNet = 0.0;

      for (final emp in employees) {
        final empId = emp['localId']?.toString() ?? '';
        final name = emp['name']?.toString() ?? 'N/A';
        final role = emp['role']?.toString() ?? 'N/A';
        final dept = emp['department']?.toString() ?? 'N/A';

        final summary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, monthKey);
        final baseSalary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;

        double advanceRecovered = 0.0;
        final monthPayments = FinanceLocalStorage.salaryLedgerBox.values.where((val) {
          if (val is! Map) return false;
          final entry = Map<String, dynamic>.from(val);
          return entry['employeeId'] == empId &&
              entry['monthKey'] == monthKey &&
              entry['type'] == 'payout' &&
              entry['isVoided'] != true;
        }).toList();

        if (monthPayments.isNotEmpty) {
          advanceRecovered = (monthPayments.first['advanceDeductions'] as num?)?.toDouble() ?? 0.0;
        }

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

        tableData.add([
          name,
          '$role\n($dept)',
          'PKR ${_fmtCurrency(baseSalary)}',
          'P: ${(summary['workingDays'] as num?)?.toDouble() ?? 0.0}\nA: ${(summary['absentDays'] as num?)?.toDouble() ?? 0.0}\nL: ${(summary['paidLeaves'] as num?)?.toDouble() ?? 0.0}',
          'PKR ${_fmtCurrency(deductions)}',
          'PKR ${_fmtCurrency(bonuses)}',
          'PKR ${_fmtCurrency(netPayable)}',
        ]);
      }

      // Add Grand Totals Row
      tableData.add([
        'GRAND TOTALS',
        '${employees.length} Employees',
        'PKR ${_fmtCurrency(totalBase)}',
        '',
        'PKR ${_fmtCurrency(totalDeductions)}',
        'PKR ${_fmtCurrency(totalBonuses)}',
        'PKR ${_fmtCurrency(totalNet)}',
      ]);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GULAB DEVI MEMORIAL WELFARE FOUNDATION',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text('MONTHLY PAYROLL & ATTENDANCE REPORT',
                        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Branch: ${branchId.toUpperCase()}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Month Key: $monthKey',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    if (department != null)
                      pw.Text('Department: $department',
                          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 10),

            // Table
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              headers: [
                'Employee Name',
                'Designation',
                'Base Salary',
                'Attendance (P/A/L)',
                'Total Deductions',
                'Total Bonuses',
                'Net Payable'
              ],
              data: tableData,
              columnWidths: {
                0: const pw.FlexColumnWidth(2.0),
                1: const pw.FlexColumnWidth(2.0),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.2),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(1.5),
              },
            ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      final dateStr = DateFormat('yyyy-MM').format(DateTime.now());
      final deptStr = department != null ? '_${department.toLowerCase()}' : '';
      final fileName = 'payroll_${branchId}_${monthKey}${deptStr}_$dateStr.pdf';

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Monthly PDF Report',
        fileName: fileName,
        bytes: pdfBytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (_) {}
  }

  static int min(int a, int b) => a < b ? a : b;
}
