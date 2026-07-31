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

/// Resolves a user's display name prioritizing explicit full name or username.
String resolveUserDisplayName(Map<String, dynamic>? data, {String fallback = 'User'}) {
  if (data == null) return fallback;
  final name = (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '').toString().trim();
  final username = (data['username'] ?? data['userName'] ?? '').toString().trim();
  final email = (data['email'] ?? '').toString().trim();

  // Return non-empty real name if it exists and is not literally 'User' or 'Unknown'
  if (name.isNotEmpty &&
      name.toLowerCase() != 'user' &&
      name.toLowerCase() != 'unknown' &&
      name.toLowerCase() != 'unknown user') {
    return name;
  }

  // Return non-empty username if it exists and is not literally 'user' or 'unknown'
  if (username.isNotEmpty &&
      username.toLowerCase() != 'user' &&
      username.toLowerCase() != 'unknown' &&
      username.toLowerCase() != 'unknown user') {
    return username;
  }

  if (email.contains('@')) {
    final parts = email.split('@').first;
    if (parts.isNotEmpty) {
      return parts[0].toUpperCase() + parts.substring(1);
    }
  }

  return name.isNotEmpty ? name : fallback;
}