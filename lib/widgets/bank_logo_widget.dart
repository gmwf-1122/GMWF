// lib/widgets/bank_logo_widget.dart

import 'package:flutter/material.dart';

class BankLogoWidget extends StatelessWidget {
  final String bankName;
  final double size;
  final bool showLabel;
  final TextStyle? labelStyle;

  const BankLogoWidget({
    super.key,
    required this.bankName,
    this.size = 24.0,
    this.showLabel = false,
    this.labelStyle,
  });

  /// Maps bank name string to local image asset path if present
  static String? getAssetForBank(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.contains('meezan')) {
      return 'assets/Banks Logos/meezan-bank-logo.webp';
    } else if (lower.contains('easypaisa') || lower.contains('easy paisa')) {
      return 'assets/Banks Logos/Easypaisa-logo.webp';
    } else if (lower.contains('jazzcash') || lower.contains('jazz cash')) {
      return 'assets/Banks Logos/jazzcash.webp';
    } else if (lower.contains('ubl') || lower.contains('united bank')) {
      return 'assets/Banks Logos/ubl-united-bank-limited-logo-png-transparent.webp';
    } else if (lower.contains('bop') || lower.contains('bank of punjab') || lower.contains('punjab')) {
      return 'assets/Banks Logos/Bank-of-punjab-Logo.webp';
    } else if (lower.contains('nbp') || lower.contains('national bank')) {
      return 'assets/Banks Logos/national-bank-of-pakistan-logo.webp';
    } else if (lower.contains('faysal')) {
      return 'assets/Banks Logos/faysal-bank-logo.webp';
    } else if (lower.contains('alfalah')) {
      return 'assets/Banks Logos/bank_alfalah.webp';
    } else if (lower.contains('hbl') || lower.contains('habib')) {
      return 'assets/Banks Logos/habib bank.webp';
    }
    return null; // Fallback to crisp brand initials badge
  }

  /// Provides brand color for initial badge fallbacks
  static Color getBrandColor(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.contains('meezan')) return const Color(0xFF501968);
    if (lower.contains('easypaisa')) return const Color(0xFF00A859);
    if (lower.contains('jazzcash')) return const Color(0xFFED1C24);
    if (lower.contains('ubl')) return const Color(0xFF00569B);
    if (lower.contains('bop')) return const Color(0xFFD32F2F);
    if (lower.contains('nbp')) return const Color(0xFF006837);
    if (lower.contains('faysal')) return const Color(0xFF003865);
    if (lower.contains('hbl')) return const Color(0xFF008375);
    if (lower.contains('mcb')) return const Color(0xFFFF6600);
    if (lower.contains('cash')) return const Color(0xFF10B981);
    return const Color(0xFF475569);
  }

  static String getBankInitials(String name) {
    final clean = name.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    if (clean.isEmpty) return 'BK';
    final parts = clean.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 3)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = getAssetForBank(bankName);
    final isCash = bankName.toLowerCase().contains('cash');

    Widget logoChild;

    if (isCash) {
      logoChild = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3), width: 1),
        ),
        child: Icon(Icons.payments_rounded, size: size * 0.58, color: const Color(0xFF10B981)),
      );
    } else if (assetPath != null) {
      logoChild = Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.22),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.18),
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildInitialsBadge(),
          ),
        ),
      );
    } else {
      logoChild = _buildInitialsBadge();
    }

    if (!showLabel) return logoChild;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,

      children: [
        logoChild,
        const SizedBox(width: 8),
        Text(
          bankName,
          style: labelStyle ??
              const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
        ),
      ],
    );
  }

  Widget _buildInitialsBadge() {
    final brandColor = getBrandColor(bankName);
    final initials = getBankInitials(bankName);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brandColor,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(color: brandColor.withOpacity(0.25), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.4,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}
