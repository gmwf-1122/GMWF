import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart';

// ════════════════════════════════════════════════════════════════════════════════
// DESIGN SYSTEM
// ════════════════════════════════════════════════════════════════════════════════

class DS {
  static const bgBase    = Color(0xFFF5F6F8);
  static const bgSurface = Color(0xFFFFFFFF);

  static const navy900 = Color(0xFF0B1426);
  static const navy800 = Color(0xFF112244);
  static const navy700 = Color(0xFF163567);
  static const navy600 = Color(0xFF1B4280);
  static const navy100 = Color(0xFFE8EEF7);

  static const emerald700 = Color(0xFF065F46);
  static const emerald600 = Color(0xFF047857);
  static const emerald500 = Color(0xFF059669);
  static const emerald100 = Color(0xFFD1FAE5);

  static const sapphire700 = Color(0xFF1E3A8A);
  static const sapphire500 = Color(0xFF3B82F6);
  static const sapphire100 = Color(0xFFDBEAFE);

  static const plum700 = Color(0xFF6B21A8);
  static const plum500 = Color(0xFFA855F7);
  static const plum100 = Color(0xFFF3E8FF);

  static const gold700 = Color(0xFF92400E);
  static const gold600 = Color(0xFFB45309);
  static const gold500 = Color(0xFFD97706);
  static const gold400 = Color(0xFFFBBF24);
  static const gold100 = Color(0xFFFEF3C7);

  static const crimson700 = Color(0xFF9B1C1C);
  static const crimson500 = Color(0xFFEF4444);
  static const crimson100 = Color(0xFFFEE2E2);

  static const statusPending  = Color(0xFFD97706);
  static const statusApproved = Color(0xFF059669);
  static const statusRejected = Color(0xFFDC2626);

  static const ink900 = Color(0xFF111827);
  static const ink700 = Color(0xFF374151);
  static const ink500 = Color(0xFF6B7280);
  static const ink300 = Color(0xFFD1D5DB);
  static const ink200 = Color(0xFFE5E7EB);
  static const ink100 = Color(0xFFF3F4F6);
  static const ink50  = Color(0xFFF9FAFB);

