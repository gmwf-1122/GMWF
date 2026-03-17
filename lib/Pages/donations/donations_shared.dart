// lib/pages/donations/donations_shared.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN SYSTEM
// ─────────────────────────────────────────────────────────────────────────────

class DS {
  // Navy palette
  static const navy900 = Color(0xFF0B1426);
  static const navy800 = Color(0xFF112244);
  static const navy700 = Color(0xFF163567);
  static const navy600 = Color(0xFF1B4280);
  static const navy100 = Color(0xFFE8EEF7);

  // Emerald
  static const emerald700 = Color(0xFF065F46);
  static const emerald600 = Color(0xFF047857);
  static const emerald500 = Color(0xFF059669);
  static const emerald100 = Color(0xFFD1FAE5);

  // Sapphire
  static const sapphire700 = Color(0xFF1E3A8A);
  static const sapphire500 = Color(0xFF3B82F6);
  static const sapphire100 = Color(0xFFDBEAFE);

  // Plum
  static const plum700 = Color(0xFF6B21A8);
  static const plum500 = Color(0xFFA855F7);
  static const plum100 = Color(0xFFF3E8FF);

  // Gold
  static const gold700 = Color(0xFF92400E);
  static const gold600 = Color(0xFFB45309);
  static const gold500 = Color(0xFFD97706);
  static const gold400 = Color(0xFFFBBF24);
  static const gold100 = Color(0xFFFEF3C7);

  // Crimson
  static const crimson700 = Color(0xFF9B1C1C);
  static const crimson500 = Color(0xFFEF4444);
  static const crimson100 = Color(0xFFFEE2E2);

  // Status
  static const statusPending  = Color(0xFFD97706);
  static const statusApproved = Color(0xFF059669);
  static const statusRejected = Color(0xFFDC2626);

  // Ink (neutral)
  static const ink900 = Color(0xFF111827);
  static const ink700 = Color(0xFF374151);
  static const ink500 = Color(0xFF6B7280);
  static const ink300 = Color(0xFFD1D5DB);
  static const ink200 = Color(0xFFE5E7EB);
  static const ink100 = Color(0xFFF3F4F6);
  static const ink50  = Color(0xFFF9FAFB);

