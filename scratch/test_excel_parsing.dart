import 'dart:io';

int? _parseDayFromHeader(String header) {
  final trimmed = header.trim();
  final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
  if (isoMatch != null) {
    return int.tryParse(isoMatch.group(3)!);
  }
  final match = RegExp(r'^(\d+)').firstMatch(trimmed);
  if (match != null) {
    final parsed = int.tryParse(match.group(1)!);
    if (parsed != null && parsed <= 31) {
      return parsed;
    }
  }
  return null;
}

String? _parseHeaderDate(String headerStr) {
  final h = headerStr.trim();
  final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(h);
  if (isoMatch != null) {
    return '${isoMatch.group(1)}-${isoMatch.group(2)}-${isoMatch.group(3)}';
  }

  try {
    final parts = h.split(RegExp(r'[-/ ]'));
    if (parts.length >= 2) {
      if (parts[0].length == 4) {
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final day = parts.length > 2 ? int.tryParse(parts[2].replaceAll(RegExp(r'\D'), '')) : null;
        if (year != null && month != null && day != null) {
          return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
      }
      
      final dayStr = parts[0];
      final monthStr = parts[1];
      final day = int.tryParse(dayStr);
      if (day != null && day <= 31) {
        final monthsMap = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
        };
        int? month = int.tryParse(monthStr);
        if (month == null && monthStr.length >= 3) {
          month = monthsMap[monthStr.substring(0, 3).toLowerCase()];
        }
        if (month != null) {
          final year = parts.length > 2 ? (int.tryParse(parts[2].replaceAll(RegExp(r'\D'), '')) ?? DateTime.now().year) : DateTime.now().year;
          final mStr = month.toString().padLeft(2, '0');
          final dStr = day.toString().padLeft(2, '0');
          return '$year-$mStr-$dStr';
        }
      }
    }
  } catch (_) {}
  return null;
}

void main() {
  final input = "2026-01-05T00:00:00.000Z";
  print('Day parsed: ${_parseDayFromHeader(input)} (expected: 5)');
  print('Date parsed: ${_parseHeaderDate(input)} (expected: 2026-01-05)');
}
