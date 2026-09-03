import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_users_audit');
  if (tempDir.existsSync()) {
    try { tempDir.deleteSync(recursive: true); } catch (_) {}
  }
  tempDir.createSync(recursive: true);

  for (final file in hiveSourceDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final destPath = '${tempDir.path}\\${file.uri.pathSegments.last}';
      file.copySync(destPath);
    }
  }

  Hive.init(tempDir.path);
  final usersBox = await Hive.openBox('local_users');
  final empBox = await Hive.openBox('local_employees');

  print('=== 👥 LOCAL USERS IN USERS_BOX (${usersBox.length} users) ===\n');

  final empIds = <String>{};
  final empEmails = <String>{};
  final empNames = <String>{};
  final empPins = <String>{};

  for (var key in empBox.keys) {
    final raw = empBox.get(key);
    if (raw is Map) {
      final id = (raw['localId'] ?? raw['id'] ?? key).toString().trim();
      final email = (raw['email'] ?? '').toString().trim().toLowerCase();
      final name = (raw['name'] ?? '').toString().trim().toLowerCase();
      final pin = (raw['biometricPin'] ?? raw['pin'] ?? '').toString().trim();
      if (id.isNotEmpty) empIds.add(id);
      if (email.isNotEmpty) empEmails.add(email);
      if (name.isNotEmpty) empNames.add(name);
      if (pin.isNotEmpty) empPins.add(pin);
    }
  }

  int inEmpCount = 0;
  int missingEmpCount = 0;

  for (var key in usersBox.keys) {
    final raw = usersBox.get(key);
    if (raw is Map) {
      final uid = (raw['uid'] ?? raw['id'] ?? raw['userId'] ?? key).toString().trim();
      final name = (raw['name'] ?? raw['username'] ?? raw['displayName'] ?? '').toString().trim();
      final email = (raw['email'] ?? '').toString().trim().toLowerCase();
      final role = (raw['role'] ?? '').toString().trim();
      final branchId = (raw['branchId'] ?? '').toString().trim();
      final branches = raw['allowedBranches'] ?? raw['branches'];
      final sessions = raw['allowedSessions'] ?? raw['sessions'];
      final pin = (raw['biometricPin'] ?? raw['pin'] ?? '').toString().trim();
      final empId = (raw['employeeId'] ?? '').toString().trim();

      final inEmp = empIds.contains(uid) || empIds.contains(empId) || (email.isNotEmpty && empEmails.contains(email)) || (name.isNotEmpty && empNames.contains(name.toLowerCase()));

      if (inEmp) {
        inEmpCount++;
        print('✅ LINKED: name="$name" | email="$email" | role="$role" | branch="$branchId" | pin="$pin" | empId="$empId"');
      } else {
        missingEmpCount++;
        print('❌ NOT IN EMPLOYEES: name="$name" | email="$email" | role="$role" | branch="$branchId" | branches=$branches | sessions=$sessions | pin="$pin" | empId="$empId" | uid="$uid"');
      }
    }
  }

  print('\nSummary: $inEmpCount users linked to employees, $missingEmpCount users NOT in employees');
}
