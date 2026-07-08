import 'package:flutter/material.dart';
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
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFD32F2F)),
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
        borderSide: BorderSide(color: errorText != null ? const Color(0xFFD32F2F) : const Color(0xFFD0D3D9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4C4DDC), width: 2),
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
          Icon(Icons.error_outline_rounded, color: Colors.red.shade300, size: 48),
          const SizedBox(height: 16),
          Text(en, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

Widget sectionLabel(String label) {
  final en = label.split('\n')[0];
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      en.toUpperCase(),
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.indigo.shade400,
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
        _menuItem('Export PDF', Icons.picture_as_pdf_outlined, Colors.red, 'pdf'),
        _menuItem('Export Excel', Icons.file_download_outlined, Colors.green, 'excel'),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : 16, vertical: isSmall ? 8 : 10),
        decoration: BoxDecoration(
          color: const Color(0xFF4C4DDC),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSmall ? null : [BoxShadow(color: const Color(0xFF4C4DDC).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded, color: Colors.white, size: isSmall ? 16 : 18),
            if (!isSmall) const SizedBox(width: 8),
            if (!isSmall) const Text('Download Reports', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
      icon: const Icon(Icons.download_rounded, color: Color(0xFF4C4DDC), size: 20),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: Colors.red.shade400, size: 18),
              const SizedBox(width: 8),
              const Text('PDF', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              Icon(Icons.file_download_outlined, color: Colors.green.shade400, size: 18),
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
                const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366), size: 18),
                const SizedBox(width: 8),
                const Text('WhatsApp', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }
}

Widget buildActivityItem(BuildContext context, String user, String text, String time, IconData icon, Color color) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    user,
                    style: context.urduStyle(
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Text(time, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: context.urduStyle(
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
