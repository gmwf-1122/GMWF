import 'dart:io';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/finance_local_storage.dart';

void main() async {
  final appData = Platform.environment['APPDATA'] ?? '';
  final hiveDir = Directory('$appData\\gmwf');
  Hive.init(hiveDir.path);

  await LocalStorageService.openBoxSafe(LocalStorageService.usersBox);
  await LocalStorageService.openBoxSafe(LocalStorageService.employeesBox);

  print('Pre-sync employees count: ${Hive.box(LocalStorageService.employeesBox).length}');

  final count = await FinanceLocalStorage.syncAllUsersToEmployees();
  print('Successfully synced/updated $count employee profiles!');

  final empBox = Hive.box(LocalStorageService.employeesBox);
  print('\n--- ALL EMPLOYEES AFTER SYNC ---');
  for (final key in empBox.keys) {
    final val = empBox.get(key);
    if (val is Map) {
      print('ID: $key | Name: "${val['name']}" | Role: "${val['role']}" | Dept: "${val['department']}" | PIN: "${val['biometricPin'] ?? val['pin']}" | Branch: "${val['branchId']}"');
    }
  }

  exit(0);
}
