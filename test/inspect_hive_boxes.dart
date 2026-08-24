import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';

class TimestampAdapter extends TypeAdapter<Timestamp> {
  @override
  final int typeId = 132;

  @override
  Timestamp read(BinaryReader reader) {
    final seconds = reader.readInt();
    final nanoseconds = reader.readInt();
    return Timestamp(seconds, nanoseconds);
  }

  @override
  void write(BinaryWriter writer, Timestamp obj) {
    writer.writeInt(obj.seconds);
    writer.writeInt(obj.nanoseconds);
  }
}

void main() async {
  final appData = Platform.environment['APPDATA'] ?? '';
  final sourceHiveDir = p.join(appData, 'com.example', 'gmwf', 'gmwf_hive');
  final tempDir = Directory(p.join(Directory.current.path, 'test', 'temp_hive2'));
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync(recursive: true);

  // Copy .hive files
  final srcDir = Directory(sourceHiveDir);
  for (final file in srcDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final destPath = p.join(tempDir.path, p.basename(file.path));
      file.copySync(destPath);
    }
  }

  print('Copied hive files to: ${tempDir.path}');
  Hive.init(tempDir.path);
  Hive.registerAdapter(TimestampAdapter());

  for (final file in tempDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final boxName = p.basenameWithoutExtension(file.path);
      try {
        final box = await Hive.openBox(boxName);
        for (final key in box.keys) {
          final val = box.get(key);
          final strVal = val.toString();
          final keyStr = key.toString();
          if (keyStr.contains('017') || strVal.contains('017') || keyStr.contains('SADD') || strVal.contains('SADD') || keyStr.contains('220826') || strVal.contains('220826')) {
            print('[$boxName] KEY: $key');
            if (val is Map) {
              print('   -> patientName: ${val['patientName'] ?? val['name']} | serial: ${val['serial']} | dateKey: ${val['dateKey'] ?? val['dispenseDate']} | status: ${val['status']}');
            }
          }
        }
      } catch (e) {
        print('Error reading $boxName: $e');
      }
    }
  }

  exit(0);
}
