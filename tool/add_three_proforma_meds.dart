import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';

const projectId = 'gmwf-8fc4c';
const apiKey = 'AIzaSyDA6MmTuZIPIxylV372s8zh-ndbShHwwAk';
const baseUrl = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

Future<void> main() async {
  final newMeds = [
    {
      'code': 'MED-ANT-TRI-TAB',
      'name': 'Antacid (Trisil)',
      'formula': 'Antacid (Trisil)',
      'type': 'Tablet',
      'dose': 'Standard',
      'price': 2.0,
      'expiryDate': '2027-09-03',
      'suffix': 'antacid-trisil--tablet--standard--2027-09-03',
    },
    {
      'code': 'MED-MEF-SYR',
      'name': 'Mefenamic Acid (Ponstan)',
      'formula': 'Mefenamic Acid (Ponstan)',
      'type': 'Syrup',
      'dose': '15 ml',
      'price': 95.0,
      'expiryDate': '2027-09-03',
      'suffix': 'mefenamic-acid-ponstan--syrup--15-ml--2027-09-03',
    },
    {
      'code': 'MED-CAP-25-TAB',
      'name': 'Captopril (Capoten)',
      'formula': 'Captopril (Capoten)',
      'type': 'Tablet',
      'dose': '25 mg',
      'price': 6.5,
      'expiryDate': '2027-09-03',
      'suffix': 'captopril-capoten--tablet--25-mg--2027-09-03',
    },
  ];

  final client = HttpClient();

  final allDocs = <Map<String, dynamic>>[];

  for (final med in newMeds) {
    for (final camp in ['hajicamp', 'saddar']) {
      final campLabel = camp == 'hajicamp' ? 'Haji Camp' : 'Saddar Camp';
      final campId = camp == 'hajicamp' ? 'haji_camp' : 'saddar';
      final docId = '$camp--${med['suffix']}';

      final doc = {
        'id': docId,
        'code': med['code'],
        'barcode': med['code'],
        'name': med['name'],
        'formula': med['formula'],
        'type': med['type'],
        'dose': med['dose'],
        'price': med['price'],
        'expiryDate': med['expiryDate'],
        'quantity': 20.0,
        'campId': campId,
        'dispensaryId': campId,
        'campName': campLabel,
        'campLabel': campLabel,
        'dispensaryTag': campId,
        'branchId': 'karachi',
        'isProformaMaster': true,
        'batches': [
          {
            'batchNumber': 'BATCH-001',
            'quantity': 20.0,
            'expiryDate': med['expiryDate'],
            'price': med['price'],
            'campId': campId,
            'dispensaryId': campId,
          }
        ],
      };

      allDocs.add(doc);

      final putUri = Uri.parse('$baseUrl/branches/karachi/inventory/$docId?key=$apiKey');
      final putReq = await client.patchUrl(putUri);
      putReq.headers.set('Content-Type', 'application/json');

      Map<String, dynamic> encodeDocFields(Map<String, dynamic> data) {
        final fields = <String, dynamic>{};
        data.forEach((k, v) {
          if (k.startsWith('_') || k == 'id') return;
          if (v == null) return;
          if (v is String) {
            fields[k] = {'stringValue': v};
          } else if (v is int) {
            fields[k] = {'integerValue': v.toString()};
          } else if (v is double) {
            fields[k] = {'doubleValue': v};
          } else if (v is bool) {
            fields[k] = {'booleanValue': v};
          } else if (v is List) {
            fields[k] = {
              'arrayValue': {
                'values': v.map((item) {
                  if (item is Map<String, dynamic>) {
                    return {'mapValue': {'fields': encodeDocFields(item)}};
                  }
                  return {'stringValue': item.toString()};
                }).toList()
              }
            };
          } else if (v is Map<String, dynamic>) {
            fields[k] = {'mapValue': {'fields': encodeDocFields(v)}};
          }
        });
        return fields;
      }

      putReq.write(jsonEncode({'fields': encodeDocFields(doc)}));
      final res = await putReq.close();
      await res.drain();
      print('Saved Firestore doc: $docId (${res.statusCode})');
    }
  }

  client.close();

  // Also update local Hive
  try {
    final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
    if (hiveDir.existsSync()) {
      Hive.init(hiveDir.path);
      final box = await Hive.openBox('local_stock');
      for (final doc in allDocs) {
        await box.put(doc['id'], doc);
        await box.put('stock:${doc['id']}', doc);
      }
      print('Saved ${allDocs.length} items to local Hive stockBox');
      await box.close();
    }
  } catch (e) {
    print('Local Hive note: $e');
  }

  print('Done adding 3 new proforma medicines to both camps!');
}
