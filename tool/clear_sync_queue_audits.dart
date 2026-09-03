import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  Hive.init(hiveDir.path);
  final box = await Hive.openBox('local_sync_queue');
  print('Initial sync queue count: ${box.length}');
  final keysToDelete = <dynamic>[];
  for (final k in box.keys) {
    final v = box.get(k);
    if (v is Map && v['type'] == 'save_audit_log') {
      keysToDelete.add(k);
    }
  }
  print('Found ${keysToDelete.length} audit logs in sync queue to clear');
  for (final k in keysToDelete) {
    await box.delete(k);
  }
  print('Remaining in sync queue: ${box.length}');
  await box.close();
}
