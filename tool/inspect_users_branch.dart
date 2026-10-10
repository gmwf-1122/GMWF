import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory.systemTemp.createTempSync('users_inspect');
  final f = File('${hiveDir.path}\\local_users.hive');
  f.copySync('${tempDir.path}\\local_users.hive');
  Hive.init(tempDir.path);
  final box = await Hive.openBox('local_users');
  for (final k in box.keys) {
    final u = box.get(k);
    if (u is Map) {
      final name = (u['username'] ?? u['email'] ?? '').toString();
      if (name.toLowerCase().contains('doc') || name.toLowerCase().contains('temp')) {
        print('MATCHED USER: $name | role=${u['role']} | branchId=${u['branchId']} | assignedCamps=${u['assignedCamps']}');
      }
    }
  }
}
