import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  Hive.init(hiveDir.path);
  for (final name in ['local_users', 'local_employees', 'local_entries', 'local_patients', 'local_tokens', 'doctor_prescriptions']) {
    try {
      final box = await Hive.openBox(name);
      int found = 0;
      for (final k in box.keys) {
        final val = box.get(k);
        final s = val.toString().toLowerCase();
        if (s.contains('zabi') || s.contains('ullah')) {
          print('Found in $name key $k:');
          if (val is Map) {
            print('  name: ${val['name'] ?? val['username'] ?? val['patientName']}');
            print('  doctor: ${val['doctor'] ?? val['doctorName'] ?? val['assignedDoctor']}');
            print('  camp: ${val['campId'] ?? val['dispensaryId'] ?? val['branchId']}');
            print('  id/serial: ${val['id'] ?? val['serial'] ?? val['patientId']}');
          } else {
            print('  val: $val');
          }
          found++;
          if (found >= 10) break;
        }
      }
      if (found == 0) {
        // print('No match in $name');
      }
      await box.close();
    } catch (e) {
      print('Error opening $name: $e');
    }
  }

  // Also query Firestore for any user/doctor named Zabiullah
  const projectId = 'gmwf-8fc4c';
  const apiKey = 'AIzaSyDA6MmTuZIPIxylV372s8zh-ndbShHwwAk';
  const baseUrl = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  final client = HttpClient();
  for (final col in ['users', 'doctors', 'employees']) {
    try {
      final uri = Uri.parse('$baseUrl/branches/karachi/$col?key=$apiKey');
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (body.toLowerCase().contains('zabi')) {
        print('Firestore branch karachi $col contains zabi!');
        final json = jsonDecode(body);
        final docs = json['documents'] as List? ?? [];
        for (final d in docs) {
          if (jsonEncode(d).toLowerCase().contains('zabi')) {
            print('  Doc: ${d['name']}');
          }
        }
      }
    } catch (_) {}
  }
  client.close();

  print('Done finding Zabiullah.');
}
