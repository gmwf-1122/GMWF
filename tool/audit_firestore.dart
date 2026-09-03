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
  print('=== 🔍 QUERYING FIRESTORE REST API ===');
  final branchesRes = await fetchJson('/branches');
  if (branchesRes != null && branchesRes.containsKey('documents')) {
    final docs = branchesRes['documents'] as List;
    print('Found ${docs.length} branches:');
    for (var doc in docs) {
      final name = doc['name'] as String;
      final branchId = name.split('/').last;
      print('  - Branch: $branchId');
    }
  } else {
    print('No branches found or error: $branchesRes');
  }
}
