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
  res['_docPath'] = name;
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

String norm(dynamic s) {
  return (s ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

Future<void> main() async {
  final hajiDocs = await fetchAllDocs('branches/karachi/inventory_haji');

  final Map<String, List<Map<String, dynamic>>> groups = {};
  for (final d in hajiDocs) {
    final name = norm(d['name']);
    final type = norm(d['type'] ?? d['dosageForm']);
    final dose = norm(d['dose']);
    final key = '$name|$type|$dose';
    groups.putIfAbsent(key, () => []).add(d);
  }

  int i = 1;
  for (final entry in groups.entries) {
    if (entry.value.length > 1) {
      if (i <= 5) {
        print('Group $i: ${entry.key}');
        for (final doc in entry.value) {
          print('   - ID: ${doc['id']} | Qty: ${doc['quantity']} | Exp: ${doc['expiryDate']} | Created: ${doc['createdAt']}');
        }
      }
      i++;
    }
  }
}
