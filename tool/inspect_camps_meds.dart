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

Future<void> main() async {
  final client = HttpClient();
  final uri = Uri.parse('$baseUrl/branches/karachi/inventory?key=$apiKey&pageSize=500');
  final req = await client.getUrl(uri);
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  client.close();

  final json = jsonDecode(body) as Map<String, dynamic>;
  final docs = json['documents'] as List? ?? [];
  print('Total raw Firestore docs found: ${docs.length}');
  if (json.containsKey('error')) {
    print('Firestore error: ${json['error']}');
  }

  final hajiMeds = <Map<String, dynamic>>[];
  final saddarMeds = <Map<String, dynamic>>[];
  final otherMeds = <Map<String, dynamic>>[];

  for (final raw in docs) {
    final doc = decodeDoc(raw as Map<String, dynamic>);
    final id = doc['id'].toString().toLowerCase();
    final campId = (doc['campId'] ?? doc['dispensaryId'] ?? '').toString().toLowerCase();

    if (id.startsWith('haji') || campId.contains('haji')) {
      hajiMeds.add(doc);
    } else if (id.startsWith('saddar') || id.startsWith('kapay') || campId.contains('sadd') || campId.contains('kap')) {
      saddarMeds.add(doc);
    } else {
      otherMeds.add(doc);
    }
  }

  print('Haji Meds: ${hajiMeds.length}');
  for (int i = 0; i < hajiMeds.length; i++) {
    final m = hajiMeds[i];
    print('${i + 1}. ${m["name"]} (${m["type"]} ${m["dose"]}) -> Qty: ${m["quantity"]} [${m["id"]}]');
  }

  print('\n=== SADDAR CAMP MEDICINES ===');
  for (final m in saddarMeds) {
    print('ID: ${m["id"]} | Name: ${m["name"]} | Type: ${m["type"]} | Dose: ${m["dose"]} | Qty: ${m["quantity"]}');
  }

  if (otherMeds.isNotEmpty) {
    print('\n=== OTHER / UNASSIGNED MEDICINES ===');
    for (final m in otherMeds) {
      print('ID: ${m["id"]} | Name: ${m["name"]} | Type: ${m["type"]} | Dose: ${m["dose"]} | Qty: ${m["quantity"]}');
    }
  }
}
