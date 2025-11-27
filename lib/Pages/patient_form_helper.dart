// lib/pages/patient_form_helper.dart
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PatientFormHelper {
  // ====================== COLORS ======================
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color primaryRed = Color(0xFFFF0000);
  static const Color textBlack = Colors.black87;

  // ====================== TEXT STYLES (Flutter UI) ======================
  static TextStyle robotoRegular({double size = 16, Color color = textBlack}) =>
      TextStyle(fontFamily: 'Roboto', fontSize: size, color: color);

  static TextStyle robotoBold({double size = 16, Color color = textBlack}) =>
      TextStyle(
          fontFamily: 'Roboto',
          fontSize: size,
          color: color,
          fontWeight: FontWeight.bold);

  static TextStyle nooriRegular({double size = 16, Color color = textBlack}) =>
      TextStyle(fontFamily: 'Noori', fontSize: size, color: color);

  // ====================== TIMING & MEDICINE HELPERS ======================
  static List<int> parseTiming(String timing) {
    if (timing.isEmpty) return [0, 0, 0];
    return timing.split('+').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  }

  static String formatTimingDisplay(String timing) =>
      parseTiming(timing).map((n) => n.toString()).join('+');

  static int totalPerDay(String timing) =>
      parseTiming(timing).reduce((a, b) => a + b);

  static String timingToUrdu(String timing) {
    final parts = parseTiming(timing);
    if (parts.every((p) => p == 0)) return '';
    final urdu = <String>[];
    if (parts[0] > 0) urdu.add('${parts[0]} گولی صبح');
    if (parts[1] > 0) urdu.add('${parts[1]} گولی دوپہر');
    if (parts[2] > 0) urdu.add('${parts[2]} گولی شام');
    return urdu.isNotEmpty ? urdu.join(' - ') : '';
  }

  static String getMealText(String meal) => meal == 'BF'
      ? 'Before Food'
      : meal == 'AF'
          ? 'After Food'
          : meal;

  static String getMealUrdu(String meal) => meal == 'BF'
      ? 'کھانے سے پہلے'
      : meal == 'AF'
          ? 'کھانے کے بعد'
          : '';

  static String getSleepText() => 'Before Sleep';
  static String getSleepUrdu() => 'سونے سے پہلے';

  static String formatPhoneForWhatsApp(String phone) {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length < 10) return clean;
    if (clean.startsWith('0')) return '92${clean.substring(1)}';
    if (clean.startsWith('92') && clean.length == 12) return clean;
    return clean;
  }

  static bool isInjectable(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString().toLowerCase().trim();
    final injectable = m['injectable'] as bool? ?? false;
    return injectable ||
        type.contains('inject') ||
        type == 'drip' ||
        type == 'syringe' ||
        type == 'big bottle';
  }

  // ====================== ASSET LOADER ======================
  static Future<Uint8List> loadAssetBytes(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (e) {
      debugPrint('Asset not found: $path');
      return Uint8List(0);
    }
  }

  // ====================== EMBEDDED NOORI NASTALIQ FONT ======================
  // PASTE YOUR FULL BASE64 STRING FROM base64.txt HERE (inside the triple quotes)
  static const String _nooriBase64 = """
PASTE_YOUR_COMPLETE_BASE64_STRING_HERE
""";

  static Future<pw.Font> getNooriFont() async {
    final clean = _nooriBase64.replaceAll(RegExp(r'\s+'), '').trim();
    if (clean.isNotEmpty && clean.length > 100) {
      try {
        final bytes = base64Decode(clean);
        return pw.Font.ttf(ByteData.view(bytes.buffer));
      } catch (e) {
        debugPrint('Failed to load embedded Noori Nastaliq: $e');
      }
    }
    return pw.Font.helvetica(); // safe fallback
  }

  static Future<pw.Font> getEnglishFont() async => pw.Font.helvetica();

  // ====================== PDF HEADER ======================
  static pw.Widget buildPdfHeader(pw.Font english, pw.Font urdu,
      Uint8List moonBytes, Uint8List logoBytes, String doctorName,
      {required bool isPrint}) {
    final textColor = isPrint ? PdfColors.black : PdfColors.green;
    final drColor = isPrint ? PdfColors.black : PdfColors.red;
    return pw.Column(children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Transform.rotate(
            angle: -0.55,
            child: pw.Image(pw.MemoryImage(moonBytes), width: 80, height: 80)),
        pw.Expanded(
            child: pw.Column(children: [
          pw.Text('ہو الشافی',
              style: pw.TextStyle(
                  font: urdu,
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: drColor)),
          pw.Text('Gulzar-e-Madina Welfare Foundation',
              style: pw.TextStyle(
                  font: english,
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: textColor)),
          pw.Text('Free Dispensary',
              style: pw.TextStyle(
                  font: english,
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: textColor)),
        ])),
        pw.Image(pw.MemoryImage(logoBytes), width: 85, height: 85),
      ]),
      pw.SizedBox(height: 16),
      pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Padding(
              padding: const pw.EdgeInsets.only(left: 20),
              child: pw.Text(
                  doctorName.isNotEmpty
                      ? 'Dr. $doctorName'
                      : 'Dr. ____________',
                  style: pw.TextStyle(
                      color: drColor,
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      font: english))))
    ]);
  }

  // ====================== LAB TESTS COLUMN ======================
  static pw.Widget buildPdfLabColumn(pw.Font english, List labTests,
      {required bool isPrint}) {
    final titleColor = isPrint ? PdfColors.black : PdfColors.green;
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Lab Tests',
              style: pw.TextStyle(
                  font: english,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: titleColor)),
          pw.SizedBox(height: 8),
          ...labTests.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Text('• ${item['name'] ?? ''}',
                  style: pw.TextStyle(
                      fontSize: 16,
                      color: PdfColors.black,
                      font: english,
                      fontWeight: pw.FontWeight.bold))))
        ]);
  }

  // ====================== RIGHT COLUMN (Patient Info + Medicines) ======================
  static pw.Widget buildPdfRightColumn(
      pw.Font english,
      pw.Font urdu,
      Uint8List rxBytes,
      String patientName,
      String diagnosis,
      List inventoryMeds,
      List inventoryInjectables,
      List customMeds,
      List customInjectables,
      {required bool isPrint,
      required String gender,
      required String age}) {
    final textColor = isPrint ? PdfColors.black : PdfColors.green;
    if (isPrint) {
      return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.RichText(
                text: pw.TextSpan(
                    style: pw.TextStyle(
                        font: english,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold),
                    children: [
                  const pw.TextSpan(text: 'Patient: '),
                  pw.TextSpan(text: patientName),
                  const pw.TextSpan(text: ' Gender: '),
                  pw.TextSpan(text: gender),
                  const pw.TextSpan(text: ' Age: '),
                  pw.TextSpan(text: age),
                ])),
            ...buildPdfMedicineSections(english, urdu,
                isPrint: true,
                inventoryMeds: [],
                inventoryInjectables: [],
                customMeds: customMeds,
                customInjectables: customInjectables)
          ]);
    }
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.RichText(
              text: pw.TextSpan(
                  style: pw.TextStyle(font: english, fontSize: 16),
                  children: [
                pw.TextSpan(
                    text: 'Patient: ',
                    style: pw.TextStyle(
                        color: textColor, fontWeight: pw.FontWeight.bold)),
                pw.TextSpan(text: patientName),
                const pw.TextSpan(text: ' '),
                pw.TextSpan(
                    text: 'Gender: ',
                    style: pw.TextStyle(
                        color: textColor, fontWeight: pw.FontWeight.bold)),
                pw.TextSpan(text: gender),
                const pw.TextSpan(text: ' '),
                pw.TextSpan(
                    text: 'Age: ',
                    style: pw.TextStyle(
                        color: textColor, fontWeight: pw.FontWeight.bold)),
                pw.TextSpan(text: age),
              ])),
          if (diagnosis.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Image(pw.MemoryImage(rxBytes), width: 40, height: 40),
            pw.SizedBox(height: 6),
            pw.Text('Diagnosis',
                style: pw.TextStyle(
                    font: english,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: textColor)),
            pw.Text(diagnosis,
                style: pw.TextStyle(fontSize: 16, font: english)),
          ],
          ...buildPdfMedicineSections(english, urdu,
              isPrint: false,
              inventoryMeds: inventoryMeds,
              inventoryInjectables: inventoryInjectables,
              customMeds: customMeds,
              customInjectables: customInjectables)
        ]);
  }

  static pw.Widget buildPdfFooter(pw.Font english, String branchName) =>
      pw.Center(
          child: pw.Column(children: [
        pw.Text('Gulzar e Madina $branchName',
            style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
                font: english)),
        pw.Text('Website: gulzarmadina.com',
            style: pw.TextStyle(
                fontSize: 12, color: PdfColors.grey, font: english))
      ]));

  static pw.Widget pdfVerticalDivider() => pw.Container(
      width: 1,
      height: 400,
      color: PdfColors.grey400,
      margin: const pw.EdgeInsets.symmetric(horizontal: 20));

  // ====================== PDF GENERATORS ======================
  static Future<Uint8List> generatePrintPdf(
      Map<String, dynamic> data, String gender, String age) async {
    final pdf = pw.Document();
    final english = await getEnglishFont();
    final urdu = await getNooriFont();
    final moonBytes = await loadAssetBytes('assets/images/moon.png');
    final logoBytes = await loadAssetBytes('assets/logo/gmwf.png');
    final labTests = (data['labResults'] ?? []) as List;
    final prescriptions = (data['prescriptions'] ?? []) as List;
    final customMeds = prescriptions
        .where((m) => m['inventoryId'] == null && !isInjectable(m))
        .toList();
    final customInjectables = prescriptions
        .where((m) => m['inventoryId'] == null && isInjectable(m))
        .toList();
    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (labTests.isNotEmpty) ...[
                    buildPdfLabColumn(english, labTests, isPrint: true),
                    pw.SizedBox(height: 20)
                  ],
                  if (customMeds.isNotEmpty ||
                      customInjectables.isNotEmpty) ...[
                    pw.Text('Custom Medicines',
                        style: pw.TextStyle(
                            font: english,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black)),
                    ...buildPdfMedicineItems(english, urdu, customMeds,
                        isPrint: true, isInjectable: false),
                    if (customInjectables.isNotEmpty) ...[
                      pw.SizedBox(height: 20),
                      pw.Text('Injectables',
                          style: pw.TextStyle(
                              font: english,
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black)),
                      ...buildPdfMedicineItems(english, urdu, customInjectables,
                          isPrint: true, isInjectable: true)
                    ]
                  ]
                ])));
    return pdf.save();
  }

  static Future<Uint8List> generateWhatsAppPdf(Map<String, dynamic> data,
      String branchName, String gender, String age) async {
    final pdf = pw.Document();
    final english = await getEnglishFont();
    final urdu = await getNooriFont();
    final moonBytes = await loadAssetBytes('assets/images/moon.png');
    final logoBytes = await loadAssetBytes('assets/logo/gmwf.png');
    final rxBytes = await loadAssetBytes('assets/images/rx.png');
    final doctorName = data['doctorName']?.toString() ?? '';
    final patientName = data['patientName']?.toString() ?? '';
    final diagnosis = data['diagnosis']?.toString() ?? '';
    final labTests = (data['labResults'] ?? []) as List;
    final prescriptions = (data['prescriptions'] ?? []) as List;
    final inventoryMeds = prescriptions
        .where((m) => m['inventoryId'] != null && !isInjectable(m))
        .toList();
    final inventoryInjectables = prescriptions
        .where((m) => m['inventoryId'] != null && isInjectable(m))
        .toList();
    final customMeds = prescriptions
        .where((m) => m['inventoryId'] == null && !isInjectable(m))
        .toList();
    final customInjectables = prescriptions
        .where((m) => m['inventoryId'] == null && isInjectable(m))
        .toList();
    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(children: [
              buildPdfHeader(english, urdu, moonBytes, logoBytes, doctorName,
                  isPrint: false),
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 1.5),
              pw.SizedBox(height: 20),
              pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (labTests.isNotEmpty)
                      pw.Expanded(
                          flex: 2,
                          child: buildPdfLabColumn(english, labTests,
                              isPrint: false)),
                    if (labTests.isNotEmpty) pdfVerticalDivider(),
                    pw.Expanded(
                        flex: 8,
                        child: buildPdfRightColumn(
                            english,
                            urdu,
                            rxBytes,
                            patientName,
                            diagnosis,
                            inventoryMeds,
                            inventoryInjectables,
                            customMeds,
                            customInjectables,
                            isPrint: false,
                            gender: gender,
                            age: age))
                  ]),
              pw.SizedBox(height: 40),
              pw.Divider(color: PdfColors.grey),
              pw.SizedBox(height: 10),
              buildPdfFooter(english, branchName)
            ])));
    return pdf.save();
  }

  // ====================== MEDICINE SECTIONS & ITEMS ======================
  static List<pw.Widget> buildPdfMedicineSections(pw.Font english, pw.Font urdu,
      {required bool isPrint,
      required List inventoryMeds,
      required List inventoryInjectables,
      required List customMeds,
      required List customInjectables}) {
    final sections = <pw.Widget>[];
    void add(String title, List items, {bool inj = false}) {
      if (items.isEmpty) return;
      sections.add(pw.SizedBox(height: 20));
      sections.add(pw.Text(title,
          style: pw.TextStyle(
              font: english,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: isPrint ? PdfColors.black : PdfColors.green)));
      sections.addAll(buildPdfMedicineItems(english, urdu, items,
          isPrint: isPrint, isInjectable: inj));
    }

    add('Inventory Medicines', inventoryMeds);
    add('Inventory Injectables', inventoryInjectables, inj: true);
    add('Custom Medicines', customMeds);
    add('Custom Injectables', customInjectables, inj: true);
    return sections;
  }

  static List<pw.Widget> buildPdfMedicineItems(
      pw.Font english, pw.Font urdu, List items,
      {required bool isPrint, required bool isInjectable}) {
    final timingColor = isPrint ? PdfColors.black : PdfColors.green;
    final totalColor = isPrint ? PdfColors.black : PdfColors.red;
    return items.map((m) {
      final name = m['name']?.toString() ?? '';
      final meal = m['meal']?.toString() ?? '';
      final beforeSleep = m['beforeSleep'] as bool? ?? false;
      final timing = m['timing']?.toString() ?? '';
      final quantity = m['quantity'] ?? 1;
      final total = totalPerDay(timing);
      final timingDisp = formatTimingDisplay(timing);
      final urduTiming = isPrint ? '' : timingToUrdu(timing);
      final mealText = getMealText(meal);
      final sleepText = getSleepText();
      final mealUrdu = isPrint ? '' : getMealUrdu(meal);
      final sleepUrdu = isPrint ? '' : getSleepUrdu();
      final urduDetails = [
        if (meal.isNotEmpty) mealUrdu,
        if (beforeSleep) sleepUrdu
      ].join(' - ');
      final showTiming = !isInjectable && total > 0;
      final showQty = isInjectable;
      return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(children: [
                  pw.Expanded(
                      flex: 3,
                      child: pw.Text('• $name',
                          style: pw.TextStyle(
                              font: english,
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold))),
                  if (showTiming)
                    pw.Expanded(
                        flex: 3,
                        child: pw.Align(
                            alignment: pw.Alignment.centerLeft,
                            child: pw.RichText(
                                text: pw.TextSpan(children: [
                              pw.TextSpan(
                                  text: timingDisp,
                                  style: pw.TextStyle(
                                      font: english,
                                      fontSize: 16,
                                      fontWeight: pw.FontWeight.bold,
                                      color: timingColor)),
                              const pw.TextSpan(text: ' ('),
                              pw.TextSpan(
                                  text: '$total',
                                  style: pw.TextStyle(
                                      font: english,
                                      fontSize: 15,
                                      fontWeight: pw.FontWeight.bold,
                                      color: totalColor)),
                              const pw.TextSpan(text: ')')
                            ])))),
                  if (showQty)
                    pw.Expanded(
                        flex: 3,
                        child: pw.Center(
                            child: pw.Text('Qty: $quantity',
                                style: pw.TextStyle(
                                    font: english,
                                    fontSize: 16,
                                    fontWeight: pw.FontWeight.bold,
                                    color: timingColor))))
                ]),
                if (meal.isNotEmpty || beforeSleep)
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Row(children: [
                        pw.Expanded(
                            flex: 3,
                            child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  if (meal.isNotEmpty)
                                    pw.Text(mealText,
                                        style: pw.TextStyle(
                                            font: english,
                                            fontSize: 14,
                                            color: isPrint
                                                ? PdfColors.black
                                                : PdfColors.green)),
                                  if (beforeSleep)
                                    pw.Text(sleepText,
                                        style: pw.TextStyle(
                                            font: english,
                                            fontSize: 14,
                                            color: isPrint
                                                ? PdfColors.black
                                                : PdfColors.green))
                                ])),
                        if (showTiming || showQty)
                          pw.Expanded(flex: 3, child: pw.SizedBox())
                      ])),
                if (showTiming && urduTiming.isNotEmpty)
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(urduTiming,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                  font: urdu,
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold)))),
                if ((meal.isNotEmpty || beforeSleep) && urduDetails.isNotEmpty)
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(urduDetails,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                  font: urdu,
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold))))
              ]));
    }).toList();
  }

  // ====================== BACKGROUND PDF GENERATION + SAVE ======================
  static Future<void> generateAndSavePdfInBackground({
    required Map<String, dynamic> data,
    required String branchName,
    required String gender,
    required String age,
    required String serial,
    required Function(File file) onComplete,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/Gulzar-e-Madina Prescriptions');
    await folder.create(recursive: true);

    final fileName = 'Prescription_$serial.pdf';
    final file = File('${folder.path}/$fileName');

    if (await file.exists()) {
      onComplete(file);
      return;
    }

    final pdfBytes = await compute(_generateWhatsAppPdfIsolated, {
      'data': data,
      'branchName': branchName,
      'gender': gender,
      'age': age,
    });

    await file.writeAsBytes(pdfBytes);
    onComplete(file);
  }

  static Future<Uint8List> _generateWhatsAppPdfIsolated(
      Map<String, dynamic> params) async {
    return await generateWhatsAppPdf(
      params['data'] as Map<String, dynamic>,
      params['branchName'] as String,
      params['gender'] as String,
      params['age'] as String,
    );
  }
}
