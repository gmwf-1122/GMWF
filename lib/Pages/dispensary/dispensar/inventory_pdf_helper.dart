// lib/pages/dispensary/dispensar/inventory_pdf_helper.dart

import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';

class InventoryPdfHelper {
  // ── Asset loader ─────────────────────────────────────────────────────────
  static Future<Uint8List> _loadAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return Uint8List(0);
    }
  }

  // ── Type helpers ──────────────────────────────────────────────────────────
  static const _typeOrder = [
    'Tablet', 'Capsule', 'Syrup', 'Injection',
    'Drip', 'Drip Set', 'Syringe', 'Nebulization',
  ];

  static int _typeIdx(String t) {
    final i = _typeOrder.indexOf(t);
    return i == -1 ? 99 : i;
  }

  static String _typeLabel(String type) => switch (type) {
        'Tablet'       => 'TABLETS',
        'Capsule'      => 'CAPSULES',
        'Syrup'        => 'SYRUPS',
        'Injection'    => 'INJECTIONS',
        'Drip'         => 'DRIPS',
        'Drip Set'     => 'DRIP SETS',
        'Syringe'      => 'SYRINGES',
        'Nebulization' => 'NEBULIZATIONS',
        _              => type.toUpperCase(),
      };

  static String _typeAbbrev(String type) => switch (type) {
        'Tablet'       => 'Tab.',
        'Capsule'      => 'Cap.',
        'Syrup'        => 'Syr.',
        'Injection'    => 'Inj.',
        'Drip'         => 'Drip',
        'Drip Set'     => 'D.Set',
        'Syringe'      => 'Syg.',
        'Nebulization' => 'Neb.',
        _              => type,
      };

  static String _fmtQty(int qty) => NumberFormat('#,###').format(qty);

  // Rule shorthand — always use BoxDecoration.color, never the color: param
  // alongside decoration:, to avoid the Flutter/PDF assertion crash.
  static pw.BoxDecoration _border({PdfColor? bg}) => pw.BoxDecoration(
        color: bg,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // MAIN EXPORT
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> exportInventoryChecklistPdf({
    required List<Map<String, dynamic>> items,
    required String branchName,
  }) async {
    // ── Logo ─────────────────────────────────────────────────────────────
    final logoBytes = await _loadAsset('assets/logo/gmwf-1.webp');
    final pw.MemoryImage? logo =
        logoBytes.isNotEmpty ? pw.MemoryImage(logoBytes) : null;

    // ── Sort: type priority → name alphabetically ─────────────────────────
    final sorted = [...items]..sort((a, b) {
        final ta = (a['type'] ?? '').toString();
        final tb = (b['type'] ?? '').toString();
        final c  = _typeIdx(ta).compareTo(_typeIdx(tb));
        if (c != 0) return c;
        return (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase());
      });

    // ── Metadata ──────────────────────────────────────────────────────────
    final dateStr  = DateFormat('dd-MMM-yyyy').format(DateTime.now());
    final timeStr  = DateFormat('hh:mm a').format(DateTime.now());
    final totalMed = sorted.length;
    final totalQty = sorted.fold<int>(
        0, (s, b) => s + ((b['quantity'] as int?) ?? 0));
    final lowCount =
        sorted.where((b) => ((b['quantity'] as int?) ?? 0) < 10).length;

    // ── Column widths (A4 usable ≈ 563 pt with 16 pt margins) ────────────
    const double colNo       = 24;
    const double colName     = 235; // wider — formula column removed
    const double colType     =  60;
    const double colDose     =  72;
    const double colQty      =  55;
    const double colPhysical =  77; // empty box for writing

    // ── Cell builders ─────────────────────────────────────────────────────

    // Header cell: bold, dark background, white text
    pw.Widget hCell(String text, double w,
        {pw.Alignment align = pw.Alignment.centerLeft}) {
      return pw.Container(
        width: w,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey800,
          border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
        ),
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    }

    // Data cell: plain text, light border, optional shading
    pw.Widget dCell(String text, double w,
        {pw.Alignment align = pw.Alignment.centerLeft,
        PdfColor? bg,
        pw.TextStyle? style}) {
      return pw.Container(
        width: w,
        height: 20,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: _border(bg: bg),
        alignment: align,
        child: pw.Text(
          text,
          overflow: pw.TextOverflow.clip,
          maxLines: 1,
          style: style ??
              const pw.TextStyle(color: PdfColors.black, fontSize: 7.5),
        ),
      );
    }

    // Physical stock cell: empty bordered box for manual writing
    pw.Widget stockBox(double w, {PdfColor? bg}) {
      return pw.Container(
        width: w,
        height: 20,
        decoration: _border(bg: bg),
        padding: const pw.EdgeInsets.all(3),
        child: pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.6),
          ),
        ),
      );
    }

    // Type group separator: grey background, bold label
    const double totalRowW =
        colNo + colName + colType + colDose + colQty + colPhysical;

    pw.Widget typeHeader(String type) {
      return pw.Container(
        width: totalRowW,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border(
            top: const pw.BorderSide(color: PdfColors.grey600, width: 0.5),
            bottom: const pw.BorderSide(color: PdfColors.grey600, width: 0.5),
          ),
        ),
        child: pw.Text(
          '  ${_typeLabel(type)}',
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    }

    // ── Build data rows grouped by type ───────────────────────────────────
    List<pw.Widget> buildRows() {
      final rows = <pw.Widget>[];
      String? lastType;
      int idx = 0;

      for (final item in sorted) {
        final type = (item['type'] ?? '').toString();
        final name = (item['name'] ?? '').toString();
        final dose = (item['dose'] ?? '').toString();
        final qty     = (item['quantity'] as int?) ?? 0;
        final low     = qty < 10;

        // Group header when type changes
        if (type != lastType) {
          lastType = type;
          rows.add(typeHeader(type));
        }

        idx++;
        // Alternating row shade (very light grey for even rows, nothing for odd)
        final rowBg = idx % 2 == 0 ? PdfColors.grey100 : null;

        // Name cell: medicine name only
        final nameCell = pw.Container(
          width: colName,
          height: 20,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: _border(bg: rowBg),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            name,
            overflow: pw.TextOverflow.clip,
            maxLines: 1,
            style: pw.TextStyle(
                fontSize: 7.5, fontWeight: pw.FontWeight.bold),
          ),
        );

        rows.add(pw.Row(children: [
          dCell('$idx', colNo,
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                  fontSize: 6.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700)),
          nameCell,
          dCell(_typeAbbrev(type), colType,
              align: pw.Alignment.center, bg: rowBg),
          dCell(dose, colDose, bg: rowBg),
          dCell(
            _fmtQty(qty),
            colQty,
            align: pw.Alignment.center,
            bg: rowBg,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: low ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          stockBox(colPhysical, bg: rowBg),
        ]));
      }
      return rows;
    }

    // ── Summary by type ────────────────────────────────────────────────────
    pw.Widget buildSummary() {
      final Map<String, int> tCounts = {};
      final Map<String, int> tQtys   = {};
      for (final item in sorted) {
        final t   = (item['type'] ?? 'Other').toString();
        final qty = (item['quantity'] as int?) ?? 0;
        tCounts[t] = (tCounts[t] ?? 0) + 1;
        tQtys[t]   = (tQtys[t]   ?? 0) + qty;
      }
      final types = tCounts.keys.toList()
        ..sort((a, b) => _typeIdx(a).compareTo(_typeIdx(b)));

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
            ),
            child: pw.Text(
              'SUMMARY BY TYPE',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left:   const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                right:  const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                bottom: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              ),
            ),
            child: pw.Wrap(
              spacing: 14,
              runSpacing: 4,
              children: types.map((t) {
                return pw.Text(
                  '${_typeLabel(t)}: ${tCounts[t]} formula${(tCounts[t] ?? 0) == 1 ? '' : 's'}'
                  '  |  ${_fmtQty(tQtys[t] ?? 0)} units',
                  style: const pw.TextStyle(fontSize: 7.5),
                );
              }).toList()
                ..add(
                  pw.Text(
                    'Low stock (< 10 units): $lowCount medicine${lowCount == 1 ? '' : 's'}'
                    '     Total: $totalMed medicines  |  ${_fmtQty(totalQty)} units',
                    style: pw.TextStyle(
                        fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                  ),
                ),
            ),
          ),
        ],
      );
    }

    // ── Sign-off row ──────────────────────────────────────────────────────
    pw.Widget buildSignatures() {
      pw.Widget sigBox(String label) => pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  height: 30,
                  margin: const pw.EdgeInsets.symmetric(horizontal: 6),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                          color: PdfColors.black, width: 0.7),
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(label,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                        fontSize: 6.5, color: PdfColors.grey700)),
              ],
            ),
          );

      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        ),
        child: pw.Column(children: [
          pw.Text('VERIFICATION & SIGN-OFF',
              style: pw.TextStyle(
                  fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            sigBox('Counted By'),
            sigBox('Verified By'),
            sigBox('Date of Count'),
            sigBox('Remarks'),
          ]),
        ]),
      );
    }

    // ── Assemble PDF ──────────────────────────────────────────────────────
    final pdf = pw.Document();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginTop: 16, marginBottom: 16,
        marginLeft: 16, marginRight: 16,
      ),

      // ── Header (repeats every page) ────────────────────────────────────
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null)
                pw.Container(
                  width: 46,
                  height: 46,
                  margin: const pw.EdgeInsets.only(right: 10),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Gulzar Madina Welfare Foundation',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'INVENTORY STOCK CHECKLIST - $branchName',
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Generated: $dateStr  $timeStr'
                      '     Formulas: $totalMed'
                      '     Total Units: ${_fmtQty(totalQty)}',
                      style: const pw.TextStyle(
                          fontSize: 7, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              // Instructions
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.grey600, width: 0.6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('HOW TO USE',
                        style: pw.TextStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('1. Count physical stock',
                        style: const pw.TextStyle(
                            fontSize: 6, color: PdfColors.grey700)),
                    pw.Text('2. Write in last column',
                        style: const pw.TextStyle(
                            fontSize: 6, color: PdfColors.grey700)),
                    pw.Text('3. Compare with Sys. Qty',
                        style: const pw.TextStyle(
                            fontSize: 6, color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 3),
          // Column header row
          pw.Row(children: [
            hCell('#',               colNo,       align: pw.Alignment.center),
            hCell('Medicine Name',    colName),
            hCell('Type',            colType,     align: pw.Alignment.center),
            hCell('Dose',            colDose),
            hCell('Sys. Qty',        colQty,      align: pw.Alignment.center),
            hCell('Physical Stock',  colPhysical, align: pw.Alignment.center),
          ]),
        ],
      ),

      // ── Footer ────────────────────────────────────────────────────────
      footer: (ctx) => pw.Column(children: [
        pw.Divider(thickness: 0.5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'GMWF Inventory Checklist - $branchName - $dateStr',
              style: const pw.TextStyle(
                  fontSize: 6, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(
                  fontSize: 6, color: PdfColors.grey600),
            ),
          ],
        ),
      ]),

      // ── Body ──────────────────────────────────────────────────────────
      build: (ctx) => [
        ...buildRows(),
        pw.SizedBox(height: 18),
        buildSummary(),
        pw.SizedBox(height: 12),
        buildSignatures(),
      ],
    ));

    // ── Save via file picker ──────────────────────────────────────────────
    final pdfBytes   = await pdf.save();
    final safeDate   = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final safeBranch = branchName
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_')
        .toLowerCase();

    await FilePicker.platform.saveFile(
      dialogTitle:       'Save Inventory Checklist PDF',
      fileName:          'inventory_checklist_${safeBranch}_$safeDate.pdf',
      bytes:             pdfBytes,
      type:              FileType.custom,
      allowedExtensions: ['pdf'],
    );
  }
}
