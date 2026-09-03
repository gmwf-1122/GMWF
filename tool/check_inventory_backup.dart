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
  print('=== CHECKING FIRESTORE INVENTORY COLLECTIONS ===');
  
  final branchIds = ['Karachi', 'karachi'];
  final subCollections = [
    'inventory',
    'inventory_saddar',
    'inventory_haji',
    'inventory_haji_camp',
    'inventory_Saddar',
    'inventory_Haji',
  ];

  for (final b in branchIds) {
    for (final sub in subCollections) {
      final res = await fetchJson('/branches/$b/$sub');
      if (res != null && res.containsKey('documents')) {
        final docs = res['documents'] as List;
        print('FOUND: /branches/$b/$sub -> ${docs.length} documents!');
        if (docs.isNotEmpty) {
          final first = docs.first;
          print('   Sample doc name: ${first['name']}');
        }
      } else {
        print('EMPTY / NOT FOUND: /branches/$b/$sub');
      }
    }
  }
}
