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
  TimestampDummy read(BinaryReader reader) => TimestampDummy(reader.readInt(), reader.readInt());
  @override
  void write(BinaryWriter writer, TimestampDummy obj) {
    writer.writeInt(obj.seconds);
    writer.writeInt(obj.nanoseconds);
  }
}

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory.systemTemp.createTempSync('entries_inspect');
  File('${hiveDir.path}\\local_entries.hive').copySync('${tempDir.path}\\local_entries.hive');
  File('${hiveDir.path}\\local_prescriptions.hive').copySync('${tempDir.path}\\local_prescriptions.hive');
  Hive.init(tempDir.path);
  Hive.registerAdapter(Fallback132Adapter(), override: true);
  Hive.registerAdapter(TimestampAdapterDummy(), override: true);

  final entriesBox = await Hive.openBox('local_entries');
  final prescBox = await Hive.openBox('local_prescriptions');
  print('Total entries: ${entriesBox.length}');
  for (final k in entriesBox.keys) {
    final v = entriesBox.get(k);
    if (v is Map && (v['branchId'] ?? '').toString().toLowerCase().contains('jalal')) {
      print('ENTRY: key=$k, serial=${v['serial']}, name=${v['patientName'] ?? v['name']}, status=${v['status']}, hasPresc=${v['prescription'] != null}');
      if (v['prescription'] is Map) {
        final p = v['prescription'] as Map;
        print('   PRESC meds=${p['prescriptions']}');
      }
    }
  }
  print('Total prescs: ${prescBox.length}');
  for (final k in prescBox.keys) {
    final v = prescBox.get(k);
    if (v is Map && (v['branchId'] ?? '').toString().toLowerCase().contains('jalal')) {
      print('PRESC: key=$k, serial=${v['serial']}, name=${v['patientName'] ?? v['name']}, meds=${v['prescriptions']}');
    }
  }
}
