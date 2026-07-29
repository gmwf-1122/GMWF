import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final srcDir = Directory(r"C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive");
  final destDir = Directory("temp_hive");
  if (!destDir.existsSync()) {
    destDir.createSync();
  }
  
  for (var file in srcDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final name = file.path.split(Platform.pathSeparator).last;
      file.copySync('temp_hive/$name');
      print("Copied $name to temp_hive");
    }
  }
  
  Hive.init('temp_hive');
  final box = await Hive.openBox('local_donations');
  print('\nTotal local donations in box: ${box.length}');
  
  final Map<int, double> yearlyTotals = {};
  for (var val in box.values) {
    if (val is Map) {
      final dateStr = val['date']?.toString();
      if (dateStr != null && dateStr.isNotEmpty) {
        final date = DateTime.tryParse(dateStr);
        if (date != null) {
          final amt = (val['amount'] as num?)?.toDouble() ?? 0.0;
          final probableAmt = (val['probableAmount'] as num?)?.toDouble() ?? 0.0;
          final finalAmt = amt > 0 ? amt : probableAmt;
          yearlyTotals[date.year] = (yearlyTotals[date.year] ?? 0.0) + finalAmt;
        }
      }
    }
  }
  
  print('\n--- Yearly Totals in Hive ---');
  for (var entry in yearlyTotals.entries) {
    print('Year ${entry.key}: PKR ${entry.value.toStringAsFixed(2)}');
  }
  await box.close();
}
