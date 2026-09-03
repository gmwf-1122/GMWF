// lib/pages/office/shared_widgets.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/bank_logo_widget.dart';


Widget buildFormField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  required RoleThemeData theme,
  List<TextInputFormatter>? inputFormatters,
  TextInputType? keyboardType,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
  bool enabled = true,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: enabled ? theme.bgCardAlt : theme.bgCardAlt.withOpacity(0.5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: theme.bgRule),
    ),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      enabled: enabled,
      style: TextStyle(color: enabled ? theme.textPrimary : theme.textSecondary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.textTertiary, fontSize: 12),
        prefixIcon: Icon(icon, color: theme.textTertiary, size: 18),
        border: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    ),
  );
}

Widget buildDatePickerField({
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  required IconData icon,
  required RoleThemeData theme,
  VoidCallback? onChanged,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: theme.bgCardAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: theme.bgRule),
    ),
    child: TextField(
      controller: controller,
      readOnly: false,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
        DateInputFormatter(),
      ],
      style: TextStyle(color: theme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.textTertiary, fontSize: 12),
        prefixIcon: Icon(icon, color: theme.textTertiary, size: 18),
        suffixIcon: IconButton(
          icon: Icon(Icons.calendar_today, color: theme.textTertiary, size: 18),
          onPressed: () async {
            final initial = controller.text.isNotEmpty ? DateTime.tryParse(controller.text) ?? DateTime.now() : DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1950),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
            );
            if (picked != null) {
              controller.text = DateFormat('yyyy-MM-dd').format(picked);
              if (onChanged != null) onChanged();
            }
          },
        ),
        border: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: (_) {
        if (onChanged != null) onChanged();
      },
    ),
  );
}

Widget buildResponsiveFieldRow({
  required List<Widget> children,
  required bool isNarrow,
  double spacing = 10,
}) {
  if (isNarrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children.map((c) {
        Widget field = c;
        if (c is Expanded) {
          field = c.child;
        }
        return Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: field,
        );
      }).toList(),
    );
  } else {
    return Padding(
      padding: EdgeInsets.only(bottom: spacing),
      child: Row(
        children: children,
      ),
    );
  }
}

Widget buildDropdownField({
  required String label,
  required String value,
  required List<String> items,
  required ValueChanged<String?> onChanged,
  required RoleThemeData theme,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: theme.bgCardAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: theme.bgRule),
    ),
    child: DropdownButtonFormField<String>(
      value: value,
      dropdownColor: theme.bgCard,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.textTertiary, fontSize: 11),
        border: InputBorder.none,
        filled: false,
      ),
      style: TextStyle(color: theme.textPrimary, fontSize: 13),
      items: items.map((i) {
        final isBank = label.toLowerCase().contains('bank') && !i.startsWith('+');
        return DropdownMenuItem(
          value: i,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBank) ...[
                BankLogoWidget(bankName: i, size: 20),
                const SizedBox(width: 8),
              ],
              Text(i, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
    ),
  );
}


void showAddCustomDialog({
  required BuildContext context,
  required String title,
  required String hint,
  required ValueChanged<String> onAdded,
  required RoleThemeData theme,
}) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: theme.bgCard,
        title: Text(title, style: TextStyle(color: theme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: theme.textTertiary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.bgRule)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.accent),
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              onAdded(text);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}

void showCustomSnackBar(BuildContext context, String msg, {bool error = false}) {
  final t = RoleThemeScope.dataOf(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red : t.accent,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ));
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED REDESIGN COMPONENTS
// Build once, reuse everywhere — see "Finance & HR UI Redesign Plan" §4.
// These back Attendance, Payroll, Employees, and Audit Trail so status
// colors, metric styling, and row layout stay identical across screens.
// ═══════════════════════════════════════════════════════════════════════════

// ── Status vocabulary ───────────────────────────────────────────────────────
// Fixed 5-color semantic vocabulary. Every status pill anywhere in the app
// (attendance, payroll, audit trail actions) should map to one of these —
// never a bespoke color. See Core Design Principles #1 and #3.
//
// Suggested mapping (adjust per screen, but keep consistent once chosen):
//   success -> present / paid / created / approved
//   warning -> leave / unpaid / pending
//   accent  -> holiday / off / info
//   pro     -> transfer / update / informational secondary actions
//   danger  -> absent / void / delete
enum StatusPillVariant { success, warning, accent, pro, danger }

Color _statusPillColor(StatusPillVariant variant, RoleThemeData theme) {
  switch (variant) {
    case StatusPillVariant.success:
      return theme.isDarkCanvas ? Colors.green[300]! : Colors.green[700]!;
    case StatusPillVariant.warning:
      return theme.isDarkCanvas ? Colors.orange[300]! : Colors.orange[700]!;
    case StatusPillVariant.accent:
      return theme.accent;
    case StatusPillVariant.pro:
      return theme.isDarkCanvas ? Colors.blue[300]! : Colors.blue[700]!;
    case StatusPillVariant.danger:
      // NOTE: assumes RoleThemeData exposes `danger` (already referenced as
      // `t.danger` in employees_tab.dart's leave-quota screen). If your
      // theme class does not define this getter, replace the line below with:
      //   return theme.isDarkCanvas ? Colors.red[300]! : Colors.red[700]!;
      return theme.danger;
  }
}

