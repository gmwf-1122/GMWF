import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';

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

String norm(dynamic s) {
  return (s ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

double findSaddarQty(Map<String, dynamic> targetMed, List<Map<String, dynamic>> saddarMeds) {
  final tName = norm(targetMed['name']);
  final tFormula = norm(targetMed['formula']);
  final tType = norm(targetMed['type']);
  final tDose = norm(targetMed['dose']);

  // Specific manual overrides for known renamed medicines
  if (tName.contains('cyanocobalamin') || (tName.contains('bcomplex') && tType.contains('injection')) || (tName.contains('neurobion') && tType.contains('injection'))) {
    for (final s in saddarMeds) {
      if (norm(s['name']).contains('cyanocobalamin') || (norm(s['name']).contains('neurobion') && norm(s['type']).contains('injection'))) {
        return (s['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
  }
  if (tName.contains('normalsaline') || tName.contains('09nacl') || tName.contains('ns')) {
    final is100 = tDose.contains('100') || norm(targetMed['id']).contains('100');
    final is500 = tDose.contains('500') || norm(targetMed['id']).contains('500');
    for (final s in saddarMeds) {
      final sN = norm(s['name']) + norm(s['id']);
      if (sN.contains('nacl') || sN.contains('saline') || sN.contains('ns')) {
        if (is100 && (sN.contains('100') || norm(s['dose']).contains('100'))) {
          return (s['quantity'] as num?)?.toDouble() ?? 0.0;
        }
        if (is500 && (sN.contains('500') || norm(s['dose']).contains('500'))) {
          return (s['quantity'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
  }
  if (tName.contains('paracetamol') || tName.contains('panadol')) {
    if (tType.contains('tablet')) {
      for (final s in saddarMeds) {
        if (norm(s['name']).contains('paracetamol') && norm(s['type']).contains('tablet')) {
          return (s['quantity'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
  }
  if (tName.contains('metoclopramide') || tName.contains('maxolon') || tName.contains('metoclone')) {
    if (tType.contains('tablet')) {
      for (final s in saddarMeds) {
        if ((norm(s['name']).contains('metoclone') || norm(s['name']).contains('maxolon')) && norm(s['type']).contains('tablet')) {
          return (s['quantity'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
  }
  if (tName.contains('diclofenac') && tType.contains('injection')) {
    for (final s in saddarMeds) {
      if (norm(s['name']).contains('diclofenac') && norm(s['type']).contains('injection')) {
        return (s['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
  }
  if (tName.contains('chlorpheniramine') || tName.contains('cpm')) {
    if (tType.contains('syrup')) {
      for (final s in saddarMeds) {
        if ((norm(s['name']).contains('chlorpheniramine') || norm(s['name']).contains('cpm')) && norm(s['type']).contains('syrup')) {
          return (s['quantity'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
  }
  if (tName.contains('antacid') || tName.contains('mucaine') || tName.contains('digas')) {
    for (final s in saddarMeds) {
      if (norm(s['name']).contains('antacid') || norm(s['name']).contains('aluminum')) {
        return (s['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
  }
  if (tName.contains('carminative') || tName.contains('cholic') || tName.contains('gripe')) {
    for (final s in saddarMeds) {
      if (norm(s['name']).contains('carminative') || norm(s['name']).contains('cholic') || norm(s['name']).contains('gripe')) {
        return (s['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
  }
  if (tName.contains('ammonium') || tName.contains('cough')) {
    for (final s in saddarMeds) {
      if (norm(s['name']).contains('ammonium') || norm(s['name']).contains('cough')) {
        return (s['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
  }
  if (tName.contains('flagyl') || tName.contains('metronidazole')) {
    if (tType.contains('syrup')) {
      for (final s in saddarMeds) {
        if ((norm(s['name']).contains('flagyl') || norm(s['name']).contains('metronidazole')) && norm(s['type']).contains('syrup')) {
          return (s['quantity'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
  }
  if (tName.contains('vitaminc') || tName.contains('ascorbic')) {
    for (final s in saddarMeds) {
      if (norm(s['name']).contains('vitaminc') || norm(s['name']).contains('ascorbic')) {
        return (s['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
  }
  if (tName.contains('mefenamic') || tName.contains('ponstan')) {
    for (final s in saddarMeds) {
      if (norm(s['name']).contains('mefenamic') || norm(s['name']).contains('ponstan')) {
        return (s['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
  }

  // 1. Exact match on formula/name + type + dose
  for (final s in saddarMeds) {
    final sName = norm(s['name']);
    final sFormula = norm(s['formula']);
    final sType = norm(s['type']);
    final sDose = norm(s['dose']);

    final nameMatch = (tName.contains(sName) || sName.contains(tName) ||
                       (tFormula.isNotEmpty && (tFormula.contains(sFormula) || sFormula.contains(tFormula))));
    final typeMatch = tType == sType || (tType.contains('drip') && sType.contains('infusion')) || (tType.contains('infusion') && sType.contains('drip'));
    final doseMatch = tDose == sDose || tDose.isEmpty || sDose.isEmpty || tDose.replaceAll(RegExp(r'\D'), '') == sDose.replaceAll(RegExp(r'\D'), '');

    if (nameMatch && typeMatch && doseMatch) {
      final q = s['quantity'];
      if (q is num) return q.toDouble();
    }
  }

  // 2. Fallback: match by key tokens in name/formula and type
  for (final s in saddarMeds) {
    final sName = norm(s['name']);
    final sFormula = norm(s['formula']);
    final sType = norm(s['type']);

    final typeMatch = tType == sType || (tType.contains('drip') && sType.contains('infusion')) || (tType.contains('infusion') && sType.contains('drip'));
    if (!typeMatch) continue;

    for (final kw in ['amoxicillin', 'paracetamol', 'metronidazole', 'flagyl', 'omeprazole', 'risek', 'danzen', 'serratiopeptidase', 'neurobion', 'cyanocobalamin', 'bcomplex', 'calcium', 'dexamethasone', 'diclofenac', 'ibuprofen', 'brufen', 'cholic', 'carminative', 'antacid', 'mucaine', 'cpm', 'chlorpheniramine', 'ciprofloxacin', 'drotaverine', 'nospa', 'nimesulide', 'saline', 'dexosaline', 'ringer', 'sodamint', 'folic', 'syringe', 'oxytetracycline', 'lincomycin', 'mefenamic', 'metoclopramide', 'metoclone', 'indomethacin', 'doxycycline', 'avil', 'pheniramine', 'stemetil', 'cough']) {
      if ((tName.contains(kw) || tFormula.contains(kw)) && (sName.contains(kw) || sFormula.contains(kw))) {
        final tNum = tDose.replaceAll(RegExp(r'\D'), '');
        final sNum = norm(s['dose']).replaceAll(RegExp(r'\D'), '');
        if (tNum.isEmpty || sNum.isEmpty || tNum == sNum) {
          final q = s['quantity'];
          if (q is num) return q.toDouble();
        }
      }
    }
  }

  return 0.0;
}

Future<void> main(List<String> args) async {
  final execute = args.contains('--execute');

  final client = HttpClient();
  final uri = Uri.parse('$baseUrl/branches/karachi/inventory?key=$apiKey&pageSize=500');
  final req = await client.getUrl(uri);
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();

  final json = jsonDecode(body) as Map<String, dynamic>;
  final docs = json['documents'] as List? ?? [];

  final hajiMeds = <Map<String, dynamic>>[];
  final saddarMeds = <Map<String, dynamic>>[];

  for (final raw in docs) {
    final doc = decodeDoc(raw as Map<String, dynamic>);
    final id = doc['id'].toString().toLowerCase();
    final campId = (doc['campId'] ?? doc['dispensaryId'] ?? '').toString().toLowerCase();

    if (id.startsWith('haji') || campId.contains('haji')) {
      hajiMeds.add(doc);
    } else if (id.startsWith('saddar') || id.startsWith('kapay') || campId.contains('sadd') || campId.contains('kap')) {
      saddarMeds.add(doc);
    }
  }

  print('Haji Meds found: ${hajiMeds.length}');
  print('Existing Saddar Meds found: ${saddarMeds.length}');

  print('\n=== PLAN: CLONE HAJI MEDS TO SADDAR WITH SADDAR QUANTITIES ===');
  final plannedSaddarDocs = <Map<String, dynamic>>[];

  for (final h in hajiMeds) {
    final hId = h['id'].toString();
    // Convert ID prefix from haji to saddar
    final suffix = hId.replaceFirst(RegExp(r'^haji_?camp?--?', caseSensitive: false), '');
    final newSaddarId = 'saddar--$suffix';

    final saddarQty = findSaddarQty(h, saddarMeds);

    final saddarDoc = Map<String, dynamic>.from(h);
    saddarDoc['id'] = newSaddarId;
    saddarDoc['campId'] = 'saddar';
    saddarDoc['dispensaryId'] = 'saddar';
    saddarDoc['campName'] = 'Saddar Camp';
    saddarDoc['campLabel'] = 'Saddar Camp';
    saddarDoc['dispensaryTag'] = 'saddar';
    saddarDoc['quantity'] = saddarQty;
    if (saddarDoc['batches'] is List && (saddarDoc['batches'] as List).isNotEmpty) {
      final bList = List<Map<String, dynamic>>.from((saddarDoc['batches'] as List).map((b) => Map<String, dynamic>.from(b as Map)));
      if (bList.isNotEmpty) {
        bList[0]['quantity'] = saddarQty;
        bList[0]['campId'] = 'saddar';
        bList[0]['dispensaryId'] = 'saddar';
      }
      saddarDoc['batches'] = bList;
    }

    plannedSaddarDocs.add(saddarDoc);
    print('Clone -> $newSaddarId | Name: ${saddarDoc["name"]} | Qty: $saddarQty');
  }

  print('\nTotal cloned Saddar documents to create/update: ${plannedSaddarDocs.length}');
  print('Existing Saddar documents to remove: ${saddarMeds.length}');

  if (!execute) {
    print('\n[DRY RUN COMPLETE] To apply to Firestore, run with --execute');
    client.close();
    return;
  }

  print('\n[EXECUTING] Deleting old Saddar docs from Firestore...');
  for (final old in saddarMeds) {
    final delUri = Uri.parse('$baseUrl/branches/karachi/inventory/${old["id"]}?key=$apiKey');
    final delReq = await client.deleteUrl(delUri);
    final delRes = await delReq.close();
    await delRes.drain();
    print('Deleted old doc: ${old["id"]} (${delRes.statusCode})');
  }

  print('\n[EXECUTING] Writing cloned Saddar docs to Firestore...');
  for (final doc in plannedSaddarDocs) {
    final docId = doc['id'];
    final putUri = Uri.parse('$baseUrl/branches/karachi/inventory/$docId?key=$apiKey');
    final putReq = await client.patchUrl(putUri);
    putReq.headers.set('Content-Type', 'application/json');

    // Encode fields to Firestore REST JSON
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
                } else if (item is String) {
                  return {'stringValue': item};
                } else if (item is num) {
                  return {'doubleValue': item.toDouble()};
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

    final payload = jsonEncode({'fields': encodeDocFields(doc)});
    putReq.write(payload);
    final putRes = await putReq.close();
    await putRes.drain();
    print('Created doc: $docId (${putRes.statusCode})');
  }

  client.close();
  print('\n✅ All ${plannedSaddarDocs.length} Saddar medicines cloned to Firestore!');

  // Also update local Hive stockBox
  try {
    final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
    if (hiveDir.existsSync()) {
      Hive.init(hiveDir.path);
      final box = await Hive.openBox('local_stock');
      final keysToDelete = <dynamic>[];
      for (final k in box.keys) {
        final val = box.get(k);
        if (val is Map) {
          final cId = (val['campId'] ?? val['dispensaryId'] ?? '').toString().toLowerCase();
          final dId = (val['id'] ?? k).toString().toLowerCase();
          if (cId.contains('saddar') || cId.contains('kapay') || dId.startsWith('saddar') || dId.startsWith('kapay')) {
            keysToDelete.add(k);
          }
        }
      }
      for (final k in keysToDelete) {
        await box.delete(k);
      }
      for (final doc in plannedSaddarDocs) {
        await box.put(doc['id'], doc);
        await box.put('stock:${doc['id']}', doc);
      }
      print('✅ Local Hive stockBox synchronized with ${plannedSaddarDocs.length} cloned Saddar items!');
      await box.close();
    }
  } catch (e) {
    print('Note: Could not directly write to local Hive box (app may be running): $e');
  }
}
