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
  print('APPDATA: $appData');
  
  // Find where gmwf hive files are stored
  final candidates = [
    p.join(appData, 'com.example', 'gmwf', 'gmwf_hive'),
    p.join(appData, 'gmwf', 'gmwf_hive'),
    p.join(appData, 'gmwf'),
  ];
  
  Directory? sourceDir;
  for (final c in candidates) {
    final d = Directory(c);
    if (d.existsSync()) {
      sourceDir = d;
      break;
    }
  }

  if (sourceDir == null) {
    print('No hive directory found in APPDATA candidates');
    return;
  }

  print('Reading hive from: ${sourceDir.path}');
  final tempDir = Directory(p.join(Directory.current.path, 'test', 'temp_hive_patients'));
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync(recursive: true);

  for (final file in sourceDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      file.copySync(p.join(tempDir.path, p.basename(file.path)));
    }
  }

  Hive.init(tempDir.path);
  Hive.registerAdapter(TimestampAdapter());

  try {
    final pBox = await Hive.openBox('local_patients');
    print('local_patients box length: ${pBox.length}');
    print('Keys: ${pBox.keys.toList()}');
    for (final k in pBox.keys) {
      final v = pBox.get(k);
      print('KEY [$k]: $v');
    }
  } catch (e) {
    print('Error opening local_patients: $e');
  }

  await Hive.close();
  try {
    tempDir.deleteSync(recursive: true);
  } catch (_) {}
}
