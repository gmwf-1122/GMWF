import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_app_settings');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync(recursive: true);

  final f = File('${hiveSourceDir.path}\\app_settings.hive');
  if (f.existsSync()) {
    f.copySync('${tempDir.path}\\app_settings.hive');
    Hive.init(tempDir.path);
    final box = await Hive.openBox('app_settings');
    print('app_settings count: ${box.length}');
    for (final k in box.keys) {
      final v = box.get(k);
      String preview = v.toString();
      if (preview.length > 80) preview = '${preview.substring(0, 80)}...';
      print('  $k => $preview');
    }
    await box.close();
  } else {
    print('app_settings.hive does not exist');
  }
  tempDir.deleteSync(recursive: true);
}
