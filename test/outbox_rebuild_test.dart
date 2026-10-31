import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:hive/hive.dart';

void main() {
  test('oversized outbox is rebuilt: newest copy per record, critical kept, nesting flattened', () async {
    final dir = await Directory.systemTemp.createTemp('outbox_rebuild_');
    Hive.init(dir.path);
    final box = await Hive.openBox('realtime_outbox');

    Map<String, dynamic> nested(int depth) {
      Map<String, dynamic> p = {'medicines': [{'name': 'Panadol', 'quantity': 2}], 'diagnosis': 'fever'};
      for (var i = 0; i < depth; i++) {
        p = {'medicines': [{'name': 'Panadol', 'quantity': 2}], 'diagnosis': 'fever', 'prescription': p};
      }
      return p;
    }

    final now = DateTime.now();
    final old = now.subtract(const Duration(days: 3));
    // Three queued copies of one token: only the newest survives.
    for (var i = 0; i < 3; i++) {
      await box.put('entry_copy_$i', {
        'event_type': 'save_entry',
        '_messageId': 'entry_copy_$i',
        'serial': '311026-HAJI-001',
        '_outboxTimestamp': now.subtract(Duration(minutes: 10 - i)).toIso8601String(),
        'data': {'serial': '311026-HAJI-001', 'patientName': 'copy $i'},
      });
    }
    // A prescription carrying 7 nested older copies.
    await box.put('presc', {
      'event_type': 'save_prescription',
      '_messageId': 'presc',
      '_outboxTimestamp': now.toIso8601String(),
      'data': {'serial': '311026-HAJI-002', 'prescription': nested(7)},
    });
    // An undelivered token from three days ago: critical, never dropped.
    await box.put('old_token', {
      'event_type': 'save_entry',
      '_messageId': 'old_token',
      '_outboxTimestamp': old.toIso8601String(),
      'data': {'serial': '281026-HAJI-009', 'dateKey': '281026'},
    });
    // A stale non-critical item: dropped.
    await box.put('old_notice', {
      'event_type': 'relay_cloud_write',
      '_messageId': 'old_notice',
      '_outboxTimestamp': old.toIso8601String(),
      'data': {'id': 'branches/karachi/notifications/x'},
    });
    // Bloat the file the way the flush loop did: the same item re-put many times.
    for (var i = 0; i < 300; i++) {
      await box.put('presc', {
        'event_type': 'save_prescription',
        '_messageId': 'presc',
        '_outboxTimestamp': now.toIso8601String(),
        '_outboxSends': i,
        'data': {'serial': '311026-HAJI-002', 'prescription': nested(7)},
      });
    }
    await box.close();
    final beforeBytes = File('${dir.path}/realtime_outbox.hive').lengthSync();

    final path = dir.path;
    final stats = await Isolate.run(() => RealtimeManager.rebuildQueueFile(path, 'realtime_outbox'));

    expect(stats['beforeCount'], 6);
    expect(stats['afterCount'], 3); // newest token copy, prescription, old token
    final afterBytes = File('${dir.path}/realtime_outbox.hive').lengthSync();
    expect(afterBytes, lessThan(beforeBytes ~/ 10));
    expect(File('${dir.path}/realtime_outbox_rebuild.hive').existsSync(), isFalse);

    Hive.init(dir.path);
    final rebuilt = await Hive.openBox('realtime_outbox');
    expect(rebuilt.containsKey('entry_copy_2'), isTrue);
    expect(rebuilt.containsKey('entry_copy_0'), isFalse);
    expect(rebuilt.containsKey('old_token'), isTrue);
    expect(rebuilt.containsKey('old_notice'), isFalse);
    final presc = rebuilt.get('presc') as Map;
    final rx = (presc['data'] as Map)['prescription'] as Map;
    expect(rx.containsKey('prescription'), isFalse);
    expect((rx['medicines'] as List).length, 1);
    expect(presc.containsKey('_outboxSends'), isFalse);
    await rebuilt.close();
    await dir.delete(recursive: true);
  });
}
