// lib/pages/patient_form_helper.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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
    final parts =
        timing.split('+').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    while (parts.length < 3) parts.add(0);
    return parts.sublist(0, 3);
  }

  static int totalPerDay(String timing) =>
      parseTiming(timing).reduce((a, b) => a + b);

  static bool isInjectable(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString().toLowerCase().trim();
    final name = (m['name'] ?? '').toString().toLowerCase();
    return type.contains('injection') ||
        type.contains('inj') ||
        type.contains('drip') ||
        type.contains('syringe') ||
        name.contains('injection') ||
        name.contains('inj');
  }

  static String getUnitUrdu(Map<String, dynamic> med) {
    final type = (med['type'] ?? '').toString().toLowerCase().trim();
    final name = (med['name'] ?? '').toString().toLowerCase();
    final dosage = (med['dosage'] ?? '').toString().toLowerCase();
    if (type.contains('syrup') ||
        type.contains('syp') ||
        name.contains('syrup') ||
        name.contains('syp') ||
        dosage.contains('spoon')) return 'چمچ';
    if (type.contains('capsule') || type.contains('cap')) return 'کیپسول';
    return 'گولی';
  }

  static String buildUrduDosageLine(Map<String, dynamic> med) {
    final timing = med['timing']?.toString() ?? '';
    final quantity = med['quantity'] ?? 1;
    if (isInjectable(med)) return 'مقدار: $quantity';
    final totalPerDayVal = totalPerDay(timing);
    num dosePerTime = 1;
    final dosage = med['dosage']?.toString() ?? '';
    if (dosage.isNotEmpty) {
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(dosage);
      if (match != null) dosePerTime = num.tryParse(match.group(1)!) ?? 1;
    }
    final unitUrdu = getUnitUrdu(med);
    final parts = parseTiming(timing);
    List<String> periods = [];
    if (parts[0] > 0)
      periods.add('${(parts[0] * dosePerTime).toInt()} $unitUrdu صبح');
    if (parts[1] > 0)
      periods.add('${(parts[1] * dosePerTime).toInt()} $unitUrdu دوپہر');
    if (parts[2] > 0)
      periods.add('${(parts[2] * dosePerTime).toInt()} $unitUrdu شام');
    if (periods.isNotEmpty) return periods.join(' - ');
    final doseStr = dosePerTime == dosePerTime.floor()
        ? dosePerTime.toInt().toString()
        : dosePerTime.toStringAsFixed(1);
    return 'مقدار: $doseStr $unitUrdu';
  }

  static String getMealUrdu(String meal) {
    switch (meal) {
      case 'Empty Stomach':
        return 'خالی پیٹ';
      case 'Before Meal':
        return 'کھانے سے پہلے';
      case 'During Meal':
        return 'کھانے کے دوران';
      case 'After Meal':
        return 'کھانے کے بعد';
      case 'Before Sleep':
        return 'سونے سے پہلے';
      default:
        return '';
    }
  }

  static String _getMedAbbrevStatic(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('syrup')) return 'syp.';
    if (t.contains('injection')) return 'inj.';
    if (t.contains('tablet')) return 'tab.';
    if (t.contains('capsule')) return 'cap.';
    if (t.contains('drip')) return 'drip.';
    if (t.contains('syringe')) return 'syr.';
    return '';
  }

  /// Returns only the timing string, e.g. "1+1+1" or "Qty: 2" for injectables.
  static String buildEnglishDosageLine(Map<String, dynamic> med) {
    final timing = med['timing']?.toString() ?? '';
    final quantity = med['quantity'] ?? 1;

    if (isInjectable(med)) {
      return 'Qty: $quantity';
    }

    return timing.isNotEmpty ? timing : 'Qty: $quantity';
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

  // ====================== FONT HELPERS ======================
  static Future<pw.Font> getNooriFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/Noori.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      return pw.Font.helvetica();
    }
  }

  static Future<pw.Font> getEnglishFont() async {
    return pw.Font.helvetica();
  }

  // =========================================================================
  // PRINT SLIP — clean, English-only, small page (A5 or thermal 80mm)
  // Contents:
  //   • gmwf.png logo  +  "Free Dispensary" title (English only)
  //   • Lab tests (if any)
  //   • Custom medicines (name + dosage + quantity)
  //   • Custom injectables (name + quantity)
  //
  // NO patient name/token, NO Urdu, NO Unicode bullets, NO inventory medicines.
  // =========================================================================
  static Future<Uint8List> generatePrintSlip({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final english = await getEnglishFont();
    final logoBytes = await loadAssetBytes('assets/logo/gmwf.png');

    final labTests = (data['labResults'] ?? []) as List;
    final prescriptions = (data['prescriptions'] ?? []) as List;

    // Only custom items on the slip
    final customMeds = prescriptions
        .where((m) => m['inventoryId'] == null && !isInjectable(m))
        .toList();
    final customInjectables = prescriptions
        .where((m) => m['inventoryId'] == null && isInjectable(m))
        .toList();

    final teal = PdfColor.fromHex('#00695C');
    final black = PdfColors.black;
    final grey = PdfColors.grey700;

    final pdf = pw.Document();

    pw.Widget _label(String text, {double size = 9, PdfColor? color}) =>
        pw.Text(text,
            style: pw.TextStyle(
                font: english,
                fontSize: size,
                color: color ?? black,
                fontWeight: pw.FontWeight.bold));

    pw.Widget _value(String text, {double size = 9}) =>
        pw.Text(text,
            style: pw.TextStyle(font: english, fontSize: size, color: black));

    // Build medicine rows — name left, dosage right — no bullets
    pw.Widget _medRow(Map<String, dynamic> med) {
      final abbrev = _getMedAbbrevStatic(med['type']);
      final name = '$abbrev ${med['name'] ?? ''}'.trim();
      final dosage = buildEnglishDosageLine(med);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Text(name,
                  style: pw.TextStyle(
                      font: english,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              flex: 5,
              child: pw.Text(dosage,
                  style: pw.TextStyle(
                      font: english, fontSize: 8, color: PdfColors.grey800)),
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        // 80mm thermal width; height auto via content — use A5 as fallback
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
            marginAll: 5 * PdfPageFormat.mm),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoBytes.isNotEmpty)
                    pw.Image(pw.MemoryImage(logoBytes), width: 36, height: 36)
                  else
                    pw.SizedBox(width: 36, height: 36),
                  pw.SizedBox(width: 6),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Gulzar-e-Madina Welfare Foundation',
                          style: pw.TextStyle(
                              font: english,
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: teal)),
                      pw.Text('Free Dispensary',
                          style: pw.TextStyle(
                              font: english,
                              fontSize: 8,
                              color: teal)),
                      if (branchName.isNotEmpty && branchName != 'Free Dispensary')
                        pw.Text(branchName,
                            style: pw.TextStyle(
                                font: english, fontSize: 7, color: grey)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5, color: grey),

              // ── Lab Tests ────────────────────────────────────────────────
              if (labTests.isNotEmpty) ...[
                _label('Lab Tests', size: 9, color: teal),
                pw.SizedBox(height: 3),
                ...labTests.map((lab) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Text(lab['name']?.toString() ?? '',
                          style: pw.TextStyle(font: english, fontSize: 9)),
                    )),
              ],

              // ── Custom Medicines ─────────────────────────────────────────
              if (customMeds.isNotEmpty) ...[
                pw.Divider(thickness: 0.4, color: grey),
                _label('Medicines', size: 9, color: teal),
                pw.SizedBox(height: 3),
                ...customMeds.map((m) => _medRow(m)),
              ],

              // ── Custom Injectables ───────────────────────────────────────
              if (customInjectables.isNotEmpty) ...[
                pw.Divider(thickness: 0.4, color: grey),
                _label('Injectables', size: 9, color: teal),
                pw.SizedBox(height: 3),
                ...customInjectables.map((m) => _medRow(m)),
              ],

              // ── Footer ───────────────────────────────────────────────────
              pw.Divider(thickness: 0.5, color: grey),
              pw.Center(
                child: pw.Text('gulzarmadina.com',
                    style: pw.TextStyle(
                        font: english, fontSize: 7, color: grey)),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ====================== PDF HEADER (WhatsApp / full doc) =================
  static pw.Widget buildPdfHeader(
    pw.Font english,
    pw.Font urdu,
    Uint8List logoBytes,
    Uint8List moonBytes,
    String doctorName, {
    required bool isPrint,
    bool includeDoctor = true,
  }) {
    final textColor = PdfColors.green;
    final drColor = isPrint ? PdfColors.green : PdfColors.red;
    final logoSize = isPrint ? 70.0 : 85.0;
    final titleSize1 = isPrint ? 18.0 : 28.0;
    final titleSize2 = isPrint ? 16.0 : 26.0;
    final titleSize3 = isPrint ? 14.0 : 24.0;
    final doctorSize = isPrint ? 12.0 : 22.0;
    return pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.start,
        children: [
          if (logoBytes.isNotEmpty)
            pw.Image(pw.MemoryImage(logoBytes),
                width: logoSize, height: logoSize)
          else
            pw.SizedBox(width: logoSize, height: logoSize),
          pw.SizedBox(width: 8),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('ہو الشافی',
                style: pw.TextStyle(
                    font: urdu,
                    fontSize: titleSize1,
                    fontWeight: pw.FontWeight.bold,
                    color: drColor)),
            pw.Text('Gulzar-e-Madina Welfare Foundation',
                style: pw.TextStyle(
                    font: english,
                    fontSize: titleSize2,
                    fontWeight: pw.FontWeight.bold,
                    color: textColor)),
            pw.Text('Free Dispensary',
                style: pw.TextStyle(
                    font: english,
                    fontSize: titleSize3,
                    fontWeight: pw.FontWeight.bold,
                    color: textColor)),
          ]),
        ],
      ),
      pw.SizedBox(height: isPrint ? 4 : 16),
      if (includeDoctor)
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(left: 20),
            child: pw.Text(
              doctorName.isNotEmpty ? 'Dr. $doctorName' : 'Dr. ____________',
              style: pw.TextStyle(
                  color: drColor,
                  fontSize: doctorSize,
                  fontWeight: pw.FontWeight.bold,
                  font: english),
            ),
          ),
        ),
    ]);
  }

  static pw.Widget buildPdfLabColumn(pw.Font english, List labTests,
      {required bool isPrint}) {
    final titleColor = PdfColors.green;
    final titleSize = isPrint ? 12.0 : 18.0;
    final itemSize = isPrint ? 10.0 : 16.0;
    final paddingVertical = isPrint ? 2.0 : 6.0;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Lab Tests',
            style: pw.TextStyle(
                font: english,
                fontSize: titleSize,
                fontWeight: pw.FontWeight.bold,
                color: titleColor)),
        pw.SizedBox(height: isPrint ? 2 : 8),
        ...labTests.map((item) => pw.Padding(
              padding: pw.EdgeInsets.symmetric(vertical: paddingVertical),
              child: pw.Text(item['name'] ?? '',
                  style: pw.TextStyle(
                      fontSize: itemSize,
                      color: PdfColors.black,
                      font: english,
                      fontWeight: pw.FontWeight.bold)),
            )),
      ],
    );
  }

  static pw.Widget buildPdfRightColumn(
    pw.Font english,
    pw.Font urdu,
    Uint8List rxBytes,
    String patientName,
    String diagnosis,
    List inventoryMeds,
    List inventoryInjectables,
    List customMeds,
    List customInjectables, {
    required bool isPrint,
    required String gender,
    required String age,
  }) {
    final textColor = PdfColors.green;
    final patientSize = isPrint ? 10.0 : 16.0;
    final diagTitleSize = isPrint ? 12.0 : 18.0;
    final diagSize = isPrint ? 10.0 : 16.0;
    final patientStyle = pw.TextStyle(font: english, fontSize: patientSize);
    final labelStyle =
        pw.TextStyle(color: textColor, fontWeight: pw.FontWeight.bold);

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.RichText(
        text: pw.TextSpan(style: patientStyle, children: [
          pw.TextSpan(text: 'Patient: ', style: labelStyle),
          pw.TextSpan(text: patientName),
          const pw.TextSpan(text: ' '),
          pw.TextSpan(text: 'Gender: ', style: labelStyle),
          pw.TextSpan(text: gender),
          const pw.TextSpan(text: ' '),
          pw.TextSpan(text: 'Age: ', style: labelStyle),
          pw.TextSpan(text: age),
        ]),
      ),
      if (diagnosis.isNotEmpty && !isPrint) ...[
        pw.SizedBox(height: 20),
        if (rxBytes.isNotEmpty)
          pw.Image(pw.MemoryImage(rxBytes),
              width: isPrint ? 30 : 40, height: isPrint ? 30 : 40),
        pw.SizedBox(height: 6),
        pw.Text('Diagnosis',
            style: pw.TextStyle(
                font: english,
                fontSize: diagTitleSize,
                fontWeight: pw.FontWeight.bold,
                color: textColor)),
        pw.Text(diagnosis,
            style: pw.TextStyle(fontSize: diagSize, font: english)),
      ],
      ...buildPdfMedicineSections(english, urdu,
          isPrint: isPrint,
          inventoryMeds: inventoryMeds,
          inventoryInjectables: inventoryInjectables,
          customMeds: customMeds,
          customInjectables: customInjectables),
    ]);
  }

  static pw.Widget buildPdfFooter(pw.Font english, String branchName) =>
      pw.Center(
        child: pw.Column(children: [
          pw.Text('Gulzar e Madina $branchName',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  font: english)),
          pw.Text('Website: gulzarmadina.com',
              style: pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey, font: english)),
        ]),
      );

  static pw.Widget pdfVerticalDivider() => pw.Container(
      width: 1,
      height: 400,
      color: PdfColors.grey400,
      margin: const pw.EdgeInsets.symmetric(horizontal: 20));

  static List<pw.Widget> buildPdfMedicineSections(
    pw.Font english,
    pw.Font urdu, {
    required bool isPrint,
    required List inventoryMeds,
    required List inventoryInjectables,
    required List customMeds,
    required List customInjectables,
  }) {
    final sections = <pw.Widget>[];
    final titleSize = isPrint ? 12.0 : 18.0;
    final spacing = isPrint ? 10.0 : 20.0;

    void add(String title, List items, {bool inj = false}) {
      if (items.isEmpty) return;
      sections.add(pw.SizedBox(height: spacing));
      sections.add(pw.Text(title,
          style: pw.TextStyle(
              font: english,
              fontSize: titleSize,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green)));
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
    pw.Font english,
    pw.Font urdu,
    List items, {
    required bool isPrint,
    required bool isInjectable,
  }) {
    final timingColor = isPrint ? PdfColors.black : PdfColors.green;
    final totalColor = isPrint ? PdfColors.black : PdfColors.red;
    final paddingVertical = isPrint ? 2.0 : 6.0;
    final nameSize = isPrint ? 10.0 : 16.0;
    final timingSize = isPrint ? 10.0 : 16.0;
    final totalSize = isPrint ? 9.0 : 15.0;
    final urduSize = isPrint ? 8.0 : 14.0;

    return items.map((m) {
      final rawName = m['name']?.toString() ?? '';
      final prefixType = _getMedAbbrevStatic(m['type']);
      final name = '$prefixType$rawName'.trim();
      final timing = m['timing']?.toString() ?? '';
      final quantity = m['quantity'] ?? 1;
      final total = totalPerDay(timing);
      final timingDisp = timing.replaceAll('+', '+');
      final urduTiming = buildUrduDosageLine(m);
      final urduDose = (total <= 0 && !isInjectable)
          ? 'مقدار: $quantity ${getUnitUrdu(m)}'
          : '';
      final mealUrdu = getMealUrdu(m['meal']?.toString() ?? '');
      final showTiming = !isInjectable && total > 0;
      final showQty = isInjectable;

      if (isPrint) {
        return pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: paddingVertical),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Text(name,
                  style: pw.TextStyle(
                      font: english,
                      fontSize: nameSize,
                      fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(
              child: pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (urduTiming.isNotEmpty)
                      pw.Text(urduTiming,
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              font: urdu,
                              fontSize: urduSize,
                              fontWeight: pw.FontWeight.bold)),
                    if (urduDose.isNotEmpty)
                      pw.Text(urduDose,
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              font: urdu,
                              fontSize: urduSize,
                              fontWeight: pw.FontWeight.bold)),
                    if (mealUrdu.isNotEmpty)
                      pw.Text(mealUrdu,
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              font: urdu,
                              fontSize: urduSize,
                              fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ]),
        );
      } else {
        return pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: paddingVertical),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(name,
                      style: pw.TextStyle(
                          font: english,
                          fontSize: nameSize,
                          fontWeight: pw.FontWeight.bold)),
                ),
                if (showTiming)
                  pw.Expanded(
                    flex: 3,
                    child: pw.RichText(
                      text: pw.TextSpan(children: [
                        pw.TextSpan(
                            text: timingDisp,
                            style: pw.TextStyle(
                                font: english,
                                fontSize: timingSize,
                                fontWeight: pw.FontWeight.bold,
                                color: timingColor)),
                        const pw.TextSpan(text: ' '),
                        pw.TextSpan(
                            text: '$total/day',
                            style: pw.TextStyle(
                                font: english,
                                fontSize: totalSize,
                                fontWeight: pw.FontWeight.bold,
                                color: totalColor)),
                      ]),
                    ),
                  ),
                if (showQty)
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text('Qty: $quantity',
                        style: pw.TextStyle(
                            font: english,
                            fontSize: timingSize,
                            fontWeight: pw.FontWeight.bold,
                            color: timingColor)),
                  ),
              ]),
              if (urduTiming.isNotEmpty)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Text(urduTiming,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                                font: urdu,
                                fontSize: urduSize,
                                fontWeight: pw.FontWeight.bold)))),
              if (urduDose.isNotEmpty)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Text(urduDose,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                                font: urdu,
                                fontSize: urduSize,
                                fontWeight: pw.FontWeight.bold)))),
              if (mealUrdu.isNotEmpty)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Text(mealUrdu,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                                font: urdu,
                                fontSize: urduSize,
                                fontWeight: pw.FontWeight.bold)))),
            ],
          ),
        );
      }
    }).toList();
  }

  // ====================== WhatsApp PDF (unchanged) =========================
  static Future<Uint8List> generateWhatsAppPdf(
    Map<String, dynamic> data,
    String branchName,
    String gender,
    String age,
  ) async {
    final pdf = pw.Document();
    final english = await getEnglishFont();
    final urdu = await getNooriFont();
    final logoBytes = await loadAssetBytes('assets/logo/gmwf.png');
    final moonBytes = await loadAssetBytes('assets/images/moon.png');
    final rxBytes = await loadAssetBytes('assets/images/rx.png');
    final doctorName = data['doctorName']?.toString() ?? '';
    final patientName = data['patientName']?.toString() ?? '';
    final diagnosis = data['diagnosis']?.toString() ?? '';
    final labTests = (data['labResults'] ?? []) as List;
    final prescriptions = (data['prescriptions'] ?? []) as List;
    final inventoryMeds =
        prescriptions.where((m) => m['inventoryId'] != null && !isInjectable(m)).toList();
    final inventoryInjectables =
        prescriptions.where((m) => m['inventoryId'] != null && isInjectable(m)).toList();
    final customMeds =
        prescriptions.where((m) => m['inventoryId'] == null && !isInjectable(m)).toList();
    final customInjectables =
        prescriptions.where((m) => m['inventoryId'] == null && isInjectable(m)).toList();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(children: [
        buildPdfHeader(english, urdu, logoBytes, moonBytes, doctorName,
            isPrint: false, includeDoctor: true),
        pw.SizedBox(height: 20),
        pw.Divider(thickness: 1.5),
        pw.SizedBox(height: 20),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (labTests.isNotEmpty)
            pw.Expanded(
                flex: 2,
                child: buildPdfLabColumn(english, labTests, isPrint: false)),
          if (labTests.isNotEmpty) pdfVerticalDivider(),
          pw.Expanded(
            flex: 8,
            child: buildPdfRightColumn(english, urdu, rxBytes, patientName,
                diagnosis, inventoryMeds, inventoryInjectables, customMeds,
                customInjectables,
                isPrint: false, gender: gender, age: age),
          ),
        ]),
        pw.SizedBox(height: 40),
        pw.Divider(color: PdfColors.grey),
        pw.SizedBox(height: 10),
        buildPdfFooter(english, branchName),
      ]),
    ));
    return pdf.save();
  }
}