import 'dart:io';
import 'package:hive/hive.dart';

class Adapter132 extends TypeAdapter<dynamic> {
  @override
  final int typeId = 132;
  @override
  dynamic read(BinaryReader reader) {
    try {
      final numOfFields = reader.readByte();
      final fields = <int, dynamic>{};
      for (var i = 0; i < numOfFields; i++) {
        final key = reader.readByte();
        fields[key] = reader.read();
      }
      return fields;
    } catch (_) {
      return {};
    }
  }
  @override
  void write(BinaryWriter writer, dynamic obj) {}
}

class Adapter100 extends TypeAdapter<dynamic> {
  @override
  final int typeId = 100;
  @override
  dynamic read(BinaryReader reader) {
    try {
      final s = reader.readInt();
      final n = reader.readInt();
      return {'seconds': s, 'nanoseconds': n};
    } catch (_) {
      return {};
    }
  }
  @override
  void write(BinaryWriter writer, dynamic obj) {}
}

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_sync_audit');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);

  final syncFile = File('${hiveSourceDir.path}\\sync_queue.hive');
  if (syncFile.existsSync()) {
    syncFile.copySync('${tempDir.path}\\sync_queue.hive');
  }

  Hive.init(tempDir.path);
  Hive.registerAdapter(Adapter132());
  Hive.registerAdapter(Adapter100());

  final box = await Hive.openBox('sync_queue');
  print('=== DETAILED AUDIT OF SYNC QUEUE (${box.length} items) ===');

  int attPrinted = 0;
  for (final key in box.keys) {
    final item = box.get(key);
    if (item is Map) {
      final type = item['type'] ?? item[0];
      if (type == 'save_attendance_record' && attPrinted < 5) {
        attPrinted++;
        print('\n--- Attendance Item #$attPrinted (key: $key) ---');
        item.forEach((k, v) {
          print('  $k: $v');
        });
      }
    }
  }

  print('\nSample of other items:');
  int otherPrinted = 0;
  for (final key in box.keys) {
    final item = box.get(key);
    if (item is Map) {
      final type = item['type'] ?? item[0];
      if (type != 'save_attendance_record' && otherPrinted < 5) {
        otherPrinted++;
        print('\n--- Other Item ($type) (key: $key) ---');
        item.forEach((k, v) {
          print('  $k: $v');
        });
      }
    }
  }

  await box.close();
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
}
