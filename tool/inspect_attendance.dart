import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:hive/hive.dart';

void main() async {
  final hiveDir = r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive';
  final tempDir = Directory.systemTemp.createTempSync('hive_inspect_');

  // Copy .hive files to tempDir
  for (final file in Directory(hiveDir).listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final dest = p.join(tempDir.path, p.basename(file.path));
      try {
        file.copySync(dest);
      } catch (e) {
        // ignore locked if any
      }
    }
  }

  Hive.init(tempDir.path);
  try {
    final boxesToScan = [
      'local_employees',
      'local_madrassa_students',
      'local_school_students',
      'local_madrassa_logs',
      'local_school_logs',
      'local_biometric_credentials',
      'local_users',
    ];
    for (final bName in boxesToScan) {
      try {
        final b = await Hive.openBox(bName);
        print('\n--- SCANNING $bName (${b.length}) ---');
        for (final k in b.keys) {
          try {
            final v = b.get(k);
            if (v != null) {
              final str = v.toString().toLowerCase();
              if (str.contains('haroon')) {
                print('FOUND in $bName: key=$k');
                print('data: $v');
              }
            }
          } catch (_) {}
        }
      } catch (e) {
        print('Error scanning $bName: $e');
      }
    }
    return;


  } catch (e) {
    print('Error opening devBox: $e');
  }


  try {
    final attBox = await Hive.openBox('local_employee_attendance');

    print('\n--- ALL ATTENDANCE FOR 163 and 136 ---');
    for (final key in attBox.keys) {
      final v = attBox.get(key);
      if (v is Map) {
        final pin = (v['pin'] ?? v['biometricPin'] ?? '').toString();
        final shifts = v['shifts'];
        if (pin == '163' || pin == '136') {
          print('ATT: key=$key | date=${v['date']} | empId=${v['employeeId']} | name=${v['employeeName'] ?? v['name']} | pin=$pin | in=${v['checkInTime']} | out=${v['checkOutTime']} | shifts=$shifts');
        }
      }
    }
  } catch (e) {
    print('Error opening local_employee_attendance: $e');
  }

  try {
    final crossBox = await Hive.openBox('local_cross_branch_punches');
    print('\n--- ALL CROSS BRANCH PUNCHES FOR 163 and 136 ---');
    for (final key in crossBox.keys) {
      final v = crossBox.get(key);
      if (v is Map) {
        final pin = (v['pin'] ?? '').toString();
        if (pin == '163' || pin == '136') {
          print('CROSS: pin=$pin | time=${v['timestamp']} | branch=${v['punchBranchName'] ?? v['punchBranchId']} | dev=${v['deviceName']} | loc=${v['buildingLocation']}');
        }
      }
    }
  } catch (e) {
    print('Error opening crossBox: $e');
  }

  try {
    final unmappedBox = await Hive.openBox('local_unmapped_punches');
    print('\n--- ALL UNMAPPED PUNCHES FOR 163 and 136 ---');
    for (final key in unmappedBox.keys) {
      final v = unmappedBox.get(key);
      if (v is Map) {
        final pin = (v['pin'] ?? '').toString();
        if (pin == '163' || pin == '136') {
          print('UNMAPPED: pin=$pin | time=${v['timestamp']} | ip=${v['deviceIp']} | dev=${v['deviceName']}');
        }
      }
    }
  } catch (e) {
    print('Error: $e');
  }



  try {
    final attBox = await Hive.openBox('local_employee_attendance');
    print('\nTotal attendance records in box: ${attBox.length}');
    for (final key in attBox.keys) {
      final v = attBox.get(key);
      if (v is Map) {
        final empId = (v['employeeId'] ?? v['localId'] ?? '').toString();
        final name = (v['employeeName'] ?? v['name'] ?? '').toString().toLowerCase();
        final pin = (v['pin'] ?? v['biometricPin'] ?? '').toString();
        if (name.contains('farrukh') || name.contains('kashif') || pin == '163' || pin == '136' || name.contains('ans')) {
          print('--- ATTENDANCE: key=$key ---');
          print('date: ${v['date']}, name: ${v['employeeName'] ?? v['name']}, pin: $pin, in: ${v['checkInTime']}, out: ${v['checkOutTime']}, shifts: ${v['shifts']}');
        }
      }
    }
  } catch (e) {
    print('Error opening local_employee_attendance: $e');
  }

  try {
    final unmappedBox = await Hive.openBox('local_unmapped_punches');
    print('\nTotal unmapped punches in box: ${unmappedBox.length}');
    for (final key in unmappedBox.keys) {
      final v = unmappedBox.get(key);
      if (v is Map) {
        final pin = (v['pin'] ?? '').toString();
        if (pin == '163' || pin == '136') {
          print('UNMAPPED PUNCH: key=$key -> $v');
        }
      }
    }
  } catch (e) {
    print('Error opening unmappedBox: $e');
  }

  try {
    final crossBox = await Hive.openBox('local_cross_branch_punches');
    print('\nTotal cross branch punches in box: ${crossBox.length}');
    for (final key in crossBox.keys) {
      final v = crossBox.get(key);
      if (v is Map) {
        final pin = (v['pin'] ?? '').toString();
        if (pin == '163' || pin == '136') {
          print('CROSS BRANCH PUNCH: key=$key -> $v');
        }
      }
    }
  } catch (e) {
    print('Error opening crossBox: $e');
  }

  try {
    tempDir.deleteSync(recursive: true);
  } catch (_) {}
}
