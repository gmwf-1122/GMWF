// Safe version that works on the temp audit copy (not live Hive)
import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('  GMWF Attendance Sync Reset Tool (SAFE PREVIEW MODE)');
  print('  Working on temp copy — does NOT touch live data');
  print('═══════════════════════════════════════════════════════════════\n');

  // Work on temp copy
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_reset_preview');
  if (!tempDir.existsSync()) tempDir.createSync(recursive: true);

  for (final name in ['local_employee_attendance.hive', 'local_employee_attendance.lock']) {
    final src = File('${hiveSourceDir.path}\\$name');
    if (src.existsSync()) src.copySync('${tempDir.path}\\$name');
  }

  Hive.init(tempDir.path);
  final attBox = await Hive.openBox('local_employee_attendance');

  print('📦 Total records: ${attBox.length}\n');

  int resetCount = 0;
  int alreadyPendingCount = 0;
  int trulySync = 0;
  final resetDates = <String>{};

  for (final key in attBox.keys) {
    final raw = attBox.get(key);
    if (raw is! Map) continue;

    final synced = raw['synced'];
    final syncStatus = raw['syncStatus']?.toString();
    final lastSyncedAt = raw['lastSyncedAt'];
    final date = raw['date']?.toString() ?? 'unknown';
    final empName = (raw['employeeName'] ?? raw['name'] ?? '?').toString();
    final empId = (raw['employeeId'] ?? '?').toString();

    if (synced == false || syncStatus == 'pending') {
      alreadyPendingCount++;
      continue;
    }

    if (synced == true && syncStatus == 'synced' && lastSyncedAt != null) {
      trulySync++;
      continue;
    }

    if (synced == true && lastSyncedAt == null) {
      resetCount++;
      resetDates.add(date);
      print('  ↩ Would RESET: $empName ($empId) | $date | synced=true lastSyncedAt=null');
    }
  }

  await attBox.close();

  print('\n─── PREVIEW SUMMARY ───────────────────────────────────────────');
  print('Records that WOULD be reset to pending: $resetCount');
  print('Already properly pending:                $alreadyPendingCount');
  print('Truly synced (with timestamp):           $trulySync');
  if (resetDates.isNotEmpty) {
    final sortedDates = resetDates.toList()..sort();
    print('Affected dates: ${sortedDates.join(', ')}');
  }
  print('───────────────────────────────────────────────────────────────');
  print('\nTo apply the fix, close the GMWF app then run:');
  print('  dart run tool/reset_unsynced_attendance.dart');
}
