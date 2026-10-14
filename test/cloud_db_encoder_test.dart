import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/cloud/cloud_db.dart';

/// The REST upload transport must store exactly what the Firestore SDK stored:
/// same field types, same merge behaviour, same server-side transforms.
void main() {
  const name = 'projects/p/databases/(default)/documents/branches/karachi/serials/A1';

  Map<String, dynamic> enc({Map<String, dynamic>? set, SetOptions? options, Map<Object, Object?>? update, bool delete = false}) =>
      CloudDb.encodeForTest('branches/karachi/serials/A1', set: set, options: options, update: update, delete: delete);

  test('delete', () {
    expect(enc(delete: true), {'delete': name});
  });

  test('value types match the SDK encoding', () {
    final w = enc(set: {
      's': 'x',
      'i': 7,
      'd': 2.5,
      'whole': 3.0,
      'b': true,
      'n': null,
      'list': [1, 'a'],
      'ts': Timestamp(1700000000, 5000),
      'dt': DateTime.utc(2026, 10, 12, 8, 30, 15, 123),
    });
    final f = (w['update'] as Map)['fields'] as Map;
    expect(f['s'], {'stringValue': 'x'});
    expect(f['i'], {'integerValue': '7'});
    expect(f['d'], {'doubleValue': 2.5});
    expect(f['whole'], {'doubleValue': 3.0});
    expect(f['b'], {'booleanValue': true});
    expect(f['n'], {'nullValue': null});
    expect(f['list'], {
      'arrayValue': {
        'values': [
          {'integerValue': '1'},
          {'stringValue': 'a'}
        ]
      }
    });
    expect(f['ts'], {'timestampValue': '2023-11-14T22:13:20.000005000Z'});
    expect(f['dt'], {'timestampValue': '2026-10-12T08:30:15.123000000Z'});
    // A plain set replaces the document: no field mask.
    expect(w.containsKey('updateMask'), isFalse);
  });

  test('merge only touches the leaf fields it names (nested maps merge)', () {
    final w = enc(set: {
      'status': 'completed',
      'meta': {'by': 'doc1', 'inner': {'x': 1}},
      'empty': <String, dynamic>{},
      'odd key': 1,
    }, options: SetOptions(merge: true));
    expect((w['updateMask'] as Map)['fieldPaths'],
        ['status', 'meta.by', 'meta.inner.x', 'empty', '`odd key`']);
    final meta = ((w['update'] as Map)['fields'] as Map)['meta'];
    expect(meta, {
      'mapValue': {
        'fields': {
          'by': {'stringValue': 'doc1'},
          'inner': {
            'mapValue': {
              'fields': {'x': {'integerValue': '1'}}
            }
          },
        }
      }
    });
  });

  test('sentinels become transforms and are left out of the mask', () {
    final w = enc(set: {
      'totalTokens': FieldValue.increment(3),
      'avg': FieldValue.increment(1.5),
      'lastUpdated': FieldValue.serverTimestamp(),
      'tags': FieldValue.arrayUnion(['a']),
      'gone': FieldValue.delete(),
      'name': 'x',
    }, options: SetOptions(merge: true));
    expect((w['updateMask'] as Map)['fieldPaths'], ['gone', 'name']);
    expect(w['updateTransforms'], [
      {'fieldPath': 'totalTokens', 'increment': {'integerValue': '3'}},
      {'fieldPath': 'avg', 'increment': {'doubleValue': 1.5}},
      {'fieldPath': 'lastUpdated', 'setToServerValue': 'REQUEST_TIME'},
      {'fieldPath': 'tags', 'appendMissingElements': {'values': [{'stringValue': 'a'}]}},
    ]);
    expect(((w['update'] as Map)['fields'] as Map).keys, ['name']);
    // Increments add to the stored value, so such a write is never skipped as "unchanged".
    expect(CloudDb.isRepeatableForTest(w), isFalse);
  });

  test('a write with only server timestamps can be skipped when unchanged', () {
    final w = enc(set: {'a': 1, 'at': FieldValue.serverTimestamp()}, options: SetOptions(merge: true));
    expect(CloudDb.isRepeatableForTest(w), isTrue);
  });

  test('update uses dotted field paths and requires the document to exist', () {
    final w = enc(update: {
      'currentAdvanceBalance': FieldValue.increment(-10),
      'profile.phone': '0300',
    });
    expect(w['currentDocument'], {'exists': true});
    expect((w['updateMask'] as Map)['fieldPaths'], ['profile.phone']);
    expect(((w['update'] as Map)['fields'] as Map)['profile'], {
      'mapValue': {
        'fields': {'phone': {'stringValue': '0300'}}
      }
    });
    expect(w['updateTransforms'], [
      {'fieldPath': 'currentAdvanceBalance', 'increment': {'integerValue': '-10'}},
    ]);
  });

  test('mergeFields writes only the listed fields', () {
    final w = enc(set: {'a': 1, 'b': 2, 'c': {'d': 3}}, options: SetOptions(mergeFields: ['a', 'c.d']));
    expect((w['updateMask'] as Map)['fieldPaths'], ['a', 'c.d']);
    expect(((w['update'] as Map)['fields'] as Map).keys, ['a', 'c']);
  });

  test('FieldValue inside an array is rejected (as by the SDK)', () {
    expect(() => enc(set: {'x': [FieldValue.serverTimestamp()]}), throwsArgumentError);
  });
}
