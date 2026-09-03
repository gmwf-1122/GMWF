import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  Hive.init(hiveDir.path);

  print('=== CHECKING HIVE FOR HAJI CAMP & DOCTORS ===');

  if (await Hive.boxExists('local_entries')) {
    final box = await Hive.openBox('local_entries');
    print('Total entries in local_entries: ${box.length}');
    final hajiEntries = <Map>[];
    for (final k in box.keys) {
      final v = box.get(k);
      if (v is Map) {
        final s = v.toString().toLowerCase();
        final camp = (v['campId'] ?? v['dispensaryId'] ?? v['dispensaryTag'] ?? '').toString().toLowerCase();
        final serial = (v['serial'] ?? v['id'] ?? '').toString().toLowerCase();
        if (camp.contains('haji') || serial.contains('haji') || s.contains('zabi')) {
          hajiEntries.add(v);
        }
      }
    }
    print('Total Haji Camp or Zabiullah entries: ${hajiEntries.length}');
    for (int i = 0; i < hajiEntries.length && i < 15; i++) {
      final e = hajiEntries[i];
      print('--- Entry ${i + 1} ---');
      print('  serial: ${e['serial'] ?? e['id']}');
      print('  patientName: ${e['patientName'] ?? e['name']}');
      print('  patientId: ${e['patientId']}');
      print('  cnic: ${e['cnic'] ?? e['patientCnic']}');
      print('  doctorName: ${e['doctorName'] ?? e['assignedDoctor'] ?? e['activeDoctor']}');
      print('  campId: ${e['campId'] ?? e['dispensaryId']}');
      print('  status: ${e['status']}');
      print('  prescription: ${e['prescription'] != null ? "HAS PRESC" : "NO PRESC"}');
    }
    await box.close();
  }

  if (await Hive.boxExists('local_prescriptions')) {
    final box = await Hive.openBox('local_prescriptions');
    print('\nTotal in local_prescriptions: ${box.length}');
    int hajiPCount = 0;
    for (final k in box.keys) {
      final v = box.get(k);
      if (v is Map) {
        final s = v.toString().toLowerCase();
        if (s.contains('haji') || s.contains('zabi')) {
          hajiPCount++;
          if (hajiPCount <= 5) {
            print('  Presc $k: doc=${v['doctorName']}, patient=${v['patientName']}, serial=${v['serial']}');
          }
        }
      }
    }
    print('Total Haji Camp or Zabiullah prescriptions: $hajiPCount');
    await box.close();
  }

  print('\n=== CHECKING APP SETTINGS ===');
  if (await Hive.boxExists('app_settings')) {
    final box = await Hive.openBox('app_settings');
    print('active_camp_id: ${box.get('active_camp_id')}');
    print('current_branch_id: ${box.get('current_branch_id')}');
    print('currentUser / user_data: ${box.get('user_data') ?? box.get('currentUser')}');
    await box.close();
  }
}
