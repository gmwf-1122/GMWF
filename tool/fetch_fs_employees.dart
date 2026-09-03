import 'dart:convert';
import 'dart:io';

const projectId = 'gmwf-8fc4c';
const apiKey = 'AIzaSyDA6MmTuZIPIxylV372s8zh-ndbShHwwAk';
const baseUrl = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

Future<Map<String, dynamic>?> fetchJson(String path) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl$path${path.contains('?') ? '&' : '?'}key=$apiKey&pageSize=500');
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 200) {
      return jsonDecode(body) as Map<String, dynamic>;
    } else {
      print('HTTP ${response.statusCode} for $path: $body');
      return null;
    }
  } catch (e) {
    print('Error fetching $path: $e');
    return null;
  } finally {
    client.close();
  }
}

Future<void> main() async {
  print('=== 🔍 QUERYING FIRESTORE EMPLOYEES ===');
  for (final branch in ['karachi', 'gujrat', 'jalalpurjattan', 'sialkot', 'rawalpindi', 'global', 'all']) {
    final res = await fetchJson('/branches/$branch/employees');
    if (res != null && res.containsKey('documents')) {
      final docs = res['documents'] as List;
      print('\n--- Branch: $branch (${docs.length} employees) ---');
      for (var doc in docs) {
        final docName = doc['name'] as String;
        final docId = docName.split('/').last;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};
        final name = fields['name']?['stringValue'] ?? 'NO_NAME_FIELD';
        final pin = fields['biometricPin']?['stringValue'] ?? fields['pin']?['stringValue'] ?? fields['biometricPin']?['integerValue'] ?? fields['pin']?['integerValue'] ?? 'NO_PIN';
        final dept = fields['department']?['stringValue'] ?? 'NO_DEPT';
        final role = fields['role']?['stringValue'] ?? 'NO_ROLE';
        print('  docId: $docId | name: "$name" | pin: "$pin" | dept: "$dept" | role: "$role"');
      }
    }
  }
}
