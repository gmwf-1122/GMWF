import 'package:flutter/services.dart';

/// Formats CNIC input as XXXXX-XXXXXXX-X (13 digits, auto-hyphen)
class CNICInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Limit to 13 digits
    final limited = digits.length > 13 ? digits.substring(0, 13) : digits;
    final buffer = StringBuffer();

    for (int i = 0; i < limited.length; i++) {
      buffer.write(limited[i]);
      // Insert hyphen after 5th digit (index 4) and after 12th digit (index 11)
      if ((i == 4 || i == 11) && i != limited.length - 1) {
        buffer.write('-');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();

    for (int i = 0; i < limited.length; i++) {
      buffer.write(limited[i]);
      if ((i == 3 || i == 5) && i != limited.length - 1) {
        buffer.write('-');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Resolves a user's display name prioritizing username unless a custom name is explicitly provided.
String resolveUserDisplayName(Map<String, dynamic>? data, {String fallback = 'User'}) {
  if (data == null) return fallback;
  final username = (data['username'] ?? '').toString().trim();
  final name = (data['name'] ?? '').toString().trim();
  final role = (data['role'] ?? '').toString().trim();

  final isGenericOrRoleName = name.isEmpty ||
      name.toLowerCase() == username.toLowerCase() ||
      name.toLowerCase() == role.toLowerCase() ||
      ['user', 'admin', 'ceo', 'chairman', 'hq manager', 'branch manager', 'manager', 'supervisor', 'doctor', 'dispenser', 'receptionist', 'madrassa admin', 'school admin', 'global user', 'office boy', 'kitchen staff', 'staff'].contains(name.toLowerCase());

  if (!isGenericOrRoleName) {
    return name;
  }
  if (username.isNotEmpty) {
    return username;
  }
  if (name.isNotEmpty) {
    return name;
  }
  final email = (data['email'] ?? '').toString().trim();
  if (email.contains('@')) {
    return email.split('@').first;
  }
  return fallback;
}