/// A small colored pill for status/state — replaces bespoke banner text,
/// ad hoc badges, and one-off `Container(decoration: BoxDecoration(color: ...))`
/// blocks scattered across Payroll/Employees/Audit Trail.
///
/// `filled: false` (default) = outline/muted chip, used for row-level status
/// (e.g. "Unpaid", "Archived", audit action tags).
/// `filled: true` = solid chip, used for the "active" state in a segmented
/// control (e.g. the Attendance 5-icon status group).
Widget buildStatusPill({
  required String label,
  required StatusPillVariant variant,
  required RoleThemeData theme,
  IconData? icon,
  bool filled = false,
}) {
  final color = _statusPillColor(variant, theme);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? color : color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(filled ? 1 : 0.3), width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: filled ? Colors.white : color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: filled ? Colors.white : color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ],
    ),
  );
}

// ── Metric card ──────────────────────────────────────────────────────────────
/// Label (small, muted) above, number (large, w500) below, flat surface,
/// no gradient. Replaces the gradient-background summary strip on the
/// Payroll board and any other "dashboard tile" pattern.
Widget buildMetricCard({
  required String label,
  required String value,
  required RoleThemeData theme,
  Color? valueColor,
  String? caption,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.bgCardAlt,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: theme.bgRule),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(color: theme.textTertiary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(color: valueColor ?? theme.textPrimary, fontSize: 18, fontWeight: FontWeight.w500),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption, style: TextStyle(color: theme.textTertiary, fontSize: 9)),
        ],
      ],
    ),
  );
}

/// Convenience row of metric cards separated by a thin rule, matching the
/// "Month Disbursement / Disbursed Total / Pending Total" strip pattern —
/// use this instead of hand-rolling `Row` + `Container(width: 0.5)` dividers.
Widget buildMetricCardRow({
  required List<Widget> cards,
  required RoleThemeData theme,
}) {
  final children = <Widget>[];
  for (var i = 0; i < cards.length; i++) {
    children.add(Expanded(child: cards[i]));
    if (i != cards.length - 1) {
      children.add(Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 10), color: theme.bgRule));
    }
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
}

// ── Initials avatar ──────────────────────────────────────────────────────────
/// Extracted since `CircleAvatar(backgroundColor: accentMuted, child: Text(initial))`
/// is currently duplicated in Employees, Payroll, and Employee Report.
Widget buildInitialsAvatar({
  required String name,
  required RoleThemeData theme,
  double radius = 20,
  String? imageUrl,
  String? imagePath,
  String? gender,
}) {
  bool hasLocal = false;
  if (!kIsWeb && imagePath != null && imagePath.isNotEmpty) {
    try {
      hasLocal = File(imagePath).existsSync();
    } catch (_) {
      hasLocal = false;
    }
  }
  final hasRemote = imageUrl != null && imageUrl.isNotEmpty;
  Uint8List? base64Bytes;
  if (hasRemote) {
    base64Bytes = ImageUploadService.decodeBase64ToBytes(imageUrl);
  }

  final isFemale = gender?.toLowerCase() == 'female';
  final isMale = gender?.toLowerCase() == 'male';

  Widget buildGenderFallback() {
    if (isFemale) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFFCE7F3),
        child: Icon(Icons.face_3_rounded, size: radius * 1.25, color: const Color(0xFFDB2777)),
      );
    } else if (isMale) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE0F2FE),
        child: Icon(Icons.face_6_rounded, size: radius * 1.25, color: const Color(0xFF0284C7)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.accentMuted,
      child: Text(
        (name.isNotEmpty && name.trim() != '.') ? name.trim()[0].toUpperCase() : '?',
        style: TextStyle(color: theme.accent, fontWeight: FontWeight.bold, fontSize: radius * 0.77),
      ),
    );
  }

  if (hasLocal || hasRemote) {
    ImageProvider imageProvider;
    if (hasLocal && !kIsWeb) {
      imageProvider = FileImage(File(imagePath!));
    } else if (base64Bytes != null) {
      imageProvider = MemoryImage(base64Bytes);
    } else {
      imageProvider = NetworkImage(imageUrl!);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: isFemale ? const Color(0xFFFCE7F3) : (isMale ? const Color(0xFFE0F2FE) : theme.accentMuted),
        child: Image(
          image: imageProvider,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => buildGenderFallback(),
        ),
      ),
    );
  }

  return buildGenderFallback();
}

// ── List row ─────────────────────────────────────────────────────────────────
/// Bordered (bottom rule), not boxed — no shadow, no card background.
/// avatar/leading + title/subtitle on the left, one key metric on the
/// right, an optional muted secondary-detail line underneath, and an
/// optional status pill next to the title.
///
/// This is THE row pattern for Payroll, Employees, and Audit Trail —
/// dense lists over heavy cards (Core Design Principle #4). Wrap a list of
/// these directly in a Column or ListView; no extra margin/elevation needed.
Widget buildListRow({
  required RoleThemeData theme,
  required String title,
  String? subtitle,
  String? secondaryDetail,
  Widget? leading,
  Widget? trailing,
  Widget? statusPill,
  VoidCallback? onTap,
}) {
  return InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.bgRule, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (statusPill != null) ...[const SizedBox(width: 8), statusPill],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: theme.textSecondary, fontSize: 12)),
                ],
                if (secondaryDetail != null) ...[
                  const SizedBox(height: 4),
                  Text(secondaryDetail, style: TextStyle(color: theme.textTertiary, fontSize: 11)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    ),
  );
}