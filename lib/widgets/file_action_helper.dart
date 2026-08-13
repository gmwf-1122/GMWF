// lib/widgets/file_action_helper.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/services.dart';

class FileActionHelper {
  static const MethodChannel _whatsappChannel = MethodChannel('com.gmwf.app/whatsapp_share');

  /// Resolves a usable local file path for bytes if direct save path is null or unsupported.
  static Future<String> getTempFilePath(String fileName, Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Displays an interactive modal sheet providing instant Open, Share, and Print options.
  static Future<void> showFileOptions(
    BuildContext context, {
    required String? filePath,
    required Uint8List? bytes,
    required String fileName,
    String title = 'Document Ready',
  }) async {
    String? resolvedPath = filePath;
    if ((resolvedPath == null || resolvedPath.isEmpty) && bytes != null && bytes.isNotEmpty && !kIsWeb) {
      try {
        resolvedPath = await getTempFilePath(fileName, bytes);
      } catch (e) {
        debugPrint('[FileActionHelper] Temp save failed: $e');
      }
    }

    final bool isPdf = fileName.toLowerCase().endsWith('.pdf') || (resolvedPath?.toLowerCase().endsWith('.pdf') ?? false);
    const accentColor = Color(0xFF10B981);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
                        color: accentColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF111827)),
                          ),
                          Text(
                            fileName,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Open File
                if (resolvedPath != null && resolvedPath.isNotEmpty && !kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.open_in_new_rounded, color: accentColor),
                    title: const Text('Open Document', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Open with system default application', style: TextStyle(fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final res = await OpenFilex.open(resolvedPath!);
                      if (res.type != ResultType.done && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not open file: ${res.message}')),
                        );
                      }
                    },
                  ),

                // Share File
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Colors.blue),
                  title: const Text('Share File', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Share via Email, WhatsApp, or Bluetooth', style: TextStyle(fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      if (resolvedPath != null && resolvedPath.isNotEmpty) {
                        await Share.shareXFiles(
                          [XFile(resolvedPath, mimeType: isPdf ? 'application/pdf' : null, name: fileName)],
                        );
                      } else if (isPdf && bytes != null) {
                        await Printing.sharePdf(bytes: bytes, filename: fileName);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Share failed: $e')),
                        );
                      }
                    }
                  },
                ),

                // Print Document (PDF only)
                if (isPdf)
                  ListTile(
                    leading: const Icon(Icons.print_rounded, color: Colors.purple),
                    title: const Text('Print Document', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Send directly to local or network printer', style: TextStyle(fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        if (bytes != null) {
                          await Printing.layoutPdf(onLayout: (_) async => bytes);
                        } else if (resolvedPath != null && File(resolvedPath).existsSync()) {
                          final fBytes = await File(resolvedPath).readAsBytes();
                          await Printing.layoutPdf(onLayout: (_) async => fBytes);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Printing failed: $e')),
                          );
                        }
                      }
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Generates, saves, and attaches the PDF to share via WhatsApp directly to the patient's phone number.
  static Future<void> sharePdfToWhatsApp({
    required Uint8List bytes,
    required String fileName,
    String? phoneNumber,
    String text = '',
  }) async {
    final cleanName = fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: cleanName);
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$cleanName');
    await file.writeAsBytes(bytes, flush: true);

    String? cleanPhone;
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.startsWith('0')) {
        cleanPhone = '92${cleanPhone.substring(1)}';
      }
    }

    if (Platform.isAndroid) {
      try {
        final bool? success = await _whatsappChannel.invokeMethod<bool>('sharePdfToWhatsAppNumber', {
          'filePath': file.path,
          'phone': cleanPhone,
          'text': text,
        });
        if (success == true) return;
      } catch (e) {
        debugPrint('[FileActionHelper] Direct WhatsApp share failed: $e');
      }
    }

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: cleanName)],
      text: text,
    );
  }
}

