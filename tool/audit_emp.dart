import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_emp_audit');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);

  for (final file in hiveSourceDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final destPath = '${tempDir.path}\\${file.uri.pathSegments.last}';
      file.copySync(destPath);
    }
  }

  Hive.init(tempDir.path);
  final box = await Hive.openBox('local_employees');
  print('Total Employees in local_employees: ${box.length}');

  int dotCount = 0;
  for (var key in box.keys) {
    final raw = box.get(key);
    if (raw is Map) {
      final name = raw['name']?.toString() ?? '';
      final pin = raw['biometricPin'] ?? raw['pin'] ?? '';
      final branchId = raw['branchId']?.toString() ?? '';
      final dept = raw['department']?.toString() ?? '';
      final role = raw['role']?.toString() ?? '';
      if (name.trim() == '.' || name.trim().isEmpty || pin.toString() == '155' || pin.toString() == '136' || pin.toString() == '15') {
        dotCount++;
        print('KEY: $key | name: "$name" | pin: "$pin" | branchId: "$branchId" | dept: "$dept" | role: "$role" | raw: $raw');
      }
    }
  }
  print('Total dot/matching records: $dotCount');

  // Also check sync_queue
  final sbox = await Hive.openBox('sync_queue');
  print('\nSync Queue items: ${sbox.length}');
  for (var key in sbox.keys) {
    print('  sync op: ${sbox.get(key)}');
  }

  tempDir.deleteSync(recursive: true);
}
