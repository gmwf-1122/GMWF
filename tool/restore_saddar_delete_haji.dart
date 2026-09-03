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
  res['docPath'] = name;
  return res;
}

Future<void> deleteDoc(String docPath) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('https://firestore.googleapis.com/v1/$docPath?key=$apiKey');
    final req = await client.deleteUrl(uri);
    final res = await req.close();
    if (res.statusCode == 200 || res.statusCode == 204) {
      // success
    } else {
      final body = await res.transform(utf8.decoder).join();
      print('Failed delete $docPath: HTTP ${res.statusCode} $body');
    }
  } catch (e) {
    print('Error deleting $docPath: $e');
  } finally {
    client.close();
  }
}

Future<void> patchDoc(String docPath, Map<String, dynamic> fieldsToUpdate) async {
  final client = HttpClient();
  try {
    final maskParams = fieldsToUpdate.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    final uri = Uri.parse('https://firestore.googleapis.com/v1/$docPath?$maskParams&key=$apiKey');
    final req = await client.patchUrl(uri);
    req.headers.set('Content-Type', 'application/json');

    final firestoreFields = <String, dynamic>{};
    for (final entry in fieldsToUpdate.entries) {
      if (entry.value is String) {
        firestoreFields[entry.key] = {'stringValue': entry.value};
      } else if (entry.value is int) {
        firestoreFields[entry.key] = {'integerValue': entry.value.toString()};
      } else if (entry.value is bool) {
        firestoreFields[entry.key] = {'booleanValue': entry.value};
      }
    }

    req.write(jsonEncode({'fields': firestoreFields}));
    final res = await req.close();
    if (res.statusCode != 200) {
      final body = await res.transform(utf8.decoder).join();
      print('Failed patch $docPath: HTTP ${res.statusCode} $body');
    }
  } catch (e) {
    print('Error patching $docPath: $e');
  } finally {
    client.close();
  }
}

Future<void> main() async {
  print('=== 1. FETCHING ALL KARACHI INVENTORY DOCS ===');
  final client = HttpClient();
  final uri = Uri.parse('$baseUrl/branches/karachi/inventory?key=$apiKey&pageSize=500');
  final req = await client.getUrl(uri);
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  client.close();

  final json = jsonDecode(body) as Map<String, dynamic>;
  final docs = json['documents'] as List? ?? [];
  print('Total items retrieved: ${docs.length}');

  int hajiDeleted = 0;
  int saddarKept = 0;

  for (final raw in docs) {
    final doc = decodeDoc(raw as Map<String, dynamic>);
    final id = doc['id'] as String;
    final docPath = doc['docPath'] as String;
    final campId = (doc['campId'] ?? doc['dispensaryId'] ?? '').toString().toLowerCase();
    final tag = (doc['dispensaryTag'] ?? '').toString().toLowerCase();

    bool isHaji = id.startsWith('haji_') || id.startsWith('hajicamp--') || campId.contains('haji') || tag.contains('haji');
    bool isSaddar = id.startsWith('kapayya--') || id.startsWith('saddar--') || campId.contains('kapayya') || campId.contains('saddar') || tag.contains('sadd');

    if (isHaji && !isSaddar) {
      // DELETE Haji item
      print('🗑️ DELETING HAJI: $id');
      await deleteDoc(docPath);
      hajiDeleted++;
    } else {
      // KEEP Saddar item, ensure campId is explicitly 'saddar' and dispensaryId is 'saddar'
      print('✅ KEEPING SADDAR: $id');
      await patchDoc(docPath, {
        'campId': 'saddar',
        'dispensaryId': 'saddar',
        'dispensaryTag': 'SADD',
      });
      saddarKept++;
    }
  }

  print('\n=== COMPLETED RECOVERY & SELECTIVE CLEANUP ===');
  print('Haji items deleted from cloud: $hajiDeleted');
  print('Saddar items preserved & tagged: $saddarKept');
}
