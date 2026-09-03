import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  Hive.init(hiveDir.path);
  final box = await Hive.openBox('local_prescriptions');
  print('Total in local_prescriptions: ${box.length}');
  for (final k in box.keys) {
    final v = box.get(k);
    if (v is Map) {
      final s = v.toString().toLowerCase();
      if (s.contains('zabi') || s.contains('haji')) {
        print('Key: $k');
        print('  serial: ${v["serial"]} | id: ${v["id"]}');
        print('  name: ${v["patientName"] ?? v["name"]}');
        print('  cnic: ${v["cnic"] ?? v["patientCnic"]}');
        print('  patientId: ${v["patientId"]}');
        print('  doctorName: ${v["doctorName"] ?? v["prescribedBy"]}');
        print('  complaint: ${v["complaint"]} | diagnosis: ${v["diagnosis"]}');
        print('  prescriptions: ${v["prescriptions"]}');
      }
    }
  }
  await box.close();
}
