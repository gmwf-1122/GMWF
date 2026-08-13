import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

/// Service to interact with Meta WhatsApp Cloud API for sending documents (PDFs) and messages.
class WhatsAppCloudApiService {
  static String get _token => WhatsAppConfig.accessToken;
  static String get _phoneNumberId => WhatsAppConfig.phoneNumberId;

  /// Sanitizes phone number to international format without leading + or 0 (defaults to country code 92 for Pakistan if starting with 0).
  static String formatPhoneNumber(String phone) {
    String clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('0')) {
      clean = '92${clean.substring(1)}';
    }
    return clean;
  }

  /// Step 1: Upload PDF binary bytes to WhatsApp Cloud API Media endpoint.
  /// Returns the uploaded media ID string.
  static Future<String?> uploadPdfMedia({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      final uri = Uri.parse(WhatsAppConfig.mediaUploadUrl);
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $_token';
      request.fields['messaging_product'] = 'whatsapp';
      request.fields['type'] = 'application/pdf';

      final cleanName = fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          pdfBytes,
          filename: cleanName,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final mediaId = data['id'] as String?;
        debugPrint('[WhatsAppCloudApi] Media uploaded successfully. ID: $mediaId');
        return mediaId;
      } else {
        debugPrint('[WhatsAppCloudApi] Media upload failed (${response.statusCode}): ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[WhatsAppCloudApi] Error uploading PDF media: $e');
      return null;
    }
  }

  /// Step 2: Send uploaded PDF document via media ID to recipient phone number.
  static Future<bool> sendPdfDocument({
    required String recipientPhone,
    required String mediaId,
    required String fileName,
    String? caption,
  }) async {
    try {
      final cleanPhone = formatPhoneNumber(recipientPhone);
      final uri = Uri.parse(WhatsAppConfig.sendMessageUrl);
      final cleanName = fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf';

      final body = {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": cleanPhone,
        "type": "document",
        "document": {
          "id": mediaId,
          "filename": cleanName,
          if (caption != null && caption.isNotEmpty) "caption": caption,
        }
      };

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[WhatsAppCloudApi] Document sent successfully to $cleanPhone');
        return true;
      } else {
        debugPrint('[WhatsAppCloudApi] Send document failed (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[WhatsAppCloudApi] Error sending PDF document: $e');
      return false;
    }
  }

  /// Convenience method: Uploads PDF and directly sends document message to recipient.
  static Future<bool> uploadAndSendPdf({
    required String recipientPhone,
    required Uint8List pdfBytes,
    required String fileName,
    String? caption,
  }) async {
    final mediaId = await uploadPdfMedia(pdfBytes: pdfBytes, fileName: fileName);
    if (mediaId == null) {
      return false;
    }
    return await sendPdfDocument(
      recipientPhone: recipientPhone,
      mediaId: mediaId,
      fileName: fileName,
      caption: caption,
    );
  }
}
