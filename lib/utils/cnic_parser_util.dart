import 'dart:convert';

class CnicParsedResult {
  final String cnic;
  final String name;
  final String fatherName;
  final String dob;
  final String rawText;
  final bool isSuccess;

  const CnicParsedResult({
    required this.cnic,
    required this.name,
    this.fatherName = '',
    this.dob = '',
    this.rawText = '',
    this.isSuccess = false,
  });

  factory CnicParsedResult.empty() => const CnicParsedResult(
        cnic: '',
        name: '',
        isSuccess: false,
      );
}

class CnicParserUtil {
  /// Format a 13-digit raw string (e.g. 3410112345671) into 34101-1234567-1
  static String formatCnic(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 13) return input.trim();
    return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-${digits.substring(12, 13)}';
  }

  /// Normalize CNIC to pure 13 digits for deduplication lookups
  static String normalizeCnic(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  /// Attempts to decode multi-format encoded QR/barcode payloads (Base64, Hex, URL, Delimited)
  static String decodeRawPayload(String input) {
    var text = input.trim();
    if (text.isEmpty) return text;

    // 1. Try URL decode
    try {
      if (text.contains('%')) {
        text = Uri.decodeComponent(text);
      }
    } catch (_) {}

    // 2. Try Base64 decode
    try {
      final cleanedB64 = text.replaceAll(RegExp(r'\s+'), '');
      if (cleanedB64.length % 4 == 0 && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(cleanedB64)) {
        final decodedBytes = base64.decode(cleanedB64);
        final decodedStr = utf8.decode(decodedBytes, allowMalformed: true);
        if (decodedStr.contains('|') || RegExp(r'\d{13}').hasMatch(decodedStr)) {
          text = decodedStr;
        }
      }
    } catch (_) {}

    // 3. Try Hex string decode (e.g. 3334313031...)
    try {
      final cleanedHex = text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (cleanedHex.length >= 26 && cleanedHex.length % 2 == 0) {
        final bytes = <int>[];
        for (int i = 0; i < cleanedHex.length; i += 2) {
          bytes.add(int.parse(cleanedHex.substring(i, i + 2), radix: 16));
        }
        final decodedHexStr = utf8.decode(bytes, allowMalformed: true);
        if (decodedHexStr.contains('|') || RegExp(r'\d{13}').hasMatch(decodedHexStr)) {
          text = decodedHexStr;
        }
      }
    } catch (_) {}

    return text;
  }

  /// Parses raw PDF417 / QR barcode string from Pakistani Smart CNIC (SNIC)
  static CnicParsedResult parsePdf417Barcode(String rawBarcodeData) {
    if (rawBarcodeData.trim().isEmpty) return CnicParsedResult.empty();

    final text = decodeRawPayload(rawBarcodeData);
    String cnic = '';
    String name = '';
    String fatherName = '';
    String dob = '';

    // Strategy 1: Delimited NADRA Smart CNIC barcode ('|', ';', '~', ',', '\t')
    final delimiterRegex = RegExp(r'[|;~,\t\r\n]+');
    if (delimiterRegex.hasMatch(text)) {
      final parts = text.split(delimiterRegex).map((p) => p.trim()).toList();
      for (final p in parts) {
        final digitsOnly = p.replaceAll(RegExp(r'[^0-9]'), '');
        if (digitsOnly.length == 13 && cnic.isEmpty) {
          cnic = formatCnic(digitsOnly);
        } else if (name.isEmpty && _isLikelyName(p)) {
          name = p.toUpperCase();
        } else if (fatherName.isEmpty && _isLikelyName(p)) {
          fatherName = p.toUpperCase();
        }
      }
      if (cnic.isNotEmpty) {
        return CnicParsedResult(
          cnic: cnic,
          name: name,
          fatherName: fatherName,
          dob: dob,
          rawText: text,
          isSuccess: true,
        );
      }
    }

    // Strategy 2: Regex 13-digit scan in raw text
    final cnicRegex = RegExp(r'\b\d{5}[-–]?\d{7}[-–]?\d{1}\b');
    final match = cnicRegex.firstMatch(text);
    if (match != null) {
      cnic = formatCnic(match.group(0)!);
    }

    // Extract name lines
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      final lLower = l.toLowerCase();
      if ((lLower.contains('name') || lLower.contains('نام')) && i + 1 < lines.length) {
        final nextLine = lines[i + 1].trim();
        if (_isLikelyName(nextLine)) {
          name = nextLine.toUpperCase();
          break;
        }
      }
    }

    return CnicParsedResult(
      cnic: cnic,
      name: name,
      fatherName: fatherName,
      dob: dob,
      rawText: text,
      isSuccess: cnic.isNotEmpty,
    );
  }

  /// Parses raw text extracted from OCR camera stream or barcode scanner
  static CnicParsedResult extractCnicAndNameFromOcr(String ocrText) {
    return parsePdf417Barcode(ocrText);
  }

  static bool _isLikelyName(String input) {
    if (input.length < 3 || input.length > 50) return false;
    // Must contain letters, no pure numbers
    if (RegExp(r'^\d+$').hasMatch(input)) return false;
    // Skip common label keywords
    final lower = input.toLowerCase();
    if (lower.contains('pakistan') ||
        lower.contains('identity') ||
        lower.contains('card') ||
        lower.contains('father') ||
        lower.contains('gender') ||
        lower.contains('date')) {
      return false;
    }
    return true;
  }
}
