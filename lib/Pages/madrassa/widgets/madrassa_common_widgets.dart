import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../madrassa_strings.dart';
class BiLabel extends StatelessWidget {
  final String en;
  final TextStyle? enStyle;

  const BiLabel(this.en, {super.key, this.enStyle});

  @override
  Widget build(BuildContext context) {
    return Text(
      en,
      style: enStyle ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
    );
  }
}

Widget buildTf(
  TextEditingController ctrl,
  String label,
  IconData icon,
  BuildContext context, {
  TextInputType? inputType,
  List<TextInputFormatter>? formatters,
  bool obscure = false,
  String? hint,
  ValueChanged<String>? onChanged,
  bool enabled = true,
  String? errorText,
  bool isRequired = false,
}) {
  final en = label.split('\n')[0];

  return TextField(
    controller: ctrl,
    keyboardType: inputType,
    inputFormatters: formatters,
    obscureText: obscure,
    onChanged: onChanged,
    enabled: enabled,
    decoration: InputDecoration(
      label: isRequired
          ? RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: en,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.adapt(SoftPalette.gray900A87)),
                  ),
                  TextSpan(
                    text: ' *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.adapt(SoftPalette.red500)),
                  ),
                ],
              ),
            )
          : Text(en, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      hintText: hint,
      errorText: errorText,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: errorText != null ? context.adapt(SoftPalette.red500) : context.adapt(SoftPalette.slate200)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.adapt(SoftPalette.indigo550), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

class FriendlyError extends StatelessWidget {
  final String en, ur;
  const FriendlyError(this.en, this.ur, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: context.adapt(SoftPalette.red400), size: 48),
          const SizedBox(height: 16),
          Text(en, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

Widget sectionLabel(String label, BuildContext context) {
  final en = label.split('\n')[0];
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      en.toUpperCase(),
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: context.adapt(SoftPalette.indigo500),
          letterSpacing: 1.2),
    ),
  );
}

class ExportButton extends StatelessWidget {
  final VoidCallback onExcel;
  final VoidCallback onPdf;
  final bool isSmall;

  const ExportButton({super.key, required this.onExcel, required this.onPdf, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'excel') onExcel();
        if (val == 'pdf') onPdf();
      },
      itemBuilder: (ctx) => [
        _menuItem('Export PDF', Icons.picture_as_pdf_outlined, ctx.adapt(SoftPalette.red400), 'pdf'),
        _menuItem('Export Excel', Icons.file_download_outlined, ctx.adapt(SoftPalette.green400), 'excel'),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : 16, vertical: isSmall ? 8 : 10),
        decoration: BoxDecoration(
          color: SoftPalette.indigo550,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSmall ? null : [BoxShadow(color: SoftPalette.indigo550.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded, color: SoftPalette.gray50, size: isSmall ? 16 : 18),
            if (!isSmall) const SizedBox(width: 8),
            if (!isSmall) const Text('Download Reports', style: TextStyle(color: SoftPalette.gray50, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String en, IconData icon, Color color, String value) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(en, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class StudentExportMenu extends StatelessWidget {
  final VoidCallback onExcel;
  final VoidCallback onPdf;
  final VoidCallback? onWhatsApp;

  const StudentExportMenu({
    super.key,
    required this.onExcel,
    required this.onPdf,
    this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'excel') onExcel();
        if (val == 'pdf') onPdf();
        if (val == 'whatsapp' && onWhatsApp != null) onWhatsApp!();
      },
      icon: Icon(Icons.download_rounded, color: context.adapt(SoftPalette.indigo550), size: 20),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: ctx.adapt(SoftPalette.red400), size: 18),
              const SizedBox(width: 8),
              const Text('PDF', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              Icon(Icons.file_download_outlined, color: ctx.adapt(SoftPalette.green350), size: 18),
              const SizedBox(width: 8),
              const Text('Excel', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        if (onWhatsApp != null)
          PopupMenuItem(
            value: 'whatsapp',
            child: Row(
              children: [
                FaIcon(FontAwesomeIcons.whatsapp, color: ctx.adapt(SoftPalette.green350), size: 18),
                const SizedBox(width: 8),
                const Text('WhatsApp', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }
}

Widget buildActivityItem(BuildContext context, String user, String text, String time, IconData icon, Color color, {String? role}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cleanRole = role ?? '';

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? SoftPalette.slate800 : SoftPalette.gray50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? SoftPalette.slate700 : SoftPalette.slate150,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        user,
                        style: context.urduStyle(
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: isDark ? SoftPalette.gray50 : SoftPalette.slate900,
                          ),
                        ),
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        time,
                        style: TextStyle(
                          color: isDark ? SoftPalette.gray50A54 : SoftPalette.slate350,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                if (cleanRole.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: color.withValues(alpha: 0.2), width: 0.6),
                    ),
                    child: Text(
                      cleanRole.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: color,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  text,
                  style: context.urduStyle(
                    style: TextStyle(
                      color: isDark ? SoftPalette.slate200 : SoftPalette.slate600,
                      fontSize: 11.5,
                      height: 1.38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool isRequired;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final IconData icon;
  final bool enabled;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.isRequired = false,
    this.errorText,
    this.onChanged,
    this.icon = Icons.lock_outline,
    this.enabled = true,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final en = widget.label.split('\n')[0];

    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      decoration: InputDecoration(
        label: widget.isRequired
            ? RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: en,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.adapt(SoftPalette.gray900A87)),
                    ),
                    TextSpan(
                      text: ' *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.adapt(SoftPalette.red500)),
                    ),
                  ],
                ),
              )
            : Text(en, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        prefixIcon: Icon(widget.icon),
        suffixIcon: IconButton(
          icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.errorText != null ? context.adapt(SoftPalette.red500) : context.adapt(SoftPalette.slate200)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.adapt(SoftPalette.indigo550), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        errorText: widget.errorText,
      ),
    );
  }
}
