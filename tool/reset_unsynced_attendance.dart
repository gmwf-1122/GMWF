// tool/reset_unsynced_attendance.dart
//
// ONE-TIME FIX: Resets attendance records that were falsely marked as
// synced=true (because of the !enqueueForSync bug in zkteco_network_service.dart)
// but have no lastSyncedAt — meaning they were NEVER actually uploaded to Firestore.
//
// After running this, the next app launch will have _enqueueMissingAttendance()
// re-queue and upload all of these records automatically.
//
// RUN ONCE with: dart run tool/reset_unsynced_attendance.dart
// (App must be CLOSED before running this script)

import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('  GMWF Attendance Sync Reset Tool');
  print('  Finds records marked synced=true but never actually uploaded');
  print('  and resets them to pending so the app re-uploads them.');
  print('═══════════════════════════════════════════════════════════════\n');

  // --- Safety check: make sure app is not running ---
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  if (!hiveDir.existsSync()) {
    print('❌ Hive directory not found at ${hiveDir.path}');
    print('   Make sure the GMWF app has been run at least once.');
    exit(1);
  }

  // Work directly on live Hive directory (app must be closed)
  Hive.init(hiveDir.path);

  Box? attBox;
  try {
    attBox = await Hive.openBox('local_employee_attendance');
  } catch (e) {
    print('❌ Could not open attendance box: $e');
    print('   Make sure the GMWF app is CLOSED before running this tool.');
    exit(1);
  }

  print('📦 Opened local_employee_attendance: ${attBox.length} records total\n');

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

    // Case 1: Already properly pending — skip
    if (synced == false || syncStatus == 'pending') {
      alreadyPendingCount++;
      continue;
    }

    // Case 2: Truly synced (has lastSyncedAt and both flags set) — skip
    if (synced == true && syncStatus == 'synced' && lastSyncedAt != null) {
      trulySync++;
      continue;
    }

    // Case 3: Falsely synced (synced=true but NO lastSyncedAt, or syncStatus missing)
    // This is the bug: zkteco set synced=true but it was never actually uploaded.
    if (synced == true && lastSyncedAt == null) {
      final updated = Map<String, dynamic>.from(raw)
        ..['synced'] = false
        ..['syncStatus'] = 'pending'
        ..remove('remoteId');
      await attBox.put(key, updated);
      resetCount++;
      resetDates.add(date);
      print('  ↩ RESET: $empName ($empId) | $date | was synced=true, lastSyncedAt=null');
    }
  }

  await attBox.flush();
  await attBox.close();

  print('\n═══════════════════════════════════════════════════════════════');
  print('✅ DONE!');
  print('   Records RESET to pending:     $resetCount');
  print('   Already pending (good):        $alreadyPendingCount');
  print('   Truly synced (with timestamp): $trulySync');
  if (resetDates.isNotEmpty) {
    final sortedDates = resetDates.toList()..sort();
    print('   Affected dates: ${sortedDates.join(', ')}');
  }
  print('\n💡 NEXT STEPS:');
  print('   1. Open the GMWF app (Server mode)');
  print('   2. The app will automatically detect $resetCount unsynced records');
  print('   3. They will be uploaded to Firestore in the background');
  print('   4. Check attendance in the app — all historical records should appear');
  print('═══════════════════════════════════════════════════════════════');
}