  // Shadows
  static List<BoxShadow> get shadowSm => [
    const BoxShadow(color: Color(0x0C000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
  static List<BoxShadow> get shadowMd => [
    const BoxShadow(color: Color(0x10000000), blurRadius: 16, offset: Offset(0, 4)),
    const BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static List<BoxShadow> get shadowLg => [
    const BoxShadow(color: Color(0x16000000), blurRadius: 32, offset: Offset(0, 8)),
    const BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  // Radii
  static const rSm  = 6.0;
  static const rMd  = 10.0;
  static const rLg  = 14.0;
  static const rXl  = 18.0;
  static const r2xl = 24.0;

  // Text styles
  static TextStyle display({Color color = ink900}) => TextStyle(
      fontSize: 24, fontWeight: FontWeight.w800, color: color,
      letterSpacing: -0.8, height: 1.15);
  static TextStyle heading({Color color = ink900}) => TextStyle(
      fontSize: 17, fontWeight: FontWeight.w700, color: color,
      letterSpacing: -0.3);
  static TextStyle subheading({Color color = ink700}) =>
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color);
  static TextStyle body({Color color = ink700}) =>
      TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: color);
  static TextStyle label({Color color = ink500}) => TextStyle(
      fontSize: 10, fontWeight: FontWeight.w700, color: color,
      letterSpacing: 0.9);
  static TextStyle caption({Color color = ink500}) =>
      TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color);
  static TextStyle mono({Color color = ink900, double size = 20}) => TextStyle(
      fontSize: size, fontWeight: FontWeight.w800, color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: -0.4);
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const String kStatusPending  = 'pending';
const String kStatusApproved = 'approved';
const String kStatusRejected = 'rejected';

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT METHOD  (no online transfer — bank deposit covers it)
// ─────────────────────────────────────────────────────────────────────────────

enum PaymentMethod { cash, cheque, bankDeposit }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:        return 'Cash';
      case PaymentMethod.cheque:      return 'Cheque';
      case PaymentMethod.bankDeposit: return 'Bank Deposit';
    }
  }
  IconData get icon {
    switch (this) {
      case PaymentMethod.cash:        return Icons.payments_rounded;
      case PaymentMethod.cheque:      return Icons.description_rounded;
      case PaymentMethod.bankDeposit: return Icons.account_balance_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BRANCH HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String branchCodeFor(String branchId) {
  final id = branchId.toLowerCase().trim();
  if (id.contains('gujrat'))     return 'grt';
  if (id.contains('jalalpur'))   return 'jpt';
  if (id.contains('karachi-1') || id == 'karachi1') return 'khi1';
  if (id.contains('karachi-2') || id == 'karachi2') return 'khi2';
  if (id.contains('rawalpindi')) return 'rwp';
  if (id.contains('sialkot'))    return 'skt';
  if (id.contains('lahore') || id == 'lhr') return 'lhr';
  return id.length >= 3 ? id.substring(0, 3) : id;
}

String buildReceiptNumber(String branchId, int seq) {
  final code    = branchCodeFor(branchId);
  final dateStr = DateFormat('ddMMyy').format(DateTime.now());
  final seqStr  = seq.toString().padLeft(3, '0');
  return '$code-$dateStr-$seqStr';
}

// ─────────────────────────────────────────────────────────────────────────────
// EXTENSIONS
// ─────────────────────────────────────────────────────────────────────────────

extension IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}

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

// ─────────────────────────────────────────────────────────────────────────────
// DONATION CATEGORIES
// ─────────────────────────────────────────────────────────────────────────────

enum DonationCategory { jamia, gmwf }

extension DonationCategoryX on DonationCategory {
  String get label {
    switch (this) {
      case DonationCategory.jamia: return 'Jamia / Masjid';
      case DonationCategory.gmwf:  return 'GMWF';
    }
  }
  String get shortLabel {
    switch (this) {
      case DonationCategory.jamia: return 'Jamia';
      case DonationCategory.gmwf:  return 'GMWF';
    }
  }
  IconData get icon {
    switch (this) {
      case DonationCategory.jamia: return Icons.mosque_rounded;
      case DonationCategory.gmwf:  return Icons.volunteer_activism_rounded;
    }
  }
  Color get color {
    switch (this) {
      case DonationCategory.jamia: return DS.sapphire700;
      case DonationCategory.gmwf:  return DS.emerald600;
    }
  }
  Color get lightColor {
    switch (this) {
      case DonationCategory.jamia: return DS.sapphire100;
      case DonationCategory.gmwf:  return DS.emerald100;
    }
  }
  List<Color> get gradient {
    switch (this) {
      case DonationCategory.jamia: return [DS.sapphire700, DS.sapphire500];
      case DonationCategory.gmwf:  return [DS.emerald700, DS.emerald500];
    }
  }
  PdfColor get pdfPrimary {
    switch (this) {
      case DonationCategory.jamia: return const PdfColor(0.118, 0.227, 0.541);
      case DonationCategory.gmwf:  return const PdfColor(0.016, 0.471, 0.341);
    }
  }
  PdfColor get pdfDark {
    switch (this) {
      case DonationCategory.jamia: return const PdfColor(0.043, 0.122, 0.361);
      case DonationCategory.gmwf:  return const PdfColor(0.024, 0.373, 0.275);
    }
  }
  PdfColor get pdfLight {
    switch (this) {
      case DonationCategory.jamia: return const PdfColor(0.859, 0.918, 0.996);
      case DonationCategory.gmwf:  return const PdfColor(0.820, 0.980, 0.898);
    }
  }
  String get pdfCategoryFullLabel {
    switch (this) {
      case DonationCategory.jamia: return 'Jamia / Masjid Fund';
      case DonationCategory.gmwf:  return 'GMWF General Fund';
    }
  }
  // compat aliases
  PdfColor get pdfAccent     => pdfPrimary;
  PdfColor get pdfAccentDark => pdfDark;
  PdfColor get pdfAccentMid  => pdfPrimary;
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY TYPE  (Cash / Goods)
// ─────────────────────────────────────────────────────────────────────────────

enum DonationEntryType { cash, goods }

extension DonationEntryTypeX on DonationEntryType {
  bool get isGoods => this == DonationEntryType.goods;
  String get label =>
      this == DonationEntryType.cash ? 'Cash' : 'Goods / Ajnas';
  IconData get icon => this == DonationEntryType.cash
      ? Icons.payments_rounded
      : Icons.inventory_2_rounded;
}

// ─────────────────────────────────────────────────────────────────────────────
// GMWF SUB-CATEGORY
// ─────────────────────────────────────────────────────────────────────────────

enum GmwfSubCategory { dasterkhwaan, dispensary, madrisa, general }

extension GmwfSubCategoryX on GmwfSubCategory {
  String get label {
    switch (this) {
      case GmwfSubCategory.dasterkhwaan: return 'Dasterkhwaan';
      case GmwfSubCategory.dispensary:   return 'Dispensary';
      case GmwfSubCategory.madrisa:      return 'Madrisa';
      case GmwfSubCategory.general:      return 'General';
    }
  }
  IconData get icon {
    switch (this) {
      case GmwfSubCategory.dasterkhwaan: return Icons.restaurant_rounded;
      case GmwfSubCategory.dispensary:   return Icons.local_hospital_rounded;
      case GmwfSubCategory.madrisa:      return Icons.school_rounded;
      case GmwfSubCategory.general:      return Icons.volunteer_activism_rounded;
    }
  }
  Color get color {
    switch (this) {
      case GmwfSubCategory.dasterkhwaan: return DS.gold600;
      case GmwfSubCategory.dispensary:   return DS.crimson500;
      case GmwfSubCategory.madrisa:      return DS.plum700;
      case GmwfSubCategory.general:      return DS.emerald600;
    }
  }
  Color get lightColor {
    switch (this) {
      case GmwfSubCategory.dasterkhwaan: return DS.gold100;
      case GmwfSubCategory.dispensary:   return DS.crimson100;
      case GmwfSubCategory.madrisa:      return DS.plum100;
      case GmwfSubCategory.general:      return DS.emerald100;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DONATION SUBTYPES
// ─────────────────────────────────────────────────────────────────────────────

enum DonationSubtype {
  construction, maintenance, iftar,
  zakat, sadqaWajiba, sadqaAtyaat, general,
}

extension DonationSubtypeX on DonationSubtype {
  String get label {
    switch (this) {
      case DonationSubtype.construction: return 'Construction';
      case DonationSubtype.maintenance:  return 'Maintenance';
      case DonationSubtype.iftar:        return 'Iftar';
      case DonationSubtype.zakat:        return 'Zakat';
      case DonationSubtype.sadqaWajiba:  return 'Sadqa Wajiba';
      case DonationSubtype.sadqaAtyaat:  return 'Sadqa / Atyaat';
      case DonationSubtype.general:      return 'General';
    }
  }
  IconData get icon {
    switch (this) {
      case DonationSubtype.construction: return Icons.construction_rounded;
      case DonationSubtype.maintenance:  return Icons.build_circle_rounded;
      case DonationSubtype.iftar:        return Icons.dinner_dining_rounded;
      case DonationSubtype.zakat:        return Icons.account_balance_rounded;
      case DonationSubtype.sadqaWajiba:  return Icons.star_rounded;
      case DonationSubtype.sadqaAtyaat:  return Icons.favorite_rounded;
      case DonationSubtype.general:      return Icons.circle_outlined;
    }
  }
  Color get color {
    switch (this) {
      case DonationSubtype.construction: return DS.sapphire700;
      case DonationSubtype.maintenance:  return DS.sapphire500;
      case DonationSubtype.iftar:        return DS.gold600;
      case DonationSubtype.zakat:        return DS.emerald700;
      case DonationSubtype.sadqaWajiba:  return const Color(0xFFDB2777);
      case DonationSubtype.sadqaAtyaat:  return DS.plum700;
      case DonationSubtype.general:      return DS.ink500;
    }
  }
}

/// Returns applicable cash subtypes for given category + optional gmwfSub.
/// Empty list for goods.
List<DonationSubtype> subtypesFor({
  required DonationCategory  category,
  required DonationEntryType entryType,
  GmwfSubCategory?           gmwfSub,
}) {
  if (entryType.isGoods) return [];
  switch (category) {
    case DonationCategory.jamia:
      return [
        DonationSubtype.construction,
        DonationSubtype.maintenance,
        DonationSubtype.iftar,
        DonationSubtype.general,
      ];
    case DonationCategory.gmwf:
      if (gmwfSub == GmwfSubCategory.general) {
        return [
          DonationSubtype.zakat,
          DonationSubtype.sadqaWajiba,
          DonationSubtype.sadqaAtyaat,
        ];
      }
      return [DonationSubtype.sadqaAtyaat];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kUnits = [
  'kg', 'gram', 'liter', 'piece', 'packet', 'maund', 'quintal',
];

// ─────────────────────────────────────────────────────────────────────────────
// MESSAGING HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String buildThankYouMessage({
  required String           donorName,
  required String           receiptNo,
  required DonationCategory category,
  required double           amount,
  required String           unit,
  required String           branchName,
  DonationSubtype?          subtype,
  GmwfSubCategory?          gmwfSub,
  String                    paymentMethod = 'Cash',
  bool                      isGoods       = false,
}) {
  final dateStr = DateFormat('dd MMM yyyy').format(DateTime.now());
  final orgLine = branchName.trim().isNotEmpty
      ? 'Gulzar Madina Welfare Foundation - $branchName'
      : 'Gulzar Madina Welfare Foundation';
  final amtLine = isGoods
      ? '${amount % 1 == 0 ? amount.toInt() : amount} $unit'
      : 'PKR ${NumberFormat('#,##0', 'en_US').format(amount)}';
  String typeLabel = category.label;
  if (gmwfSub != null) typeLabel += ' – ${gmwfSub.label}';
  if (subtype != null) typeLabel += ' (${subtype.label})';

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
      'For queries, contact the GMWF office directly.\n'
      '_Gulzar Madina Welfare Foundation_';
}

Future<void> sendSmsThankYou(
  String phone, String donorName, DonationCategory category,
  double amount, String unit, String receiptNo, String branchName, {
  DonationSubtype? subtype, GmwfSubCategory? gmwfSub,
  String paymentMethod = 'Cash', bool isGoods = false,
}) async {
  final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.isEmpty) return;
  final body = buildThankYouMessage(
    donorName: donorName, receiptNo: receiptNo, category: category,
    amount: amount, unit: unit, branchName: branchName,
    subtype: subtype, gmwfSub: gmwfSub,
    paymentMethod: paymentMethod, isGoods: isGoods,
  );
  final uri = Uri(scheme: 'sms', path: clean, queryParameters: {'body': body});
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

Future<void> shareReceiptWhatsApp(
  Map<String, dynamic> d, String receiptNo, String phone, String branchName,
) async {
  final recordPhone    = (d['phone'] as String? ?? '').trim();
  final effectivePhone = recordPhone.isNotEmpty ? recordPhone : phone.trim();
  if (effectivePhone.isEmpty) return;

  String clean = effectivePhone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.startsWith('0')) {
    clean = '+92${clean.substring(1)}';
  } else if (clean.startsWith('92') && !clean.startsWith('+')) {
    clean = '+$clean';
  } else if (!clean.startsWith('+')) {
    clean = '+92$clean';
  }

  final donorName   = d['donorName']  as String? ?? '';
  final categoryId  = d['categoryId'] as String? ?? '';
  final cat         = DonationCategory.values
      .firstWhere((c) => c.name == categoryId, orElse: () => DonationCategory.gmwf);
  final subtypeId   = d['subtypeId']  as String?;
  final subtype     = subtypeId != null
      ? DonationSubtype.values.firstWhereOrNull((s) => s.name == subtypeId) : null;
  final gmwfSubId   = d['gmwfSubCategoryId'] as String?;
  final gmwfSub     = gmwfSubId != null
      ? GmwfSubCategory.values.firstWhereOrNull((s) => s.name == gmwfSubId) : null;
  final amount      = (d['amount'] as num?)?.toDouble() ?? 0.0;
  final unit        = d['unit'] as String? ?? 'PKR';
  final payMethod   = d['paymentMethod'] as String? ?? 'Cash';
  final isGoods     = (d['entryType'] as String? ?? '') == 'goods';

  final caption = buildThankYouMessage(
    donorName: donorName, receiptNo: receiptNo, category: cat,
    amount: amount, unit: unit, branchName: branchName,
    subtype: subtype, gmwfSub: gmwfSub,
    paymentMethod: payMethod, isGoods: isGoods,
  );

  final waNumber    = clean.replaceAll('+', '');
  final encodedText = Uri.encodeComponent(caption);
  final waUri       = Uri.parse('https://wa.me/$waNumber?text=$encodedText');

  if (await canLaunchUrl(waUri)) {
    await launchUrl(waUri, mode: LaunchMode.externalApplication);
    return;
  }
  try {
    await Share.share(caption, subject: 'Donation Receipt - $receiptNo');
  } catch (_) {}
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF
// ─────────────────────────────────────────────────────────────────────────────

Future<void> printReceiptPdf(Map<String, dynamic> d, String receiptNo) async {
  await Printing.layoutPdf(
      onLayout: (_) => buildReceiptPdf(d, receiptNo, PdfPageFormat.a5));
}

Future<void> downloadReceiptPdf(
    Map<String, dynamic> d, String receiptNo, BuildContext context) async {
  try {
    final bytes = await buildReceiptPdf(d, receiptNo, PdfPageFormat.a5);
    await Printing.sharePdf(bytes: bytes, filename: 'receipt_$receiptNo.pdf');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download failed: $e',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: DS.statusRejected,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rMd)),
      ));
    }
  }
}

Future<Uint8List> buildReceiptPdf(
    Map<String, dynamic> d, String receiptNo, PdfPageFormat format) async {
  final categoryId = (d['categoryId'] as String? ?? '').trim();
  final cat = DonationCategory.values
      .firstWhere((c) => c.name == categoryId, orElse: () => DonationCategory.gmwf);

  final donorName     = (d['donorName']  as String? ?? 'Valued Donor').trim();
  final phone         = (d['phone']      as String? ?? '').trim();
  final branchName    = (d['branchName'] as String? ?? 'GMWF Branch').trim();
  final recordedBy    = ((d['recordedBy'] as String?)?.trim().isNotEmpty == true
      ? d['recordedBy'] as String : 'Authorized Staff');
  final paymentMethod = (d['paymentMethod'] as String? ?? 'Cash').trim();
  final notes         = (d['notes']        as String? ?? '').trim();
  final subtypeId     = (d['subtypeId']    as String? ?? '').trim();
  final gmwfSubId     = (d['gmwfSubCategoryId'] as String? ?? '').trim();
  final goodsItem     = (d['goodsItem']    as String? ?? '').trim();
  final unit          = (d['unit']         as String? ?? '').trim();
  final rawDate       = d['date'] as String?;
  final isGoods       = (d['entryType'] as String? ?? '') == 'goods';

  double amount = 0.0;
  final rawAmt = d['amount'];
  if (rawAmt is num) amount = rawAmt.toDouble();
  if (rawAmt is String) amount = double.tryParse(rawAmt) ?? 0.0;

  double? probAmt;
  final rawProb = d['probableAmount'];
  if (rawProb is num) probAmt = rawProb.toDouble();
  if (rawProb is String) probAmt = double.tryParse(rawProb);

  String subtypeLabel = '';
  if (subtypeId.isNotEmpty) {
    final st = DonationSubtype.values.firstWhereOrNull((s) => s.name == subtypeId);
    subtypeLabel = st?.label ?? subtypeId;
  }
  String gmwfSubLabel = '';
  if (gmwfSubId.isNotEmpty) {
    final gs = GmwfSubCategory.values.firstWhereOrNull((s) => s.name == gmwfSubId);
    gmwfSubLabel = gs?.label ?? gmwfSubId;
  }

  final dateDisplay  = _fmtDate(rawDate);
  final amountDisplay = isGoods
      ? '${amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(2)} $unit'
      : 'PKR ${_fmtNum(amount)}';

  pw.MemoryImage? logo, qrAnjuman, qrGm;
  try {
    final b = await rootBundle.load('assets/logo/gmwf.png');
    logo = pw.MemoryImage(b.buffer.asUint8List());
  } catch (_) {}
  try {
    final b = await rootBundle.load('assets/qr/anjuman.png');
    qrAnjuman = pw.MemoryImage(b.buffer.asUint8List());
  } catch (_) {}
  try {
    final b = await rootBundle.load('assets/qr/gm.png');
    qrGm = pw.MemoryImage(b.buffer.asUint8List());
  } catch (_) {}

  final accent   = cat.pdfPrimary;
  final accentDk = cat.pdfDark;
  final accentLt = cat.pdfLight;
  final cWhite   = PdfColors.white;
  final cInkDark = PdfColor.fromInt(0xFF0F172A);
  final cInkGrey = PdfColor.fromInt(0xFF94A3B8);
  final cRule    = PdfColor.fromInt(0xFFE2E8F0);
  final cPageBg  = PdfColor(accentLt.red, accentLt.green, accentLt.blue, 0.35);

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin:     pw.EdgeInsets.zero,
    build: (_) => pw.Container(
      color: cPageBg,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.max,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: pw.Column(children: [
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (logo != null)
                  pw.Container(
                    width: 52, height: 52,
                    decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(12)),
                    child: pw.ClipRRect(horizontalRadius: 12, verticalRadius: 12,
                        child: pw.Image(logo, fit: pw.BoxFit.cover)),
                  )
                else
                  pw.Container(
                    width: 44, height: 44,
                    decoration: pw.BoxDecoration(
                      gradient: pw.LinearGradient(colors: [accentDk, accent]),
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Center(child: pw.Text('G',
                        style: pw.TextStyle(fontSize: 28, color: cWhite,
                            fontWeight: pw.FontWeight.bold))),
                  ),
                pw.SizedBox(width: 16),
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GULZAR MADINA', style: pw.TextStyle(fontSize: 14,
                        fontWeight: pw.FontWeight.bold, color: cInkDark, letterSpacing: 0.5)),
                    pw.SizedBox(height: 2),
                    pw.Text('WELFARE FOUNDATION', style: pw.TextStyle(fontSize: 11,
                        fontWeight: pw.FontWeight.bold, color: accent, letterSpacing: 1.2)),
                  ],
                )),
              ]),
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: pw.BoxDecoration(
                  gradient: pw.LinearGradient(colors: [accentDk, accent]),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('DONATION RECEIPT', style: pw.TextStyle(fontSize: 8,
                          color: const PdfColor(1, 1, 1, 0.75),
                          fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
                      pw.SizedBox(height: 4),
                      pw.Text(receiptNo, style: pw.TextStyle(fontSize: 18, color: cWhite,
                          fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
                    ]),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: pw.BoxDecoration(color: cWhite,
                          borderRadius: pw.BorderRadius.circular(8)),
                      child: pw.Text(dateDisplay, style: pw.TextStyle(fontSize: 9,
                          color: accentDk, fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          pw.Container(
            margin: const pw.EdgeInsets.fromLTRB(20, 10, 20, 0),
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: cWhite,
                borderRadius: pw.BorderRadius.circular(16)),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Expanded(child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(isGoods ? 'QUANTITY DONATED' : 'AMOUNT DONATED',
                      style: pw.TextStyle(fontSize: 8, color: cInkGrey,
                          fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                  pw.SizedBox(height: 6),
                  if (isGoods && goodsItem.isNotEmpty) ...[
                    pw.Text(goodsItem, style: pw.TextStyle(fontSize: 18, color: accent,
                        fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(amountDisplay, style: pw.TextStyle(fontSize: 24, color: accentDk,
                        fontWeight: pw.FontWeight.bold)),
                  ] else ...[
                    pw.Text(amountDisplay, style: pw.TextStyle(fontSize: 32, color: accent,
                        fontWeight: pw.FontWeight.bold)),
                  ],
                  if (isGoods && probAmt != null) ...[
                    pw.SizedBox(height: 4),
                    pw.Text('Estimated value: PKR ${_fmtNum(probAmt)}',
                        style: pw.TextStyle(fontSize: 8.5, color: accent,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ],
              )),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: pw.BoxDecoration(color: accentLt,
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: accent, width: 1.5)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text(cat.shortLabel.toUpperCase(), textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(fontSize: 9, color: accentDk,
                          fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
                  if (gmwfSubLabel.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Container(width: 30, height: 1, color: accent),
                    pw.SizedBox(height: 4),
                    pw.Text(gmwfSubLabel, textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 7.5, color: accent,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                  if (subtypeLabel.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(subtypeLabel, textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 7, color: accentDk,
                            fontStyle: pw.FontStyle.italic)),
                  ],
                ]),
              ),
            ]),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 20),
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: cWhite,
                borderRadius: pw.BorderRadius.circular(16)),
            child: pw.Column(children: [
              _pdfRow('Donor Name', donorName, cInkGrey, cInkDark),
              if (phone.isNotEmpty) ...[pw.SizedBox(height: 10),
                _pdfRow('Contact', phone, cInkGrey, cInkDark)],
              pw.SizedBox(height: 10),
              _pdfRow(isGoods ? 'Item Donated' : 'Payment Method',
                  isGoods ? goodsItem : paymentMethod, cInkGrey, cInkDark),
              pw.SizedBox(height: 10),
              _pdfRow('Date', dateDisplay, cInkGrey, cInkDark),
              pw.SizedBox(height: 10),
              pw.Container(height: 1, color: cRule),
              pw.SizedBox(height: 10),
              _pdfRow('Branch', branchName, cInkGrey, cInkDark),
              pw.SizedBox(height: 10),
              _pdfRow('Received By', recordedBy, cInkGrey, cInkDark),
            ]),
          ),
          pw.SizedBox(height: 10),
          if (notes.isNotEmpty)
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(horizontal: 20),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: accentLt,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: accent, width: 1)),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(width: 6, height: 6,
                    decoration: pw.BoxDecoration(color: accent, shape: pw.BoxShape.circle),
                    margin: const pw.EdgeInsets.only(top: 4, right: 10)),
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('NOTE', style: pw.TextStyle(fontSize: 7, color: accentDk,
                        fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
                    pw.SizedBox(height: 4),
                    pw.Text(notes, style: pw.TextStyle(fontSize: 9, color: accentDk,
                        fontStyle: pw.FontStyle.italic)),
                  ],
                )),
              ]),
            ),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(colors: [
                accentLt, PdfColor(accentLt.red, accentLt.green, accentLt.blue, 0.5),
              ]),
            ),
            child: pw.Center(child: pw.Text(
                'JazakAllah Khair - May Allah accept your generous donation',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 9, color: accentDk,
                    fontWeight: pw.FontWeight.bold, fontStyle: pw.FontStyle.italic))),
          ),
          pw.Container(
            color: accentDk,
            padding: const pw.EdgeInsets.all(14),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Expanded(child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Gulzar Madina Welfare Foundation', style: pw.TextStyle(
                      fontSize: 9, color: cWhite, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(branchName, style: pw.TextStyle(fontSize: 8,
                      color: const PdfColor(1, 1, 1, 0.7))),
                ],
              )),
              pw.SizedBox(width: 12),
              pw.Row(children: [
                if (qrAnjuman != null) _qrBlock(qrAnjuman, 'gulzarmadina.com', cWhite),
                if (qrAnjuman != null && qrGm != null) pw.SizedBox(width: 10),
                if (qrGm != null) _qrBlock(qrGm, 'gmwf.org.pk', cWhite),
                if (qrAnjuman == null && qrGm == null)
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(color: cWhite,
                          borderRadius: pw.BorderRadius.circular(8)),
                      child: pw.BarcodeWidget(
                        data: 'gmwf.org.pk/verify/$receiptNo',
                        barcode: pw.Barcode.qrCode(), width: 44, height: 44,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text('Verify Receipt', style: pw.TextStyle(fontSize: 6,
                        color: const PdfColor(1, 1, 1, 0.7), fontWeight: pw.FontWeight.bold)),
                  ]),
              ]),
            ]),
          ),
        ],
      ),
    ),
  ));
  return pdf.save();
}

