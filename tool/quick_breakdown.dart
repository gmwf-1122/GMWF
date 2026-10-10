import 'dart:io';
import 'package:hive/hive.dart';
import 'inspect_sync_queue_details.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_sync_audit2');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);
  final syncFile = File('${hiveSourceDir.path}\\sync_queue.hive');
  if (syncFile.existsSync()) syncFile.copySync('${tempDir.path}\\sync_queue.hive');

  Hive.init(tempDir.path);
  Hive.registerAdapter(Adapter132());
  Hive.registerAdapter(Adapter100());

  final box = await Hive.openBox('sync_queue');
  print('Total items: ${box.length}');
  print('First 10 keys:');
  for (final k in box.keys.take(10)) {
    final v = box.get(k);
    if (v is Map) {
      print('Key: $k -> type: ${v['type']} branchId: ${v['branchId']} attempts: ${v['attempts']} nextRetryAt: ${v['nextRetryAt']}');
    } else {
      print('Key: $k -> NON-MAP: $v');
    }
  }
  await box.close();
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
}
