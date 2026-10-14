// lib/pages/dispensary/widgets/desk_summary_card.dart
//
// The Receptionist desk's compact summary card (solid or outlined, title + icon,
// big count, optional amount), shared so the Dispense Queue and the Hybrid
// Pharmacy view look the same as the Receptionist screen.

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';

class DeskSummaryCard extends StatelessWidget {
  final String title;
  final int count;

  /// Small text bottom-right (e.g. "PKR 240"); hidden when null or on mobile.
  final String? amount;
  final Color solidColor;
  final IconData? icon;

  /// Shows the GMWF logo instead of [icon].
  final bool isImage;
  final bool isMobile;
  final bool isOutlined;
  final Color? outlineColor;
  final bool isDark;

  /// Card height; defaults to the Receptionist sizes (66 mobile / 76 desktop).
  final double? height;

  /// Highlights the card (used when it acts as a filter).
  final bool isSelected;
  final VoidCallback? onTap;

  const DeskSummaryCard({
    super.key,
    required this.title,
    required this.count,
    this.amount,
    required this.solidColor,
    this.icon,
    this.isImage = false,
    this.isMobile = false,
    this.isOutlined = false,
    this.outlineColor,
    required this.isDark,
    this.height,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOutline = outlineColor ?? solidColor;
    final bgColor = isOutlined
        ? (isDark ? SoftPalette.slate800 : SoftPalette.gray50)
        : solidColor;
    final primaryTextColor = isOutlined
        ? (isDark ? SoftPalette.gray50 : effectiveOutline)
        : SoftPalette.gray50;
    final secondaryTextColor = isOutlined
        ? (isDark
            ? SoftPalette.slate350
            : effectiveOutline.withValues(alpha: 0.85))
        : SoftPalette.gray50.withValues(alpha: 0.85);
    final compact = isMobile || (height != null && height! < 70);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: height ?? (isMobile ? 66 : 76),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? (isOutlined ? effectiveOutline : (isDark ? SoftPalette.gray50 : SoftPalette.gray900A54))
              : (isOutlined ? effectiveOutline : SoftPalette.gray50.withValues(alpha: 0.22)),
          width: isSelected ? 2.4 : (isOutlined ? 1.6 : 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: isOutlined
                ? effectiveOutline.withValues(alpha: isDark ? 0.25 : 0.15)
                : solidColor.withValues(alpha: isDark ? 0.45 : 0.35),
            blurRadius: isOutlined ? 10 : 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: SoftPalette.gray900.withValues(alpha: isDark ? 0.30 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 5 : 10,
        vertical: compact ? 4 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primaryTextColor,
                    fontSize: isMobile ? 9.5 : 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              if (isImage)
                Image.asset(
                  'assets/logo/gmwf-1.webp',
                  height: isMobile ? 12 : 17,
                  fit: BoxFit.contain,
                )
              else if (icon != null)
                Icon(icon, size: isMobile ? 12 : 16, color: primaryTextColor),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: primaryTextColor,
                    fontSize: isMobile ? 16 : (compact ? 19 : 22),
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
              if (!isMobile && amount != null)
                Flexible(
                  child: Text(
                    amount!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}