  static List<BoxShadow> get shadowSm => [
    const BoxShadow(color: Color(0x0C000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
  static List<BoxShadow> get shadowMd => [
    const BoxShadow(color: Color(0x10000000), blurRadius: 16, offset: Offset(0, 4)),
    const BoxShadow(color: Color(0x06000000), blurRadius: 4,  offset: Offset(0, 1)),
  ];
  static List<BoxShadow> get shadowLg => [
    const BoxShadow(color: Color(0x16000000), blurRadius: 32, offset: Offset(0, 8)),
    const BoxShadow(color: Color(0x08000000), blurRadius: 8,  offset: Offset(0, 2)),
  ];

  static const rSm  = 6.0;
  static const rMd  = 10.0;
  static const rLg  = 14.0;
  static const rXl  = 18.0;
  static const r2xl = 24.0;

  static TextStyle display({Color color = ink900}) => TextStyle(
      fontSize: 24, fontWeight: FontWeight.w800, color: color,
      letterSpacing: -0.8, height: 1.15);

  static TextStyle heading({Color color = ink900}) => TextStyle(
      fontSize: 17, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.3);

  static TextStyle subheading({Color color = ink700}) => TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600, color: color);

  static TextStyle body({Color color = ink700}) => TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400, color: color);

  static TextStyle label({Color color = ink500}) => TextStyle(
      fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.9);

  static TextStyle caption({Color color = ink500}) => TextStyle(
      fontSize: 11, fontWeight: FontWeight.w500, color: color);

  static TextStyle mono({Color color = ink900, double size = 20}) => TextStyle(
      fontSize: size, fontWeight: FontWeight.w800, color: color,
      fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: -0.4);
}

// ════════════════════════════════════════════════════════════════════════════════
// SHARED STATUS CONSTANTS
// ════════════════════════════════════════════════════════════════════════════════

const String kStatusPending  = 'pending';
const String kStatusApproved = 'approved';
const String kStatusRejected = 'rejected';

// ════════════════════════════════════════════════════════════════════════════════
// PAYMENT METHOD
// ════════════════════════════════════════════════════════════════════════════════

enum PaymentMethod { cash, cheque, onlineTransfer, bankDeposit }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:           return 'Cash';
      case PaymentMethod.cheque:         return 'Cheque';
      case PaymentMethod.onlineTransfer: return 'Online Transfer';
      case PaymentMethod.bankDeposit:    return 'Bank Deposit';
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentMethod.cash:           return Icons.payments_rounded;
      case PaymentMethod.cheque:         return Icons.description_rounded;
      case PaymentMethod.onlineTransfer: return Icons.phone_android_rounded;
      case PaymentMethod.bankDeposit:    return Icons.account_balance_rounded;
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// BRANCH CODE MAP
// ════════════════════════════════════════════════════════════════════════════════

String branchCodeFor(String branchId) {
  final id = branchId.toLowerCase().trim();
  if (id.contains('gujrat') || id == 'gujrat')                return 'grt';
  if (id.contains('jalalpurjattan') || id.contains('jalalpur')) return 'jpt';
  if (id.contains('karachi-1') || id == 'karachi1')            return 'khi1';
  if (id.contains('karachi-2') || id == 'karachi2')            return 'khi2';
  if (id.contains('rawalpindi') || id == 'rawalpindi')         return 'rwp';
  if (id.contains('sialkot') || id == 'sialkot')               return 'skt';
  if (id.contains('lahore') || id == 'lahore' || id == 'lhr')  return 'lhr';
  return id.length >= 3 ? id.substring(0, 3) : id;
}

String buildReceiptNumber(String branchId, int seq) {
  final code    = branchCodeFor(branchId);
  final dateStr = DateFormat('ddMMyy').format(DateTime.now());
  final seqStr  = seq.toString().padLeft(3, '0');
  return '$code-$dateStr-$seqStr';
}

// ════════════════════════════════════════════════════════════════════════════════
// SHARED ITERABLE EXTENSION
// ════════════════════════════════════════════════════════════════════════════════

extension IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// ROLE THEME EXTENSION
// ════════════════════════════════════════════════════════════════════════════════

extension DonationTheme on RoleThemeData {
  Color get donationAccent        => accent;
  Color get donationSurface       => bgCard;
  Color get donationBg            => bg;
  Color get donationRule          => bgRule;
  Color get donationTextPrimary   => textPrimary;
  Color get donationTextSecondary => textSecondary;
  Color get donationTextTertiary  => textTertiary;
  Color get donationDanger        => danger;
}

// ════════════════════════════════════════════════════════════════════════════════
// DONATION CATEGORIES
// ════════════════════════════════════════════════════════════════════════════════

enum DonationCategory { jamia, general, goods }

extension DonationCategoryX on DonationCategory {
  String get label {
    switch (this) {
      case DonationCategory.jamia:   return 'Jamia / Masjid';
      case DonationCategory.general: return 'General Donations';
      case DonationCategory.goods:   return 'Goods / Ajnas';
    }
  }

  String get shortLabel {
    switch (this) {
      case DonationCategory.jamia:   return 'Jamia';
      case DonationCategory.general: return 'General';
      case DonationCategory.goods:   return 'Goods';
    }
  }

  IconData get icon {
    switch (this) {
      case DonationCategory.jamia:   return Icons.mosque_rounded;
      case DonationCategory.general: return Icons.volunteer_activism_rounded;
      case DonationCategory.goods:   return Icons.inventory_2_rounded;
    }
  }

  Color get color {
    switch (this) {
      case DonationCategory.jamia:   return DS.sapphire700;
      case DonationCategory.general: return DS.emerald600;
      case DonationCategory.goods:   return DS.plum700;
    }
  }

  Color get lightColor {
    switch (this) {
      case DonationCategory.jamia:   return DS.sapphire100;
      case DonationCategory.general: return DS.emerald100;
      case DonationCategory.goods:   return DS.plum100;
    }
  }

  Color get borderColor {
    switch (this) {
      case DonationCategory.jamia:   return const Color(0xFF93C5FD);
      case DonationCategory.general: return const Color(0xFF6EE7B7);
      case DonationCategory.goods:   return const Color(0xFFD8B4FE);
    }
  }

  List<Color> get gradient {
    switch (this) {
      case DonationCategory.jamia:   return [DS.sapphire700, DS.sapphire500];
      case DonationCategory.general: return [DS.emerald700,  DS.emerald500];
      case DonationCategory.goods:   return [DS.plum700,     DS.plum500];
    }
  }

  List<DonationSubtype> get subtypes {
    switch (this) {
      case DonationCategory.jamia:
        return [DonationSubtype.construction, DonationSubtype.maintenance, DonationSubtype.general];
      case DonationCategory.general:
        return [DonationSubtype.zakat, DonationSubtype.sadqaat, DonationSubtype.general];
      case DonationCategory.goods:
        return [];
    }
  }

  bool get isGoods => this == DonationCategory.goods;