pw.Widget _qrBlock(pw.MemoryImage img, String label, PdfColor cWhite) =>
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Container(
        width: 48, height: 48, padding: const pw.EdgeInsets.all(3),
        decoration: pw.BoxDecoration(color: cWhite,
            borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Image(img, fit: pw.BoxFit.contain),
      ),
      pw.SizedBox(height: 3),
      pw.Text(label, style: pw.TextStyle(fontSize: 6,
          color: const PdfColor(1, 1, 1, 0.7), fontWeight: pw.FontWeight.bold)),
    ]);

pw.Widget _pdfRow(String label, String value, PdfColor lc, PdfColor vc) =>
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 100,
          child: pw.Text(label.toUpperCase(), style: pw.TextStyle(fontSize: 7,
              color: lc, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8))),
      pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 10,
          color: vc, fontWeight: pw.FontWeight.bold))),
    ]);

String _fmtNum(double v) => NumberFormat('#,##0', 'en_US').format(v);
String _fmtDate(String? raw) {
  try { return DateFormat('dd MMM yyyy').format(DateTime.parse(raw ?? '')); }
  catch (_) { return raw ?? DateFormat('dd MMM yyyy').format(DateTime.now()); }
}

// public helpers
String fmtNum(double v) => _fmtNum(v);
String fmtAmt(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class DSField extends StatelessWidget {
  final TextEditingController      controller;
  final String                     label, hint;
  final IconData                   icon;
  final Color                      accentColor;
  final TextInputType?             keyboardType;
  final List<TextInputFormatter>?  formatters;
  final String? Function(String?)? validator;
  final int                        maxLines;
  final TextCapitalization         textCapitalization;
  final TextInputAction?           textInputAction;
  final FocusNode?                 focusNode;
  final ValueChanged<String>?      onFieldSubmitted;

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
    this.focusNode,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty) ...[
        Text(label.toUpperCase(), style: DS.label(color: t.textTertiary)
            .copyWith(fontSize: 9.5, letterSpacing: 1.0)),
        const SizedBox(height: 6),
      ],
      TextFormField(
        controller:         controller,
        focusNode:          focusNode,
        onFieldSubmitted:   onFieldSubmitted,
        keyboardType:       keyboardType,
        inputFormatters:    formatters,
        validator:          validator,
        maxLines:           maxLines,
        textCapitalization: textCapitalization,
        textInputAction:    textInputAction,
        autocorrect:        false,
        enableSuggestions:
            keyboardType == TextInputType.name || keyboardType == null,
        style: DS.body(color: t.textPrimary)
            .copyWith(fontWeight: FontWeight.w500, fontSize: 15),
        decoration: InputDecoration(
          hintText:   hint,
          hintStyle:  DS.body(color: t.textTertiary).copyWith(fontSize: 14),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
    ]);
  }
}

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
    return Wrap(spacing: 8, runSpacing: 8, children: subtypes.map((st) {
      final sel = st == selected;
      return GestureDetector(
        onTap: () => onChanged(st),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? st.color.withOpacity(0.12) : t.bgCardAlt,
            borderRadius: BorderRadius.circular(DS.rMd),
            border: Border.all(color: sel ? st.color : t.bgRule,
                width: sel ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(st.icon, size: 13, color: sel ? st.color : t.textTertiary),
            const SizedBox(width: 6),
            Text(st.label, style: DS.label(
                    color: sel ? st.color : t.textTertiary)
                .copyWith(letterSpacing: 0.3, fontSize: 11)),
          ]),
        ),
      );
    }).toList());
  }
}

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
    return Wrap(spacing: 8, runSpacing: 8, children: PaymentMethod.values.map((pm) {
      final sel = pm == selected;
      return GestureDetector(
        onTap: () => onChanged(pm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: sel ? accentColor.withOpacity(0.10) : t.bgCardAlt,
            borderRadius: BorderRadius.circular(DS.rMd),
            border: Border.all(color: sel ? accentColor : t.bgRule,
                width: sel ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(pm.icon, size: 13, color: sel ? accentColor : t.textTertiary),
            const SizedBox(width: 6),
            Text(pm.label, style: DS.label(
                    color: sel ? accentColor : t.textTertiary)
                .copyWith(letterSpacing: 0.3, fontSize: 11,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      );
    }).toList());
  }
}

class DSStatusBadge extends StatelessWidget {
  final String status;
  const DSStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isPending  = status == kStatusPending;
    final isApproved = status == kStatusApproved;
    final color = isPending ? DS.statusPending
        : isApproved ? DS.statusApproved : DS.statusRejected;
    final bg = isPending ? DS.gold100
        : isApproved ? DS.emerald100 : const Color(0xFFFEE2E2);
    final lbl = isPending ? 'PENDING' : isApproved ? 'APPROVED' : 'REJECTED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Text(lbl, style: DS.label(color: color).copyWith(fontSize: 9)),
    );
  }
}

