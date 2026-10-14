import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/zkteco_network_service.dart';

/// The pre-filter that runs off the UI thread must keep exactly the records the attendance
/// parser acts on (the last 24 h), in the same layout.
void main() {
  int encode(DateTime t) =>
      ((((((t.year - 2000) * 12 + (t.month - 1)) * 31 + (t.day - 1)) * 24 + t.hour) * 60 + t.minute) * 60) + t.second;

  Uint8List record40(String pin, DateTime t) {
    final r = Uint8List(40);
    r.setAll(0, utf8.encode(pin));
    final e = encode(t);
    r[24] = e & 0xFF;
    r[25] = (e >> 8) & 0xFF;
    r[26] = (e >> 16) & 0xFF;
    r[27] = (e >> 24) & 0xFF;
    return r;
  }

  test('binary log: only records from the last 24 h are kept, byte for byte', () {
    final now = DateTime.now();
    final fresh = record40('101', now.subtract(const Duration(hours: 2)));
    final old = record40('102', now.subtract(const Duration(days: 30)));
    final log = Uint8List.fromList([...old, ...fresh, ...old]);
    final kept = ZkTecoNetworkService.keepRecentZkRecords(log);
    expect(kept, fresh);
  });

  test('binary log with nothing recent becomes empty (parser does nothing, as before)', () {
    final old = record40('102', DateTime.now().subtract(const Duration(days: 3)));
    expect(ZkTecoNetworkService.keepRecentZkRecords(old), isEmpty);
  });

  test('text log keeps recent and unparseable-time lines, drops old ones', () {
    final now = DateTime.now();
    final recent = now.subtract(const Duration(hours: 1)).toIso8601String();
    final old = now.subtract(const Duration(days: 10)).toIso8601String();
    final text = 'ATTLOG\n101\t$old\n102\t$recent\n103\tnot-a-time\n';
    final kept = utf8.decode(ZkTecoNetworkService.keepRecentZkRecords(Uint8List.fromList(utf8.encode(text))));
    expect(kept, '102\t$recent\n103\tnot-a-time');
  });
}
