// lib/widgets/file_action_helper.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

class FileActionHelper {
  static const MethodChannel _whatsappChannel = MethodChannel('com.gmwf.app/whatsapp_share');

  /// Resolves a usable local file path for bytes if direct save path is null or unsupported.
  static Future<String> getTempFilePath(String fileName, Uint8List bytes) async {
    Directory targetDir;
    try {
      if (Platform.isWindows) {
        targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final outDir = Directory('${targetDir.path}/GMWF_Prescriptions');
        if (!outDir.existsSync()) {
          await outDir.create(recursive: true);
        }
        final file = File('${outDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      }
    } catch (_) {}

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Displays an interactive modal sheet providing instant Open, WhatsApp Share, Folder, and Print options.
  static Future<void> showFileOptions(
    BuildContext context, {
    required String? filePath,
    required Uint8List? bytes,
    required String fileName,
    String title = 'Document Ready',
    String? phoneNumber,
    String? shareText,
  }) async {
    String? resolvedPath = filePath;
    if ((resolvedPath == null || resolvedPath.isEmpty) && bytes != null && bytes.isNotEmpty && !kIsWeb) {
      try {
        resolvedPath = await getTempFilePath(fileName, bytes);
      } catch (e) {
        debugPrint('[FileActionHelper] Save failed: $e');
      }
    }

    final bool isPdf = fileName.toLowerCase().endsWith('.pdf') || (resolvedPath?.toLowerCase().endsWith('.pdf') ?? false);
    const accentColor = Color(0xFF00695C);

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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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

                // 1. WhatsApp Share
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Color(0xFF2E7D32)),
                  title: const Text('Send via WhatsApp', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    phoneNumber != null && phoneNumber.isNotEmpty
                        ? 'Send directly to $phoneNumber'
                        : 'Open chat with prefilled message & attached PDF',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    Uint8List? rawBytes = bytes;
                    if (rawBytes == null && resolvedPath != null && File(resolvedPath).existsSync()) {
                      rawBytes = await File(resolvedPath).readAsBytes();
                    }
                    if (rawBytes != null) {
                      await sharePdfToWhatsApp(
                        bytes: rawBytes,
                        fileName: fileName,
                        phoneNumber: phoneNumber,
                        text: shareText ?? 'Assalam-o-Alaikum, here is your medical prescription document from Gulzar Madina Free Dispensary.',
                      );
                    }
                  },
                ),

                // 2. Open Document
                if (resolvedPath != null && resolvedPath.isNotEmpty && !kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.open_in_new_rounded, color: accentColor),
                    title: const Text('Open Document', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Open with system default PDF reader', style: TextStyle(fontSize: 11)),
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

                // 3. Windows Explorer / Folder Location
                if (Platform.isWindows && resolvedPath != null && resolvedPath.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded, color: Color(0xFFD97706)),
                    title: const Text('Show in Folder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Open file location in Windows Explorer for drag & drop', style: TextStyle(fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await Process.run('explorer.exe', ['/select,', resolvedPath!]);
                      } catch (_) {
                        try {
                          await OpenFilex.open(File(resolvedPath!).parent.path);
                        } catch (_) {}
                      }
                    },
                  ),

                // 4. Print Document (PDF only)
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

    String? cleanPhone;
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.startsWith('0')) {
        cleanPhone = '92${cleanPhone.substring(1)}';
      } else if (!cleanPhone.startsWith('92') && cleanPhone.length == 10) {
        cleanPhone = '92$cleanPhone';
      }
    }

    // Windows Desktop: Save PDF to Downloads, open WhatsApp Web/Desktop chat, and highlight file in Explorer
    if (Platform.isWindows) {
      try {
        Directory? targetDir;
        try {
          targetDir = await getDownloadsDirectory();
        } catch (_) {}
        targetDir ??= await getApplicationDocumentsDirectory();

        final outDir = Directory('${targetDir.path}/GMWF_Prescriptions');
        if (!outDir.existsSync()) {
          await outDir.create(recursive: true);
        }
        final destFile = File('${outDir.path}/$cleanName');
        await destFile.writeAsBytes(bytes, flush: true);

        // 1. Copy the PDF file itself to the Windows Clipboard (CF_HDROP) so pressing Ctrl+V in WhatsApp instantly attaches the document!
        final winPath = destFile.path.replaceAll('/', '\\');
        try {
          await Process.run('powershell', ['-NoProfile', '-Command', 'Set-Clipboard -Path "$winPath"']);
        } catch (_) {}

        // 2. Open WhatsApp (Windows Native App or Web) directly to the patient's phone & prefilled greeting
        final encodedText = Uri.encodeComponent(text);
        bool launchedNative = false;
        if (cleanPhone != null && cleanPhone.isNotEmpty) {
          try {
            final nativeAppUri = Uri.parse('whatsapp://send/?phone=$cleanPhone&text=$encodedText');
            launchedNative = await launchUrl(nativeAppUri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }

        if (!launchedNative) {
          final waUrlStr = (cleanPhone != null && cleanPhone.isNotEmpty)
              ? 'https://web.whatsapp.com/send?phone=$cleanPhone&text=$encodedText'
              : 'https://web.whatsapp.com/send?text=$encodedText';
          try {
            await launchUrl(Uri.parse(waUrlStr), mode: LaunchMode.externalApplication);
          } catch (e) {
            try {
              final fallbackWaMe = Uri.parse('https://wa.me/${cleanPhone ?? ''}?text=$encodedText');
              await launchUrl(fallbackWaMe, mode: LaunchMode.externalApplication);
            } catch (e2) {
              debugPrint('[FileActionHelper] WhatsApp launch error: $e2');
            }
          }
        }

        // 3. Open Explorer with the exact PDF pre-selected for drag-and-drop
        try {
          await Process.run('explorer.exe', ['/select,$winPath']);
        } catch (_) {
          try {
            await OpenFilex.open(outDir.path);
          } catch (_) {}
        }
        return;
      } catch (e) {
        debugPrint('[FileActionHelper] Windows WhatsApp share error: $e');
      }
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$cleanName');
    await file.writeAsBytes(bytes, flush: true);

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

