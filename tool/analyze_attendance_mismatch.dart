import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_attendance_audit');
  Hive.init(tempDir.path);

  final attBox = await Hive.openBox('local_employee_attendance');
  print('=== TOTAL ATTENDANCE RECORDS: ${attBox.length} ===\n');

  int rootInNoOut = 0;
  int rootBothInOut = 0;
  int shiftBothInOut = 0;
  int shiftInNoOut = 0;
  int rootNullShiftHasOut = 0;
  int dateMismatchCount = 0;
  int noDateCount = 0;
  int hexKeyCount = 0;
  int totalNotSynced = 0;
  int trueSyncedNoLastSyncAt = 0;

  final dateStats = <String, Map<String, int>>{};

  for (final key in attBox.keys) {
    final raw = attBox.get(key);
    if (raw is! Map) continue;
    final r = raw;

    final keyStr = key.toString();
    final d = r['date']?.toString();
    final empId = (r['employeeId'] ?? r['empId'] ?? r['id'])?.toString();

    if (d == null || d.isEmpty) {
      noDateCount++;
    } else {
      dateStats.putIfAbsent(d, () => {'total': 0, 'in': 0, 'out': 0, 'synced': 0, 'unsynced': 0});
      dateStats[d]!['total'] = dateStats[d]!['total']! + 1;
    }

    if (keyStr.length > 20 && !keyStr.contains('_')) {
      hexKeyCount++;
    }

    // Check date mismatch between key and record
    if (d != null && keyStr.contains('_')) {
      final keyParts = keyStr.split('_');
      final keyDate = keyParts.last;
      if (keyDate != d && keyDate.length == 10) {
        dateMismatchCount++;
        print('DATE MISMATCH: key=$keyStr recordDate=$d');
      }
    }

    final rootIn = r['checkInTime'] ?? r['arrivalTime'];
    final rootOut = r['checkOutTime'] ?? r['departureTime'];

    if (rootIn != null && (rootOut == null || rootOut.toString() == '--:--')) {
      rootInNoOut++;
    } else if (rootIn != null && rootOut != null && rootOut.toString() != '--:--') {
      rootBothInOut++;
      if (d != null) dateStats[d]!['out'] = (dateStats[d]!['out'] ?? 0) + 1;
    }
    if (rootIn != null && d != null) {
      dateStats[d]!['in'] = (dateStats[d]!['in'] ?? 0) + 1;
    }

    // Check shifts
    final shifts = r['shifts'];
    if (shifts is Map) {
      for (final s in shifts.values) {
        if (s is Map) {
          final sIn = s['checkInTime'] ?? s['arrivalTime'];
          final sOut = s['checkOutTime'] ?? s['departureTime'];
          if (sIn != null && sOut != null && sOut.toString() != '--:--') {
            shiftBothInOut++;
            if (rootOut == null || rootOut.toString() == '--:--') {
              rootNullShiftHasOut++;
              print('MISMATCH: Root checkOut is null, but shift has checkOut: key=$key rootIn=$rootIn shiftOut=$sOut');
            }
          } else if (sIn != null) {
            shiftInNoOut++;
          }
        }
      }
    }

    final isSynced = r['synced'] == true && r['syncStatus'] == 'synced';
    if (!isSynced) {
      totalNotSynced++;
      if (d != null) dateStats[d]!['unsynced'] = (dateStats[d]!['unsynced'] ?? 0) + 1;
    } else {
      if (d != null) dateStats[d]!['synced'] = (dateStats[d]!['synced'] ?? 0) + 1;
    }

    if (r['synced'] == true && r['lastSyncedAt'] == null) {
      trueSyncedNoLastSyncAt++;
    }
  }

  print('\n--- MISMATCH AUDIT ---');
  print('Date mismatch between key & record date: $dateMismatchCount');
  print('Hex keys (not empId_YYYY-MM-DD): $hexKeyCount');
  print('Records with root check-in and check-out: $rootBothInOut');
  print('Records with root check-in but NO check-out: $rootInNoOut');
  print('Shifts with both check-in and check-out: $shiftBothInOut');
  print('Records where shift has checkout but ROOT checkOut is null: $rootNullShiftHasOut');
  print('synced == true BUT lastSyncedAt is null: $trueSyncedNoLastSyncAt');
  print('Total records not properly synced: $totalNotSynced');

  print('\n--- DATES SUMMARY ---');
  final sortedDates = dateStats.keys.toList()..sort();
  for (final dt in sortedDates) {
    final s = dateStats[dt]!;
    print('$dt: Total=${s['total']}, In=${s['in']}, Out=${s['out']}, Synced=${s['synced']}, Unsynced=${s['unsynced']}');
  }

  await attBox.close();
}
