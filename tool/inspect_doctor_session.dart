import 'dart:io';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';

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
  final tempDir = Directory.systemTemp.createTempSync('doctor_inspect');
  for (final f in hiveDir.listSync().whereType<File>()) {
    if (f.path.endsWith('.hive')) {
      f.copySync('${tempDir.path}\\${f.uri.pathSegments.last}');
    }
  }
  Hive.init(tempDir.path);
  Hive.registerAdapter(Fallback132Adapter(), override: true);
  Hive.registerAdapter(TimestampAdapterDummy(), override: true);

  final stockBox = await Hive.openBox(LocalStorageService.stockBox);
  await Hive.openBox(LocalStorageService.entriesBox);
  await Hive.openBox(LocalStorageService.prescriptionsBox);

  print('Stock box length: ${stockBox.length}');
  int jljStock = 0;
  for (final k in stockBox.keys) {
    final v = stockBox.get(k);
    if (v is Map) {
      final b = (v['branchId'] ?? '').toString().toLowerCase();
      if (b.contains('jalal')) {
        jljStock++;
        if (jljStock <= 5) {
          print('JLJ STOCK: name=${v['name']}, formula=${v['formula']}, qty=${v['quantity']}, dose=${v['dose']}, type=${v['type']}');
        }
      }
    }
  }
  print('Total JLJ stock items: $jljStock');

  final entriesBox = Hive.box(LocalStorageService.entriesBox);
  print('Entries box length: ${entriesBox.length}');
  int jljEntries = 0;
  for (final k in entriesBox.keys) {
    final v = entriesBox.get(k);
    if (v is Map) {
      final b = (v['branchId'] ?? '').toString().toLowerCase();
      if (b.contains('jalal')) {
        jljEntries++;
        if (jljEntries <= 5) {
          print('JLJ ENTRY: serial=${v['serial']}, name=${v['patientName'] ?? v['name']}, status=${v['status']}');
        }
      }
    }
  }
  print('Total JLJ entries: $jljEntries');
}
