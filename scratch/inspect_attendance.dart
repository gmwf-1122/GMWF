import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final path = r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive';
  Hive.init(path);
  
  final box = await Hive.openBox('local_employee_attendance');
  print('Total attendance records: ${box.length}');
  
  final empId = '6e9fe8e6-0c26-4084-ac36-9b401275925f'; // ANS SULEMAN
  final monthKey = '2026-07';
  
  final records = [];
  for (final key in box.keys) {
    if (key.toString().startsWith('${empId}_$monthKey')) {
      records.add({
        'key': key,
        'val': box.get(key)
      });
    }
  }
  
  records.sort((a, b) => a['key'].toString().compareTo(b['key'].toString()));
  for (final r in records) {
    print('${r['key']}: ${r['val']}');
  }
}
