import 'dart:io';
import 'package:hive/hive.dart';

class Dummy132 {
  final dynamic val;
  Dummy132([this.val]);
}

class Fallback132Adapter extends TypeAdapter<Dummy132> {
  @override
  final int typeId = 132;

  @override
  Dummy132 read(BinaryReader reader) {
    try {
      final numOfFields = reader.readByte();
      final map = <dynamic, dynamic>{};
      for (var i = 0; i < numOfFields; i++) {
        final key = reader.read();
        final value = reader.read();
        map[key] = value;
      }
      return Dummy132(map);
    } catch (_) {
      return Dummy132();
    }
  }

  @override
  void write(BinaryWriter writer, Dummy132 obj) {}
}

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  Hive.init(hiveDir.path);
  Hive.registerAdapter<Dummy132>(Fallback132Adapter(), override: true);
  print('Is 132 registered: ${Hive.isAdapterRegistered(132)}');

  print('Trying to open app_settings with Fallback132Adapter...');
  try {
    final box = await Hive.openBox('app_settings');
    print('✅ SUCCESS! app_settings has ${box.length} keys:');
    for (final k in box.keys) {
      final v = box.get(k);
      print('  $k: ${v is Map ? v.keys : v}');
    }
    await box.close();
  } catch (e) {
    print('❌ FAILED: $e');
  }

  print('\nTrying to open local_users with Fallback132Adapter...');
  try {
    final box = await Hive.openBox('local_users');
    print('✅ SUCCESS! local_users has ${box.length} keys:');
    for (final k in box.keys) {
      print('  $k');
    }
    await box.close();
  } catch (e) {
    print('❌ FAILED: $e');
  }
}
