import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  final meds = [
    {'name': 'Panadol', 'quantity': 2},
    {'name': 'Brufen', 'quantity': 1},
  ];

  test('a diagnosis-only wrapper keeps the medicines of the nested prescription', () {
    // What SyncService sends on reconnect: entry fields on the outside, the real prescription
    // nested, top-level medicines missing.
    final wrapper = {
      'serial': '311026-HAJI-004',
      'diagnosis': 'viral',
      'completedAt': '2026-10-31T10:00:00',
      'medicines': null,
      'prescription': {'prescriptions': meds, 'diagnosis': 'viral', 'updatedAt': '2026-10-31T09:59:00'},
    };
    final out = LocalStorageService.prescriptionForEmbedding(wrapper);
    expect(out['medicines'], meds);
    expect(out['prescriptions'], meds);
    expect(out['diagnosis'], 'viral');
    expect(out.containsKey('prescription'), isFalse);
  });

  test('an empty medicines list does not mask a filled prescriptions list', () {
    final out = LocalStorageService.prescriptionForEmbedding({'medicines': <dynamic>[], 'prescriptions': meds});
    expect(out['medicines'], meds);
    expect(out['prescriptions'], meds);
  });

  test('a full outer prescription wins over its older nested copies', () {
    Map<String, dynamic> nest(int depth) {
      Map<String, dynamic> p = {'prescriptions': [{'name': 'Old', 'quantity': 1}]};
      for (var i = 0; i < depth; i++) {
        p = {'prescriptions': [{'name': 'Old', 'quantity': 1}], 'prescription': p};
      }
      return p;
    }

    final out = LocalStorageService.prescriptionForEmbedding({'prescriptions': meds, 'prescription': nest(7)});
    expect(out['prescriptions'], meds);
    expect(out.containsKey('prescription'), isFalse);
  });

  test('flattenEmbeddedPrescription keeps medicines that were only nested', () {
    final entry = {
      'serial': '311026-HAJI-005',
      'prescription': {
        'diagnosis': 'fever',
        'prescription': {'medicines': meds},
      },
    };
    expect(LocalStorageService.flattenEmbeddedPrescription(entry), isTrue);
    final rx = entry['prescription'] as Map;
    expect(rx['medicines'], meds);
    expect(rx['diagnosis'], 'fever');
  });
}
