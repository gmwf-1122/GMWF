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
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_stress_audit');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);

  // Copy sync_queue.hive
  final syncFile = File('${hiveSourceDir.path}\\sync_queue.hive');
  if (syncFile.existsSync()) {
    syncFile.copySync('${tempDir.path}\\sync_queue.hive');
  }

  // Copy local_entries.hive
  final entriesFile = File('${hiveSourceDir.path}\\local_entries.hive');
  if (entriesFile.existsSync()) {
    entriesFile.copySync('${tempDir.path}\\local_entries.hive');
  }

  Hive.init(tempDir.path);
  Hive.registerAdapter(Adapter132(), override: true);
  Hive.registerAdapter(Adapter100(), override: true);

  print('=== AUDIT SYNC QUEUE ===');
  if (syncFile.existsSync()) {
    final sBox = await Hive.openBox('sync_queue');
    print('Total items in sync_queue: ${sBox.length}');
    final typeCounts = <String, int>{};
    for (final k in sBox.keys) {
      final v = sBox.get(k);
      if (v is Map) {
        final t = (v['type'] ?? v['action'] ?? v['event_type'] ?? 'unknown').toString();
        typeCounts[t] = (typeCounts[t] ?? 0) + 1;
      }
    }
    print('Types in sync_queue:');
    typeCounts.forEach((t, c) => print('  $t: $c'));
    await sBox.close();
  }

  print('\n=== AUDIT LOCAL ENTRIES ===');
  if (entriesFile.existsSync()) {
    final eBox = await Hive.openBox('local_entries');
    print('Total items in local_entries: ${eBox.length}');
    int stressCount = 0;
    final stressPrefixes = <String, int>{};
    final sampleStress = <String>[];
    for (final k in eBox.keys) {
      final v = eBox.get(k);
      String serial = '';
      bool isStress = false;
      if (v is Map) {
        serial = (v['serial'] ?? v['id'] ?? k.toString()).toString();
        isStress = v['isStressTest'] == true ||
            serial.startsWith('FLD-') ||
            serial.startsWith('COL-') ||
            serial.startsWith('OUT-') ||
            (v['patientName']?.toString().contains('Flood') ?? false);
      } else {
        serial = k.toString();
        isStress = serial.contains('FLD-') || serial.contains('COL-') || serial.contains('OUT-');
      }
      if (isStress) {
        stressCount++;
        final prefix = serial.contains('-') ? serial.split('-').first : 'other';
        stressPrefixes[prefix] = (stressPrefixes[prefix] ?? 0) + 1;
        if (sampleStress.length < 5) sampleStress.add('$k -> $serial');
      }
    }
    print('Stress test items in local_entries: $stressCount / ${eBox.length}');
    stressPrefixes.forEach((p, c) => print('  Prefix $p: $c'));
    if (sampleStress.isNotEmpty) {
      print('Samples:');
      for (final s in sampleStress) print('  $s');
    }
    await eBox.close();
  }

  tempDir.deleteSync(recursive: true);
}