class DSSubtypeBadge extends StatelessWidget {
  final DonationSubtype subtype;
  const DSSubtypeBadge({super.key, required this.subtype});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: subtype.color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(DS.rSm),
      border: Border.all(color: subtype.color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(subtype.icon, size: 10, color: subtype.color),
      const SizedBox(width: 4),
      Text(subtype.label, style: DS.label(color: subtype.color)
          .copyWith(fontSize: 9, letterSpacing: 0.3)),
    ]),
  );
}

class DSActionButton extends StatelessWidget {
  final IconData?    icon;
  final String?      assetImage;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  final bool         disabled;
  const DSActionButton({
    super.key, this.icon, this.assetImage,
    required this.label, required this.color,
    required this.onTap, this.disabled = false,
  }) : assert(icon != null || assetImage != null);

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final c = disabled ? t.textTertiary : color;
    final Widget iconW = assetImage != null
        ? ColorFiltered(colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
            child: Image.asset(assetImage!, width: 13, height: 13))
        : Icon(icon!, size: 13, color: c);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: disabled ? t.bgCardAlt : color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(DS.rSm),
          border: Border.all(color: disabled ? t.bgRule : color.withOpacity(0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          iconW, const SizedBox(width: 5),
          Text(label, style: DS.label(color: c)
              .copyWith(letterSpacing: 0.3, fontSize: 11)),
        ]),
      ),
    );
  }
}