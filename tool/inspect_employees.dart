import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_emp_audit');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);

  final empFile = File('${hiveSourceDir.path}\\local_employees.hive');
  if (empFile.existsSync()) {
    empFile.copySync('${tempDir.path}\\local_employees.hive');
  }

  Hive.init(tempDir.path);
  final box = await Hive.openBox('local_employees');
  print('Total employees in box: ${box.length}');
  for (final key in box.keys) {
    final emp = box.get(key);
    if (emp is Map) {
      final name = emp['name']?.toString() ?? '';
      final role = emp['role']?.toString() ?? emp['designation']?.toString() ?? '';
      final dept = emp['department']?.toString() ?? '';
      final isActive = emp['isActive'];
      final status = emp['status'];
      final branch = emp['branchId'];
      final id = emp['id'] ?? emp['localId'] ?? emp['employeeId'];
      final pin = emp['pin'] ?? emp['biometricPin'];
      if (name.toLowerCase().contains('ali') || name.toLowerCase().contains('iqra') || dept.toLowerCase().contains('iqra') || branch.toString().toLowerCase().contains('iqra')) {
        print('KEY: $key | NAME: $name | PIN: $pin | ID: $id | ROLE: $role | DEPT: $dept | ACTIVE: $isActive | STATUS: $status | BRANCH: $branch');
      }
    }
  }
  await box.close();
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
}
