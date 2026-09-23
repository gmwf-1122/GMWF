import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_sync_audit');
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync(recursive: true);

  final syncFile = File('${hiveSourceDir.path}\\sync_queue.hive');
  if (!syncFile.existsSync()) {
    print('Sync file does not exist at ${syncFile.path}');
    return;
  }
  syncFile.copySync('${tempDir.path}\\sync_queue.hive');

  Hive.init(tempDir.path);
  final box = await Hive.openBox('sync_queue');
  print('Total items in sync_queue: ${box.length}');
  final counts = <String, int>{};
  final sampleItems = <String, dynamic>{};
  for (final k in box.keys) {
    final v = box.get(k);
    if (v is Map) {
      final t = (v['type'] ?? v['action'] ?? 'unknown').toString();
      counts[t] = (counts[t] ?? 0) + 1;
      if (!sampleItems.containsKey(t)) {
        sampleItems[t] = v;
      }
    } else {
      counts['non-map'] = (counts['non-map'] ?? 0) + 1;
    }
  }
  print('Counts by type:');
  counts.forEach((k, v) => print('  $k: $v'));
  
  print('\nDetails:');
  for (final entry in sampleItems.entries) {
    print('--- Type: ${entry.key} ---');
    final sample = entry.value;
    if (sample is Map) {
      print('  keys: ${sample.keys.toList()}');
      print('  branchId: ${sample['branchId']}');
      print('  entityId: ${sample['entityId']}');
      print('  status: ${sample['status']}');
      print('  lastError: ${sample['lastError']}');
      print('  attempts: ${sample['attempts']}');
    }
  }
  await box.close();
  tempDir.deleteSync(recursive: true);
}
