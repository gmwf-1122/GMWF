import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:excel/excel.dart' as exc;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/madrassa_config.dart';
import '../models/madrassa_fee_logic.dart';
import '../../../constants/navigator_key.dart';

class MadrassaReportHelper {
  static Future<void> exportMonthlyPdf({
    required MadrassaConfig config,
    required List<QueryDocumentSnapshot> students,
    required List<QueryDocumentSnapshot> logs,
  }) async {
    final pdf = pw.Document();
    final monthName = DateFormat('MMMM yyyy').format(DateTime(config.year, config.month));
    final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);
    
    final logoData = await rootBundle.load('assets/logo/gmwf.png');
    final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Gulzar Madina Madrassa', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF008080))),
                    pw.Text('Madrassa Monthly Report - $monthName', style: pw.TextStyle(fontSize: 14)),
                  ],
                ),
                pw.Image(logoImage, height: 40),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.SizedBox(height: 16),
          ],
        ),
        build: (pw.Context context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: ['#', 'Student', 'Roll', 'Days', 'P', 'L', 'A', 'Att. Rs', 'Uni. Rs', 'Msg', 'PTM', 'Total Rs', 'Due'],
              data: List.generate(students.length, (i) {
                final s = students[i];
                final fee = MadrassaFeeLogic.calculateStudentFee(
                  studentId: s.id,
                  studentData: s.data() as Map<String, dynamic>,
                  logs: logs,
                  config: config,
                  totalWorkingDays: workingDays,
                );
                return [
                  '${i + 1}',
                  s['name'] ?? '',
                  s['rollNumber'] ?? '',
                  '${fee['activeWorkingDays']}',
                  '${fee['present']}',
                  '${fee['leave']}',
                  '${fee['absent']}',
                  '${(fee['attSavings'] as num).toStringAsFixed(0)}',
                  '${(fee['uniSavings'] as num).toStringAsFixed(0)}',
                  fee['message'] > 0 ? 'Yes' : 'No',
                  fee['ptm'] ? 'Joined' : 'Missed',
                  '${(fee['totalSavings'] as num).toStringAsFixed(0)}',
                  '${(fee['amountDue'] as num).toStringAsFixed(0)}',
                ];
              }),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.center,
              columnWidths: {
                0: const pw.FixedColumnWidth(20),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(40),
              },
            ),
          ];
        },
        footer: (pw.Context context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveAndNotify('Madrassa_Monthly_Report_${monthName.replaceAll(' ', '_')}.pdf', bytes);
  }

  static Future<void> exportMonthlyExcel({
    required MadrassaConfig config,
    required List<QueryDocumentSnapshot> students,
    required List<QueryDocumentSnapshot> logs,
  }) async {
    final excel = Excel.createExcel();
    final String sheetName = 'Monthly Report';
    excel.rename('Sheet1', sheetName);
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    
    final monthName = DateFormat('MMMM yyyy').format(DateTime(config.year, config.month));
    final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);

    // Styling
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#008080'), // Teal
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: exc.Border(borderStyle: exc.BorderStyle.Thin),
      bottomBorder: exc.Border(borderStyle: exc.BorderStyle.Thin),
      leftBorder: exc.Border(borderStyle: exc.BorderStyle.Thin),
      rightBorder: exc.Border(borderStyle: exc.BorderStyle.Thin),
    );

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: ExcelColor.fromHexString('#004D40'), // Deep Teal
    );

    // Set Column Widths
    sheet.setColumnWidth(0, 5); // #
    sheet.setColumnWidth(1, 25); // Student Name
    sheet.setColumnWidth(2, 15); // Roll
    for (int c = 3; c <= 12; c++) {
      sheet.setColumnWidth(c, 12);
    }

    // Headers & Branding
    try {
      final ByteData data = await rootBundle.load('assets/logo/gmwf.png');
      final Uint8List imageBytes = data.buffer.asUint8List();
      (excel as dynamic).insertImage(sheetName, imageBytes, 0, 0);
    } catch (e) {
      debugPrint("Excel Logo Error: $e");
    }

    // Main Title with Merged Cells
    var titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    titleCell.value = TextCellValue('Gulzar Madina Welfare Foundation');
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Left,
      fontColorHex: ExcelColor.fromHexString('#008080'), // Teal
      backgroundColorHex: ExcelColor.fromHexString('#E0F2F1'), // Light Teal
    );
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1));
    
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('Monthly Academic Report — $monthName');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).cellStyle = CellStyle(italic: true, horizontalAlign: HorizontalAlign.Left);
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2), CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 2));

    const int headerRow = 4;
    final headers = ['#', 'Student Name', 'Roll Number', 'Total Days', 'Present', 'Leave', 'Absent', 'Att. Savings', 'Uni. Savings', 'Msg Replied', 'PTM Joined', 'Total Savings', 'Amount Due'];
    
    for (int i = 0; i < headers.length; i++) {
      var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: headerRow));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    double totalAmountDue = 0;
    int totalStudents = students.length;

    for (var i = 0; i < students.length; i++) {
      final s = students[i];
      final fee = MadrassaFeeLogic.calculateStudentFee(
        studentId: s.id,
        studentData: s.data() as Map<String, dynamic>,
        logs: logs,
        config: config,
        totalWorkingDays: workingDays,
      );
      final amountDue = (fee['amountDue'] as num).toDouble();
      totalAmountDue += amountDue;

      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(s['name'] ?? ''),
        TextCellValue(s['rollNumber'] ?? ''),
        IntCellValue(fee['activeWorkingDays']),
        IntCellValue(fee['present']),
        IntCellValue(fee['leave']),
        IntCellValue(fee['absent']),
        DoubleCellValue((fee['attSavings'] as num).toDouble().roundToDouble()),
        DoubleCellValue((fee['uniSavings'] as num).toDouble().roundToDouble()),
        TextCellValue(fee['message'] > 0 ? 'Yes' : 'No'),
        TextCellValue(fee['ptm'] ? 'Joined' : 'Missed'),
        DoubleCellValue((fee['totalSavings'] as num).toDouble().roundToDouble()),
        DoubleCellValue(amountDue.roundToDouble()),
      ]);
    }

    // Add totals row
    sheet.appendRow([]);
    final totalRow = sheet.maxRows;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: totalRow)).value = TextCellValue('GRAND TOTAL:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: totalRow)).cellStyle = CellStyle(bold: true);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: totalRow)).value = DoubleCellValue(totalAmountDue.roundToDouble());
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: totalRow)).cellStyle = CellStyle(bold: true, fontColorHex: ExcelColor.fromHexString('#D32F2F'));

    final fileBytes = excel.save();
    if (fileBytes != null) {
      await _saveAndNotify('Madrassa_Monthly_Report_${monthName.replaceAll(' ', '_')}.xlsx', Uint8List.fromList(fileBytes));
    }
  }

  static Future<void> exportIndividualPdf({
    required MadrassaConfig config,
    required String studentId,
    required Map<String, dynamic> studentData,
    required List<QueryDocumentSnapshot> logs,
  }) async {
    final pdf = pw.Document();
    final monthName = DateFormat('MMMM yyyy').format(DateTime(config.year, config.month));
    final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);
    final fee = MadrassaFeeLogic.calculateStudentFee(
      studentId: studentId,
      studentData: studentData,
      logs: logs,
      config: config,
      totalWorkingDays: workingDays,
    );
    
    final logoData = await rootBundle.load('assets/logo/gmwf.png');
    final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Gulzar Madina Madrassa', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF008080))),
                      pw.Text('Student Report Card - $monthName', style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Image(logoImage, height: 60),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(height: 3, width: double.infinity, decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF00A86B))),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0F2F1), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(
                  children: [
                    _row('Student Name', studentData['name'] ?? ''),
                    _row('Roll Number', studentData['rollNumber'] ?? ''),
                    _row('Active Days', '${fee['activeWorkingDays']}'),
                    _row('Present', '${fee['present']}'),
                    _row('Absent', '${fee['absent']}'),
                    _row('Leave', '${fee['leave']}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text('FINANCIAL SUMMARY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF008080))),
              pw.Divider(color: PdfColor.fromInt(0xFF008080)),
              _row('Base Fee', 'Rs. ${config.baseFee.toStringAsFixed(0)}'),
              _row('Attendance Savings', '- Rs. ${fee['attSavings'].toStringAsFixed(0)}'),
              _row('Uniform Savings', '- Rs. ${fee['uniSavings'].toStringAsFixed(0)}'),
              _row('Message Savings', '- Rs. ${fee['msgSavings'].toStringAsFixed(0)}'),
              _row('PTM Savings', '- Rs. ${fee['ptmSavings'].toStringAsFixed(0)}'),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0F2F1), borderRadius: pw.BorderRadius.circular(8)),
                child: _row('TOTAL AMOUNT DUE', 'Rs. ${fee['amountDue'].toStringAsFixed(0)}', isBold: true),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _saveAndNotify('Report_${studentData['name']}_$monthName.pdf', bytes);
  }

  static Future<void> exportIndividualExcel({
    required MadrassaConfig config,
    required String studentId,
    required Map<String, dynamic> studentData,
    required List<QueryDocumentSnapshot> logs,
  }) async {
    final excel = Excel.createExcel();
    final String sheetName = 'Report Card';
    excel.rename('Sheet1', sheetName);
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    
    final monthName = DateFormat('MMMM yyyy').format(DateTime(config.year, config.month));
    final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);
    final fee = MadrassaFeeLogic.calculateStudentFee(
      studentId: studentId,
      studentData: studentData,
      logs: logs,
      config: config,
      totalWorkingDays: workingDays,
    );

    // Styling
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#008080'), // Teal
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    final labelStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E0F2F1')); // Light Teal
    final totalStyle = CellStyle(bold: true, fontColorHex: ExcelColor.fromHexString('#D32F2F'), fontSize: 12);

    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 30);

    // Header Branding
    try {
      final ByteData data = await rootBundle.load('assets/logo/gmwf.png');
      final Uint8List imageBytes = data.buffer.asUint8List();
      (excel as dynamic).insertImage(sheetName, imageBytes, 0, 0);
    } catch (e) {
      debugPrint("Excel Logo Error: $e");
    }

    // Title Section
    var titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    titleCell.value = TextCellValue('Gulzar Madina Welfare Foundation');
    titleCell.cellStyle = CellStyle(bold: true, fontSize: 16, fontColorHex: ExcelColor.fromHexString('#008080')); // Teal
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1));

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('Student Report Card - $monthName');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).cellStyle = CellStyle(italic: true, fontColorHex: ExcelColor.fromHexString('#004D40'));
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2), CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 2));
    
    // Info Section
    int r = 5;
    void addInfo(String label, String value) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(label);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).cellStyle = labelStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(value);
      r++;
    }

    addInfo('Student Name', studentData['name'] ?? '');
    addInfo('Roll Number', studentData['rollNumber'] ?? '');
    addInfo('Class', studentData['class'] ?? 'Hifz');
    
    r++; // Spacer
    
    // Stats Header
    var statsHeader = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r));
    statsHeader.value = TextCellValue('ACADEMIC PROGRESS');
    statsHeader.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
    r++;

    void addStat(String label, dynamic val) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(label);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = val is int ? IntCellValue(val) : TextCellValue(val.toString());
      r++;
    }

    addStat('Present Days', fee['present']);
    addStat('Absent Days', fee['absent']);
    addStat('Leave Days', fee['leave']);
    
    r++; // Spacer

    // Financial Header
    var finHeader = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r));
    finHeader.value = TextCellValue('FINANCIAL SUMMARY');
    finHeader.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
    r++;

    void addFin(String label, double val, {bool isTotal = false}) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(label);
      if (isTotal) sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).cellStyle = labelStyle;
      
      var valCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
      valCell.value = DoubleCellValue(val.roundToDouble());
      if (isTotal) valCell.cellStyle = totalStyle;
      r++;
    }

    addFin('Base Fee', config.baseFee.toDouble());
    addFin('Attendance Savings', (fee['attSavings'] as num).toDouble());
    addFin('Uniform Savings', (fee['uniSavings'] as num).toDouble());
    addFin('Message Savings', (fee['msgSavings'] as num).toDouble());
    addFin('PTM Savings', (fee['ptmSavings'] as num).toDouble());
    r++;
    addFin('TOTAL AMOUNT DUE', (fee['amountDue'] as num).toDouble(), isTotal: true);

    final fileBytes = excel.save();
    if (fileBytes != null) {
      await _saveAndNotify('Report_${studentData['name']}_$monthName.xlsx', Uint8List.fromList(fileBytes));
    }
  }

  static Future<void> _saveAndNotify(String fileName, Uint8List bytes) async {
    try {
      Directory? dir = await getDownloadsDirectory();
      if (dir == null && Platform.isWindows) {
        dir = Directory(p.join(Platform.environment['USERPROFILE']!, 'Downloads'));
      }
      
      if (dir != null) {
        final filePath = p.join(dir.path, fileName);
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        // Show dialog with copiable path
        final context = navigatorKey.currentContext;
        if (context != null) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Report Saved ✓'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The report has been saved to your Downloads folder:'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: SelectableText(filePath, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: filePath));
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Path copied to clipboard!')));
                  },
                  child: const Text('COPY PATH'),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
              ],
            ),
          );
        }
      } else {
        // Fallback to share
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      // Fallback
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  static pw.Widget _row(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : null)),
          pw.Text(value, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : null)),
        ],
      ),
    );
  }
}
