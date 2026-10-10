import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_attendance_audit');
  if (!tempDir.existsSync()) tempDir.createSync(recursive: true);

  for (final name in ['local_employee_attendance.hive', 'local_employee_attendance.lock', 'sync_queue.hive', 'sync_queue.lock']) {
    final src = File('${hiveSourceDir.path}\\$name');
    if (src.existsSync()) src.copySync('${tempDir.path}\\$name');
  }

  Hive.init(tempDir.path);
  final box = await Hive.openBox('local_employee_attendance');
  print('Total attendance in Hive: ${box.length}');
  
  int syncedTrueCount = 0;
  int syncedFalseCount = 0;
  int nullSyncCount = 0;
  final dates = <String, int>{};
  final sampleRecords = <Map>[];

  for (var key in box.keys) {
    final rec = box.get(key);
    if (rec is Map) {
      final date = rec['date']?.toString() ?? 'no_date';
      dates[date] = (dates[date] ?? 0) + 1;

      if (rec['synced'] == true) {
        syncedTrueCount++;
      } else if (rec['synced'] == false) {
        syncedFalseCount++;
      } else {
        nullSyncCount++;
      }

      if (sampleRecords.length < 15) {
        sampleRecords.add({
          'key': key,
          'empId': rec['employeeId'],
          'name': rec['employeeName'] ?? rec['name'],
          'date': rec['date'],
          'in': rec['checkInTime'],
          'out': rec['checkOutTime'],
          'synced': rec['synced'],
          'syncStatus': rec['syncStatus'],
          'lastSyncedAt': rec['lastSyncedAt'],
          'shifts': rec['shifts'],
        });
      }
    }
  }

  print('\n--- Sync Status Counts ---');
  print('synced == true: $syncedTrueCount');
  print('synced == false: $syncedFalseCount');
  print('synced == null: $nullSyncCount');

  print('\n--- Date Distribution ---');
  final sortedDates = dates.keys.toList()..sort();
  for (final d in sortedDates) {
    print('$d: ${dates[d]} records');
  }

  print('\n--- Sample Records ---');
  for (final s in sampleRecords) {
    print('Key: ${s['key']}');
    print('  Emp: ${s['name']} (${s['empId']}) | Date: ${s['date']}');
    print('  Times: In=${s['in']}, Out=${s['out']}');
    print('  Sync: synced=${s['synced']}, status=${s['syncStatus']}, lastSyncedAt=${s['lastSyncedAt']}');
    print('  Shifts: ${s['shifts']}');
    print('----------------------------------------------------');
  }

  // Also check sync_queue box if available
  try {
    final sBox = await Hive.openBox('sync_queue');
    print('\nTotal items in sync_queue: ${sBox.length}');
    int attInQueue = 0;
    for (var key in sBox.keys) {
      final item = sBox.get(key);
      if (item is Map && (item['type'] == 'save_attendance_record' || item['type'] == 'save_attendance')) {
        attInQueue++;
        if (attInQueue <= 5) {
          print('Queue Item $key: date=${item['date']}, emp=${item['employeeId']}, type=${item['type']}');
        }
      }
    }
    print('Attendance items currently in sync_queue: $attInQueue');
    await sBox.close();
  } catch (e) {
    print('Could not read sync_queue: $e');
  }

  await box.close();
}