  PdfColor get pdfAccent {
    switch (this) {
      case DonationCategory.jamia:   return const PdfColor.fromInt(0xFF1E3A8A);
      case DonationCategory.general: return const PdfColor.fromInt(0xFF047857);
      case DonationCategory.goods:   return const PdfColor.fromInt(0xFF6B21A8);
    }
  }

  PdfColor get pdfAccentDark {
    switch (this) {
      case DonationCategory.jamia:   return const PdfColor.fromInt(0xFF0B1F5C);
      case DonationCategory.general: return const PdfColor.fromInt(0xFF065F46);
      case DonationCategory.goods:   return const PdfColor.fromInt(0xFF4A1572);
    }
  }

  PdfColor get pdfAccentMid {
    switch (this) {
      case DonationCategory.jamia:   return const PdfColor.fromInt(0xFF3B82F6);
      case DonationCategory.general: return const PdfColor.fromInt(0xFF34D399);
      case DonationCategory.goods:   return const PdfColor.fromInt(0xFFC084FC);
    }
  }

  PdfColor get pdfLight {
    switch (this) {
      case DonationCategory.jamia:   return const PdfColor.fromInt(0xFFDBEAFE);
      case DonationCategory.general: return const PdfColor.fromInt(0xFFD1FAE5);
      case DonationCategory.goods:   return const PdfColor.fromInt(0xFFF3E8FF);
    }
  }

