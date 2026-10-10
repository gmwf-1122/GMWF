import 'dart:io';
import 'package:hive/hive.dart';

class Fallback132Adapter extends TypeAdapter<dynamic> {
  @override
  final int typeId = 132;
  @override
  dynamic read(BinaryReader reader) {
    try {
      final numOfFields = reader.readByte();
      final map = <dynamic, dynamic>{};
      for (var i = 0; i < numOfFields; i++) {
        final key = reader.read();
        final value = reader.read();
        map[key] = value;
      }
      return map;
    } catch (_) {
      return null;
    }
  }
  @override
  void write(BinaryWriter writer, dynamic obj) {}
}

class TimestampDummy {
  final int seconds;
  final int nanoseconds;
  TimestampDummy(this.seconds, this.nanoseconds);
}

class TimestampAdapterDummy extends TypeAdapter<TimestampDummy> {
  @override
  final int typeId = 100;
  @override
  TimestampDummy read(BinaryReader reader) {
    return TimestampDummy(reader.readInt(), reader.readInt());
  }
  @override
  void write(BinaryWriter writer, TimestampDummy obj) {
    writer.writeInt(obj.seconds);
    writer.writeInt(obj.nanoseconds);
  }
}

void main() async {
  final tempDir = Directory.systemTemp.createTempSync('hive_inspect');
  final srcFile = File(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive\local_stock_items.hive');
  srcFile.copySync('${tempDir.path}\\local_stock_items.hive');
  Hive.init(tempDir.path);
  Hive.registerAdapter(Fallback132Adapter(), override: true);
  Hive.registerAdapter(TimestampAdapterDummy(), override: true);
  final box = await Hive.openBox('local_stock_items');
  print('Total keys in local_stock_items Hive: ${box.length}');
  int count = 0;
  for (final k in box.keys) {
    final v = box.get(k);
    if (v is Map) {
      if (v['branchId'] == 'karachi' || (v['branchId'] == null && (v['campId'] != null || v['dispensaryId'] != null))) {
        print('KARACHI ITEM: key=$k | map=$v');
        count++;
        if (count >= 10) break;
      }
    }
  }
  await box.close();
}
