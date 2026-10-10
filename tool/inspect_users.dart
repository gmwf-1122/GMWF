import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_users_audit');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);

  final userFile = File('${hiveSourceDir.path}\\local_users.hive');
  if (userFile.existsSync()) {
    userFile.copySync('${tempDir.path}\\local_users.hive');
  }

  Hive.init(tempDir.path);
  final box = await Hive.openBox('local_users');
  print('Total users in local_users: ${box.length}');
  for (final key in box.keys) {
    final u = box.get(key);
    if (u is Map) {
      final name = (u['name'] ?? u['username'] ?? '').toString();
      final role = (u['role'] ?? '').toString();
      final branch = (u['branchId'] ?? '').toString();
      final uid = (u['uid'] ?? u['id'] ?? '').toString();
      final email = (u['email'] ?? '').toString().toLowerCase();
      if (name.toLowerCase() == 'ali' || name.toLowerCase().startsWith('ali ') || email.contains('ali') || name.toLowerCase().contains('iqra')) {
        print('KEY: $key | USER: $name | EMAIL: ${u['email']} | ROLE: $role | BRANCH: $branch | UID: $uid');
      }
    }
  }
  await box.close();
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
}