  String get pdfCategoryFullLabel {
    switch (this) {
      case DonationCategory.jamia:   return 'Jamia / Masjid Fund';
      case DonationCategory.general: return 'General Donations';
      case DonationCategory.goods:   return 'Goods Donation (Ajnas)';
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// DONATION SUBTYPES
// ════════════════════════════════════════════════════════════════════════════════

enum DonationSubtype {
  construction,
  maintenance,
  zakat,
  sadqaat,
  general,
}

extension DonationSubtypeX on DonationSubtype {
  String get label {
    switch (this) {
      case DonationSubtype.construction: return 'Construction';
      case DonationSubtype.maintenance:  return 'Maintenance';
      case DonationSubtype.zakat:        return 'Zakat';
      case DonationSubtype.sadqaat:      return 'Sadqaat / Atyaat';
      case DonationSubtype.general:      return 'General';
    }
  }

  IconData get icon {
    switch (this) {
      case DonationSubtype.construction: return Icons.construction_rounded;
      case DonationSubtype.maintenance:  return Icons.build_circle_rounded;
      case DonationSubtype.zakat:        return Icons.stars_rounded;
      case DonationSubtype.sadqaat:      return Icons.favorite_rounded;
      case DonationSubtype.general:      return Icons.circle_outlined;
    }
  }

  Color get color {
    switch (this) {
      case DonationSubtype.construction: return DS.sapphire700;
      case DonationSubtype.maintenance:  return DS.sapphire500;
      case DonationSubtype.zakat:        return DS.gold600;
      case DonationSubtype.sadqaat:      return DS.emerald600;
      case DonationSubtype.general:      return DS.ink500;
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════════════════

const List<String> kUnits = [
  'kg', 'gram', 'liter', 'piece', 'packet', 'maund', 'quintal',
];

// ════════════════════════════════════════════════════════════════════════════════
// MESSAGING HELPERS
// ════════════════════════════════════════════════════════════════════════════════

/// Builds a clean, professional thank-you message for WhatsApp / SMS.
/// Uses only plain text + WhatsApp markdown — no emoji icons (they break
/// when URL-encoded in wa.me links on some devices).
String buildThankYouMessage({
  required String donorName,
  required String receiptNo,
  required DonationCategory category,
  required double amount,
  required String unit,
  required String branchName,
  DonationSubtype? subtype,
  String paymentMethod = 'Cash',
}) {
  final dateStr = DateFormat('dd MMM yyyy').format(DateTime.now());
  final orgLine = branchName.trim().isNotEmpty
      ? 'Gulzar Madina Welfare Foundation - $branchName'
      : 'Gulzar Madina Welfare Foundation';

  final amtLine = category.isGoods
      ? '${amount % 1 == 0 ? amount.toInt() : amount} $unit'
      : 'PKR ${NumberFormat('#,##0', 'en_US').format(amount)}';

  final typeLabel = subtype != null
      ? '${category.pdfCategoryFullLabel} - ${subtype.label}'
      : category.pdfCategoryFullLabel;

  return 'Assalam-o-Alaikum *$donorName*,\n\n'
      'JazakAllah Khair for your generous donation. '
      'May Allah accept it and reward you abundantly.\n\n'
      '*DONATION RECEIPT*\n'
      '----------------------------\n'
      'Organisation:  $orgLine\n'
      'Receipt No:    $receiptNo\n'
      'Date:          $dateStr\n'
      'Donor:         $donorName\n'
      'Category:      $typeLabel\n'
      'Amount:        $amtLine\n'
      'Payment:       $paymentMethod\n'
      '----------------------------\n\n'
      'For queries, contact us:\n'
      '053-3525333  |  0331-8525333\n\n'
      '_Gulzar Madina Welfare Foundation_';
}

Future<void> sendSmsThankYou(
  String phone,
  String donorName,
  DonationCategory category,
  double amount,
  String unit,
  String receiptNo,
  String branchName, {
  DonationSubtype? subtype,
  String paymentMethod = 'Cash',
}) async {
  final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.isEmpty) return;

  final body = buildThankYouMessage(
    donorName:     donorName,
    receiptNo:     receiptNo,
    category:      category,
    amount:        amount,
    unit:          unit,
    branchName:    branchName,
    subtype:       subtype,
    paymentMethod: paymentMethod,
  );

  final uri = Uri(scheme: 'sms', path: clean, queryParameters: {'body': body});
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

/// Generates the receipt PDF, saves it to a temp file, and shares it
/// directly to WhatsApp with the pre-filled thank-you caption.
/// Uses share_plus XFile so the PDF is properly attached (not opened in browser).
Future<void> shareReceiptWhatsApp(
  Map<String, dynamic> d,
  String receiptNo,
  String phone,
  String branchName,
) async {
  String clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.startsWith('0')) clean = '+92${clean.substring(1)}';
  if (!clean.startsWith('+')) clean = '+92$clean';

  final donorName     = d['donorName']    as String? ?? '';
  final categoryId    = d['categoryId']   as String? ?? '';
  final cat           = DonationCategory.values.firstWhere(
      (c) => c.name == categoryId, orElse: () => DonationCategory.general);
  final subtypeId     = d['subtypeId']    as String?;
  final subtype       = subtypeId != null
      ? DonationSubtype.values.firstWhereOrNull((s) => s.name == subtypeId)
      : null;
  final amount        = (d['amount'] as num?)?.toDouble() ?? 0.0;
  final unit          = d['unit']          as String? ?? 'PKR';
  final paymentMethod = d['paymentMethod'] as String? ?? 'Cash';

  final caption = buildThankYouMessage(
    donorName:     donorName,
    receiptNo:     receiptNo,
    category:      cat,
    amount:        amount,
    unit:          unit,
    branchName:    branchName,
    subtype:       subtype,
    paymentMethod: paymentMethod,
  );

  // Build PDF bytes
  final pdfBytes = await buildReceiptPdf(d, receiptNo, PdfPageFormat.a5);

  // Write to a temp file so share_plus can attach it properly
  final tempDir  = await getTemporaryDirectory();
  final fileName = 'GMWF_Receipt_$receiptNo.pdf';
  final file     = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(pdfBytes);

  // Share via share_plus — this opens the native share sheet with the
  // PDF already attached. When the user picks WhatsApp, both the file
  // and the caption text are passed directly to the app.
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
    text:    caption,
    subject: 'Donation Receipt - $receiptNo',
  );
}

Future<void> printReceiptPdf(Map<String, dynamic> d, String receiptNo) async {
  await Printing.layoutPdf(
      onLayout: (f) => buildReceiptPdf(d, receiptNo, f));
}

Future<Uint8List> buildReceiptPdf(
  Map<String, dynamic> d,
  String receiptNo,
  PdfPageFormat format,
) async {
  final categoryId = d['categoryId'] as String? ?? '';
  final cat        = DonationCategory.values.firstWhere(
      (c) => c.name == categoryId, orElse: () => DonationCategory.general);

  pw.MemoryImage? logo;
  try {
    final data = await rootBundle.load('assets/logo/gmwf.png');
    logo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {}

  final pdfData = _ReceiptPdfData.fromMap(d, receiptNo, cat);
  return _buildModernReceipt(pdfData, logo, cat);
}

// ── PDF data model ────────────────────────────────────────────────────────────

class _ReceiptPdfData {
  final String donorName, phone, subtypeLabel, goodsItem, unit;
  final String notes, receivedBy, branchName, receiptNo, dateStr;
  final String printedAt, subtypeId, categoryId, paymentMethod;
  final double amount;
  final double? probableAmt;
  final bool isGoods;
  final String qtyStr;
  final List<List<String>> rows;

  _ReceiptPdfData._({
    required this.donorName,    required this.phone,
    required this.subtypeLabel, required this.goodsItem,
    required this.unit,         required this.notes,
    required this.receivedBy,   required this.branchName,
    required this.receiptNo,    required this.dateStr,
    required this.printedAt,    required this.subtypeId,
    required this.categoryId,   required this.amount,
    required this.probableAmt,  required this.isGoods,
    required this.qtyStr,       required this.rows,
    required this.paymentMethod,
  });

  factory _ReceiptPdfData.fromMap(
    Map<String, dynamic> d,
    String receiptNo,
    DonationCategory cat,
  ) {
    final donorName     = d['donorName']      as String? ?? 'Unknown';
    final phone         = d['phone']          as String? ?? '';
    final amount        = (d['amount'] as num?)?.toDouble() ?? 0.0;
    final subtypeId     = d['subtypeId']      as String? ?? '';
    final goodsItem     = d['goodsItem']      as String? ?? '';
    final unit          = d['unit']           as String? ?? '';
    final notes         = d['notes']          as String? ?? '';
    final receivedBy    = d['recordedBy']     as String? ?? '-';
    final branchName    = d['branchName']     as String? ?? '';
    final probableAmt   = (d['probableAmount'] as num?)?.toDouble();
    final paymentMethod = d['paymentMethod']  as String? ?? 'Cash';
    final isGoods       = cat.isGoods;
    final qtyStr        = isGoods
        ? '${amount % 1 == 0 ? amount.toInt() : amount} $unit'
        : '';

    String subtypeLabel = '';
    if (subtypeId.isNotEmpty) {
      final st = DonationSubtype.values.firstWhereOrNull((s) => s.name == subtypeId);
      subtypeLabel = st?.label ?? subtypeId;
    }

    // Build category display — plain text, no unicode separators
    String categoryDisplay = cat.pdfCategoryFullLabel;
    if (!isGoods && subtypeLabel.isNotEmpty) {
      categoryDisplay = '${cat.pdfCategoryFullLabel} - $subtypeLabel';
    }

    final dateStr   = _prettyDate(d['date'] as String?);
    final printedAt = DateFormat('dd MMM yyyy  hh:mm a').format(DateTime.now());

    final rows = <List<String>>[
      ['Donor Name',   donorName],
      if (phone.isNotEmpty)     ['Phone No.',     phone],
      ['Category',              categoryDisplay],
      if (isGoods && goodsItem.isNotEmpty) ['Item', goodsItem],
      if (isGoods)              ['Quantity',       qtyStr],
      if (isGoods && probableAmt != null)  ['Est. Value', 'PKR ${fmtAmt(probableAmt)}'],
      ['Payment Mode',          paymentMethod],
      ['Received By',           receivedBy],
      if (branchName.isNotEmpty) ['Branch',        branchName],
    ];

    return _ReceiptPdfData._(
      donorName:     donorName,    phone:         phone,
      subtypeLabel:  subtypeLabel, goodsItem:     goodsItem,
      unit:          unit,         notes:         notes,
      receivedBy:    receivedBy,   branchName:    branchName,
      receiptNo:     receiptNo,    dateStr:       dateStr,
      printedAt:     printedAt,    subtypeId:     subtypeId,
      categoryId:    cat.name,     amount:        amount,
      probableAmt:   probableAmt,  isGoods:       isGoods,
      qtyStr:        qtyStr,       rows:          rows,
      paymentMethod: paymentMethod,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// MODERN RECEIPT — UBL-inspired: gradient header, clean white body
// ════════════════════════════════════════════════════════════════════════════════

Future<Uint8List> _buildModernReceipt(
  _ReceiptPdfData data,
  pw.MemoryImage? logo,
  DonationCategory cat,
) async {
  final pdf       = pw.Document();
  final accent    = cat.pdfAccent;
  final accentDark = cat.pdfAccentDark;
  final accentMid  = cat.pdfAccentMid;

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin:     pw.EdgeInsets.zero,
    build:      (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [

        // ── GRADIENT HEADER (UBL-style) ──────────────────────────────────
        pw.Container(
          width:   double.infinity,
          padding: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [accentDark, accentMid],
              begin:  pw.Alignment.centerLeft,
              end:    pw.Alignment.centerRight,
            ),
            borderRadius: const pw.BorderRadius.only(
              bottomLeft:  pw.Radius.circular(0),
              bottomRight: pw.Radius.circular(0),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Org name row
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null) ...[
                    pw.Container(
                      width: 38, height: 38,
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        color:        PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Image(logo),
                    ),
                    pw.SizedBox(width: 10),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'GULZAR MADINA WELFARE FOUNDATION',
                          style: pw.TextStyle(
                            fontSize:   13,
                            fontWeight: pw.FontWeight.bold,
                            color:      PdfColors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (data.branchName.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            data.branchName,
                            style: pw.TextStyle(
                              fontSize: 9,
                              color:    const PdfColor(1, 1, 1, 0.75),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              // Donation label
              pw.Text(
                'Donation Receipt',
                style: pw.TextStyle(
                  fontSize:   20,
                  fontWeight: pw.FontWeight.bold,
                  color:      PdfColors.white,
                  letterSpacing: -0.3,
                ),
              ),
              pw.SizedBox(height: 4),
              // Date + Receipt row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    data.dateStr,
                    style: pw.TextStyle(fontSize: 9, color: const PdfColor(1, 1, 1, 0.75)),
                  ),
                  pw.Text(
                    data.receiptNo,
                    style: pw.TextStyle(
                      fontSize:   9,
                      color:      const PdfColor(1, 1, 1, 0.75),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── WHITE BODY ───────────────────────────────────────────────────
        pw.Expanded(
          child: pw.Container(
            color: PdfColors.white,
            padding: const pw.EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [

                // Perforated separator (dots between header & body)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 14),
                  child: pw.Row(
                    children: List.generate(
                      58,
                      (i) => pw.Expanded(
                        child: pw.Container(
                          height: 1,
                          color: i.isEven ? PdfColors.grey300 : PdfColors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── AMOUNT BLOCK ─────────────────────────────────────────
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          data.isGoods ? 'GOODS DONATED' : 'AMOUNT DONATED',
                          style: pw.TextStyle(
                            fontSize:      8,
                            color:         PdfColors.grey500,
                            fontWeight:    pw.FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          data.isGoods
                              ? (data.goodsItem.isNotEmpty ? data.goodsItem : 'Goods')
                              : 'PKR ${fmtAmt(data.amount)}',
                          style: pw.TextStyle(
                            fontSize:   data.isGoods ? 18 : 26,
                            fontWeight: pw.FontWeight.bold,
                            color:      accent,
                          ),
                        ),
                        if (data.isGoods && data.qtyStr.isNotEmpty)
                          pw.Text(
                            data.qtyStr,
                            style: pw.TextStyle(
                              fontSize: 13,
                              color:    accent,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (data.isGoods && data.probableAmt != null)
                          pw.Text(
                            'Est. PKR ${fmtAmt(data.probableAmt!)}',
                            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                          ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'STATUS',
                          style: pw.TextStyle(
                            fontSize:   7,
                            color:      PdfColors.grey400,
                            letterSpacing: 1,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: pw.BoxDecoration(
                            color:        const PdfColor.fromInt(0xFFD1FAE5),
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(
                            'RECEIVED',
                            style: pw.TextStyle(
                              fontSize:      8,
                              color:         const PdfColor.fromInt(0xFF047857),
                              fontWeight:    pw.FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Thin divider
                pw.Container(
                  height: 0.8,
                  margin: const pw.EdgeInsets.symmetric(vertical: 14),
                  color:  PdfColors.grey200,
                ),

                // ── TRANSACTION DETAILS TABLE ────────────────────────────
                pw.Text(
                  'TRANSACTION DETAILS',
                  style: pw.TextStyle(
                    fontSize:      7.5,
                    color:         PdfColors.grey500,
                    fontWeight:    pw.FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 6),

                pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2.2),
                    1: const pw.FlexColumnWidth(3.8),
                  },
                  children: data.rows.asMap().entries.map((e) {
                    final i   = e.key;
                    final row = e.value;
                    final isLast = i == data.rows.length - 1;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: i.isEven
                            ? const PdfColor.fromInt(0xFFF9FAFB)
                            : PdfColors.white,
                        border: pw.Border(
                          top: i == 0
                              ? const pw.BorderSide(
                                  color: PdfColors.grey200, width: 0.5)
                              : pw.BorderSide.none,
                          bottom: const pw.BorderSide(
                              color: PdfColors.grey200, width: 0.5),
                        ),
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              vertical: 8, horizontal: 8),
                          child: pw.Text(
                            row[0],
                            style: pw.TextStyle(
                              fontSize:   9,
                              color:      PdfColors.grey600,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              vertical: 8, horizontal: 8),
                          child: pw.Text(
                            row[1],
                            style: pw.TextStyle(
                              fontSize:   i == 0 ? 11 : 10,
                              color:      i == 0
                                  ? accent
                                  : PdfColors.grey800,
                              fontWeight: i == 0
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),

                // ── NOTES (if any) ───────────────────────────────────────
                if (data.notes.isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width:   double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color:        const PdfColor.fromInt(0xFFF9FAFB),
                      borderRadius: pw.BorderRadius.circular(4),
                      border:       pw.Border.all(
                          color: PdfColors.grey200, width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'REMARKS',
                          style: pw.TextStyle(
                            fontSize:   7,
                            color:      PdfColors.grey400,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          data.notes,
                          style: pw.TextStyle(
                            fontSize:  9,
                            color:     PdfColors.grey700,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── CATEGORY-SPECIFIC DUA ────────────────────────────────
                if (cat == DonationCategory.jamia) ...[
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width:   double.infinity,
                    padding: const pw.EdgeInsets.all(9),
                    decoration: pw.BoxDecoration(
                      color:        cat.pdfLight,
                      borderRadius: pw.BorderRadius.circular(4),
                      border:       pw.Border.all(
                          color: accent,
                          width: 0.5),
                    ),
                    child: pw.Text(
                      '"Whoever builds a masjid for the sake of Allah, Allah will build for him a house in Jannah."  - Sahih Bukhari',
                      style: pw.TextStyle(
                        fontSize:  8,
                        color:     accent,
                        fontStyle: pw.FontStyle.italic,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],

                pw.Spacer(),

                // ── AUTHORISED SIGNATORY ─────────────────────────────────
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.fromLTRB(12, 8, 44, 8),
                      decoration: pw.BoxDecoration(
                        border:       pw.Border.all(
                            color: PdfColors.grey300, width: 0.8),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Column(children: [
                        pw.Text(
                          'AUTHORISED SIGNATORY',
                          style: pw.TextStyle(
                            fontSize:      7,
                            color:         accent,
                            fontWeight:    pw.FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 20),
                        pw.Container(
                            width: 90, height: 0.5,
                            color: PdfColors.grey400),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Signature',
                          style: pw.TextStyle(
                              fontSize: 7, color: PdfColors.grey400),
                        ),
                      ]),
                    ),
                    // Print timestamp (bottom-right, small)
                    pw.Text(
                      'Printed: ${data.printedAt}',
                      style: pw.TextStyle(
                          fontSize: 7, color: PdfColors.grey400),
                    ),
                  ],
                ),

                pw.SizedBox(height: 14),

                // ── FOOTER ───────────────────────────────────────────────
                pw.Container(
                  width:   double.infinity,
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 10, horizontal: 0),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(
                          color: PdfColors.grey200, width: 0.5),
                    ),
                  ),
                  child: pw.Text(
                    'Thank you for your generous contribution. '
                    'May Allah reward you abundantly. JazakAllah Khair.',
                    style: pw.TextStyle(
                      fontSize:   8,
                      color:      accent,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ));

  return pdf.save();
}

// ════════════════════════════════════════════════════════════════════════════════
// PAYMENT METHOD SELECTOR WIDGET
// ════════════════════════════════════════════════════════════════════════════════

class DSPaymentMethodSelector extends StatelessWidget {
  final PaymentMethod               selected;
  final ValueChanged<PaymentMethod> onChanged;
  final Color                       accentColor;

  const DSPaymentMethodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Wrap(
      spacing:    8,
      runSpacing: 8,
      children: PaymentMethod.values.map((pm) {
        final isSel = pm == selected;
        return GestureDetector(
          onTap: () => onChanged(pm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color:        isSel ? accentColor.withOpacity(0.10) : t.bgCardAlt,
              borderRadius: BorderRadius.circular(DS.rMd),
              border:       Border.all(
                color: isSel ? accentColor : t.bgRule,
                width: isSel ? 1.5 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(pm.icon,
                  size:  13,
                  color: isSel ? accentColor : t.textTertiary),
              const SizedBox(width: 6),
              Text(
                pm.label,
                style: DS.label(
                        color: isSel ? accentColor : t.textTertiary)
                    .copyWith(
                        letterSpacing: 0.3,
                        fontSize:      11,
                        fontWeight:    isSel
                            ? FontWeight.w700
                            : FontWeight.w500),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// SHARED FLUTTER WIDGETS
// ════════════════════════════════════════════════════════════════════════════════

/// Banking-grade labelled text field.
class DSField extends StatelessWidget {
  final TextEditingController      controller;
  final String                     label;
  final String                     hint;
  final IconData                   icon;
  final Color                      accentColor;
  final TextInputType?             keyboardType;
  final List<TextInputFormatter>?  formatters;
  final String? Function(String?)? validator;
  final int                        maxLines;
  final TextCapitalization         textCapitalization;
  final TextInputAction?           textInputAction;

  const DSField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.accentColor,
    this.keyboardType,
    this.formatters,
    this.validator,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.words,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label.toUpperCase(), style: DS.label(color: t.textTertiary)),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller:           controller,
          keyboardType:         keyboardType,
          inputFormatters:      formatters,
          validator:            validator,
          maxLines:             maxLines,
          textCapitalization:   textCapitalization,
          textInputAction:      textInputAction,
          autocorrect:          false,
          enableSuggestions:    keyboardType == TextInputType.name ||
                                keyboardType == null,
          style: DS.body(color: t.textPrimary)
              .copyWith(fontWeight: FontWeight.w500, fontSize: 15),
          decoration: InputDecoration(
            hintText:   hint,
            hintStyle:  DS.body(color: t.textTertiary),
            prefixIcon: Icon(icon, color: accentColor, size: 18),
            filled:     true,
            fillColor:  t.bgCardAlt,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DS.rMd),
                borderSide: BorderSide(color: t.bgRule)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DS.rMd),
                borderSide: BorderSide(color: t.bgRule)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DS.rMd),
                borderSide: BorderSide(color: accentColor, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DS.rMd),
                borderSide: BorderSide(color: t.danger)),
            errorStyle:     DS.caption(color: t.danger),
            contentPadding: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 16),
          ),
        ),
      ],
    );
  }
}

/// Compact subtype selector row.
class DSSubtypeSelector extends StatelessWidget {
  final List<DonationSubtype>         subtypes;
  final DonationSubtype               selected;
  final ValueChanged<DonationSubtype> onChanged;

  const DSSubtypeSelector({
    super.key,
    required this.subtypes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: subtypes.map((st) {
        final isSel = st == selected;
        return GestureDetector(
          onTap: () => onChanged(st),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSel ? st.color.withOpacity(0.12) : t.bgCardAlt,
              borderRadius: BorderRadius.circular(DS.rMd),
              border: Border.all(
                color: isSel ? st.color : t.bgRule,
                width: isSel ? 1.5 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(st.icon, size: 13, color: isSel ? st.color : t.textTertiary),
              const SizedBox(width: 6),
              Text(
                st.label,
                style: DS.label(color: isSel ? st.color : t.textTertiary)
                    .copyWith(letterSpacing: 0.4, fontSize: 11),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

/// Status badge.
class DSStatusBadge extends StatelessWidget {
  final String status;
  const DSStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isPending  = status == kStatusPending;
    final isApproved = status == kStatusApproved;
    final color = isPending  ? DS.statusPending
        : isApproved ? DS.statusApproved
        : DS.statusRejected;
    final bg    = isPending  ? DS.gold100
        : isApproved ? DS.emerald100
        : const Color(0xFFFEE2E2);
    final lbl   = isPending  ? 'PENDING'
        : isApproved ? 'APPROVED'
        : 'REJECTED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Text(lbl, style: DS.label(color: color).copyWith(fontSize: 9)),
    );
  }
}

/// Subtype badge.
class DSSubtypeBadge extends StatelessWidget {
  final DonationSubtype subtype;
  const DSSubtypeBadge({super.key, required this.subtype});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: subtype.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(DS.rSm),
        border: Border.all(color: subtype.color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(subtype.icon, size: 10, color: subtype.color),
        const SizedBox(width: 4),
        Text(subtype.label,
            style: DS.label(color: subtype.color)
                .copyWith(fontSize: 9, letterSpacing: 0.3)),
      ]),
    );
  }
}

/// Direct action tile.
class DSActionButton extends StatelessWidget {
  final IconData?    icon;
  final String?      assetImage;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  final bool         disabled;

  const DSActionButton({
    super.key,
    this.icon,
    this.assetImage,
    required this.label,
    required this.color,
    required this.onTap,
    this.disabled = false,
  }) : assert(icon != null || assetImage != null);

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final c = disabled ? t.textTertiary : color;
    final Widget iconW = assetImage != null
        ? ColorFiltered(
            colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
            child: Image.asset(assetImage!, width: 13, height: 13))
        : Icon(icon!, size: 13, color: c);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: disabled ? t.bgCardAlt : color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(DS.rSm),
          border: Border.all(
              color: disabled ? t.bgRule : color.withOpacity(0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          iconW,
          const SizedBox(width: 5),
          Text(label,
              style: DS.label(color: c)
                  .copyWith(letterSpacing: 0.3, fontSize: 11)),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════════

String fmtNum(double v) => NumberFormat('#,##0', 'en_US').format(v);

String fmtAmt(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

String _prettyDate(String? raw) {
  try {
    return DateFormat('dd MMM yyyy').format(DateTime.parse(raw ?? ''));
  } catch (_) {
    return raw ?? '';
  }
}

pw.Widget _metaCell(String label, String value, PdfColor accent) =>
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500,
                  fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 10, color: accent,
                  fontWeight: pw.FontWeight.bold)),
        ]));