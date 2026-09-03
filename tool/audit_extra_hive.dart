import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_hive_audit');
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);

  for (final file in hiveSourceDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final destPath = '${tempDir.path}\\${file.uri.pathSegments.last}';
      file.copySync(destPath);
    }
  }

  Hive.init(tempDir.path);

  final boxesToCheck = [
    'local_users',
    'local_madrassa_students',
    'local_stock_items',
    'local_employee_attendance',
    'realtime_outbox'
  ];

  for (final bName in boxesToCheck) {
    try {
      final box = await Hive.openBox(bName);
      print('Box $bName: ${box.length} records');
    } catch (e) {
      print('Error opening $bName: $e');
    }
  }

  await Hive.close();
  try {
    tempDir.deleteSync(recursive: true);
  } catch (_) {}
}
