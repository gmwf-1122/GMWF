import 'dart:convert';
import 'dart:io';

const projectId = 'gmwf-8fc4c';
const apiKey = 'AIzaSyDA6MmTuZIPIxylV372s8zh-ndbShHwwAk';
const baseUrl = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

dynamic decodeValue(dynamic val) {
  if (val is! Map) return val;
  if (val.containsKey('stringValue')) return val['stringValue'];
  if (val.containsKey('integerValue')) return int.tryParse(val['integerValue'].toString()) ?? 0;
  if (val.containsKey('doubleValue')) return double.tryParse(val['doubleValue'].toString()) ?? 0.0;
  if (val.containsKey('booleanValue')) return val['booleanValue'];
  if (val.containsKey('mapValue')) {
    final m = val['mapValue']['fields'] as Map<String, dynamic>? ?? {};
    return m.map((k, v) => MapEntry(k, decodeValue(v)));
  }
  if (val.containsKey('arrayValue')) {
    final a = val['arrayValue']['values'] as List? ?? [];
    return a.map((v) => decodeValue(v)).toList();
  }
  return val;
}

Map<String, dynamic> decodeDoc(Map<String, dynamic> doc) {
  final fields = doc['fields'] as Map<String, dynamic>? ?? {};
  final res = <String, dynamic>{};
  fields.forEach((k, v) => res[k] = decodeValue(v));
  final name = doc['name'] as String;
  res['id'] = name.split('/').last;
  return res;
}

Future<List<Map<String, dynamic>>> fetchAllDocs(String collectionPath) async {
  final client = HttpClient();
  var url = '$baseUrl/$collectionPath?key=$apiKey&pageSize=300';
  final allDocs = <Map<String, dynamic>>[];
  String? pageToken;

  do {
    final reqUrl = pageToken != null ? '$url&pageToken=$pageToken' : url;
    final req = await client.getUrl(Uri.parse(reqUrl));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final docs = json['documents'] as List? ?? [];
    for (final d in docs) {
      allDocs.add(decodeDoc(d as Map<String, dynamic>));
    }
    pageToken = json['nextPageToken'] as String?;
  } while (pageToken != null);

  client.close();
  return allDocs;
}

Future<void> main() async {
  final hajiDocs = await fetchAllDocs('branches/karachi/inventory_haji');
  print('=== inventory_haji Docs (${hajiDocs.length}) ===');
  for (final d in hajiDocs) {
    print('${d['id']} -> name: "${d['name']}", generic: "${d['genericName'] ?? d['formula']}", dose: "${d['dose']}", type: "${d['type']}", qty: ${d['quantity']}');
  }
}
