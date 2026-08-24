import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

DateTime decodeZkTime(int encoded) {
  final second = encoded % 60;
  encoded ~/= 60;
  final minute = encoded % 60;
  encoded ~/= 60;
  final hour = encoded % 24;
  encoded ~/= 24;
  final day = (encoded % 31) + 1;
  encoded ~/= 31;
  final month = (encoded % 12) + 1;
  encoded ~/= 12;
  final year = encoded + 2000;
  return DateTime(year, month, day, hour, minute, second);
}

int encodeZkTime(DateTime dt) {
  int val = dt.year - 2000;
  val = val * 12 + (dt.month - 1);
  val = val * 31 + (dt.day - 1);
  val = val * 24 + dt.hour;
  val = val * 60 + dt.minute;
  val = val * 60 + dt.second;
  return val;
}

String? extractPinFromZkPayload(Uint8List payload) {
  // If payload contains text
  final text = String.fromCharCodes(payload);
  if (text.contains('\t') || text.contains(',')) {
    final parts = text.split(RegExp(r'[\t,]'));
    if (parts.isNotEmpty) {
      final p = parts[0].replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '').trim();
      if (p.isNotEmpty && !p.startsWith('PP')) return p;
    }
  }

  // Check 40-byte binary record (PIN at offset 0-23)
  if (payload.length >= 28) {
    final pinBytes = payload.sublist(0, 24);
    final nullIdx = pinBytes.indexOf(0);
    final rawPin = String.fromCharCodes(pinBytes.sublist(0, nullIdx > 0 ? nullIdx : 24)).trim();
    final cleanPin = rawPin.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (cleanPin.isNotEmpty && !cleanPin.startsWith('PP')) {
      return cleanPin;
    }
  }

  // Check 24-byte legacy binary record (PIN at offset 0-1 as 16-bit uint)
  if (payload.length >= 8) {
    final pinNum = payload[0] | (payload[1] << 8);
    if (pinNum > 0 && pinNum < 65535) {
      return pinNum.toString();
    }
  }

  // Regex fallback across printable chars
  final match = RegExp(r'(\d{1,10})').firstMatch(text);
  if (match != null) {
    return match.group(1);
  }

  return null;
}

void main() {
  test('ZKTeco Time Encode/Decode roundtrip', () {
    final now = DateTime(2026, 8, 22, 17, 11, 5);
    final encoded = encodeZkTime(now);
    final decoded = decodeZkTime(encoded);
    expect(decoded.year, equals(2026));
    expect(decoded.month, equals(8));
    expect(decoded.day, equals(22));
    expect(decoded.hour, equals(17));
    expect(decoded.minute, equals(11));
    expect(decoded.second, equals(5));
  });

  test('Realtime Event PIN parsing for PIN 168 (40-byte)', () {
    final payload = Uint8List(40);
    payload[0] = '1'.codeUnitAt(0);
    payload[1] = '6'.codeUnitAt(0);
    payload[2] = '8'.codeUnitAt(0);
    payload[3] = 0;

    final pin = extractPinFromZkPayload(payload);
    expect(pin, equals('168'));
  });

  test('Realtime Event PIN parsing for PIN 157 (24-byte integer)', () {
    final payload = Uint8List(24);
    payload[0] = 157 & 0xFF;
    payload[1] = (157 >> 8) & 0xFF;

    final pin = extractPinFromZkPayload(payload);
    expect(pin, equals('157'));
  });

  test('Rejects ZK Magic Bytes PP header as PIN', () {
    final magicPayload = Uint8List.fromList([0x50, 0x50, 0x82, 0x7D, 0x00, 0x00]);
    final pin = extractPinFromZkPayload(magicPayload);
    expect(pin, isNot(equals('PP')));
  });
}
