import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/utils/formatters.dart';

void main() {
  test('DOB normalization keeps dd-MM-yyyy intact and fixes 8-digit input', () {
    expect(normalizeDobInput('20-06-2006'), '20-06-2006');
    expect(normalizeDobInput('20062006'), '20-06-2006');
    expect(normalizeDobInput('2006'), '2006');
  });

  test('DOB parser resolves year correctly without dropping leading digits', () {
    final parsed = parseDobDateTime('20-06-2006');
    expect(parsed, isNotNull);
    expect(parsed!.year, 2006);
    expect(parsed.month, 6);
    expect(parsed.day, 20);
  });
}
