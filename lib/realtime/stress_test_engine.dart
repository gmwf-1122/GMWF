// lib/realtime/stress_test_engine.dart
//
// Server-side network stress test. Started from the server screen (Ctrl+Shift+Alt+T).
//
//   PROBE  - small ping-style messages to every connected device; measures round-trip time and
//            loss per device. Touches no data.
//   FLOOD  - 100 test tokens sent to every device (they show up in the doctor / dispenser /
//            receptionist queues for a few seconds); measures delivery per device.
//   BOTH   - probe, then flood.
//
// After every run the engine asks every device to delete its test tokens and verifies the
// answer. Test tokens exist only in each device's local entries box, never on the server, in the
// sync queue, in serial counters or in Firestore. Devices that were offline purge leftovers by
// themselves the next time they connect.
//
// Output: a text report and a JSON file on the server PC's Desktop.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/system_metrics_service.dart';
import 'lan_server.dart';

enum StressMode { probe, flood, both }

class DeviceStress {
  final String socketId;
  final String clientId;
  final String role;
  final String username;
  final String ip;

  int probesSent = 0;
  int probesAcked = 0;
  final List<int> probeRttMs = [];

  int tokensSent = 0;
  int tokensAcked = 0;
  final List<int> tokenRttMs = [];

  int requestsSent = 0;
  int requestsAcked = 0;
  final List<int> requestRttMs = [];

  int sendFailures = 0;
  bool lostConnection = false;
  bool reconnected = false;

  bool cleanupAnswered = false;
  int cleanupRemoved = 0;
  int cleanupRemaining = -1;

  DeviceStress({
    required this.socketId,
    required this.clientId,
    required this.role,
    required this.username,
    required this.ip,
  });

  static int _pct(List<int> sorted, double p) =>
      sorted.isEmpty ? -1 : sorted[((sorted.length - 1) * p).round().clamp(0, sorted.length - 1)];

  Map<String, dynamic> _stats(int sent, int acked, List<int> rtt) {
    final s = [...rtt]..sort();
    return {
      'sent': sent,
      'acked': acked,
      'lost': sent - acked,
      'lossPercent': sent == 0 ? 0.0 : double.parse(((sent - acked) * 100.0 / sent).toStringAsFixed(1)),
      'rttMs': {'p50': _pct(s, 0.5), 'p95': _pct(s, 0.95), 'p99': _pct(s, 0.99), 'max': s.isEmpty ? -1 : s.last},
    };
  }

  Map<String, dynamic> toJson() => {
        'device': '$username ($role)',
        'ip': ip,
        'clientId': clientId,
        'probe': _stats(probesSent, probesAcked, probeRttMs),
        'flood': _stats(tokensSent, tokensAcked, tokenRttMs),
        'requestsApprovals': _stats(requestsSent, requestsAcked, requestRttMs),
        'sendFailures': sendFailures,
        'lostConnection': lostConnection,
        'reconnectedDuringTest': reconnected,
        'cleanup': {
          'answered': cleanupAnswered,
          'removed': cleanupRemoved,
          'remainingOnDevice': cleanupRemaining,
        },
      };

  /// Pass / fail for this device given which phases ran.
  String verdict(bool probeRan, bool floodRan) {
    if (lostConnection) return 'FAIL (lost connection)';
    final probeLoss = probesSent == 0 ? 0 : probesSent - probesAcked;
    final tokenLoss = tokensSent == 0 ? 0 : tokensSent - tokensAcked;
    final reqLoss = requestsSent == 0 ? 0 : requestsSent - requestsAcked;
    if (probeRan && probeLoss > 0) return 'FAIL ($probeLoss probes lost)';
    if (floodRan && tokenLoss > 0) return 'FAIL ($tokenLoss tokens lost)';
    if (floodRan && reqLoss > 0) return 'FAIL ($reqLoss requests/approvals lost)';
    final all = [...probeRttMs, ...tokenRttMs, ...requestRttMs]..sort();
    final p95 = _pct(all, 0.95);
    if (p95 > 2000) return 'FAIL (p95 ${p95}ms)';
    if (p95 > 500) return 'WARN (p95 ${p95}ms)';
    if (!cleanupAnswered) return 'PASS (cleanup pending: device will self-clean on reconnect)';
    if (cleanupRemaining > 0) return 'WARN ($cleanupRemaining test tokens still on device)';
    return 'PASS';
  }
}

class StressResult {
  final String testId;
  final StressMode mode;
  final DateTime startedAt;
  final double seconds;
  final List<DeviceStress> devices;
  final Map<String, dynamic> serverBefore;
  final Map<String, dynamic> serverAfter;
  final bool cancelled;
  final List<String> savedPaths;

  StressResult({
    required this.testId,
    required this.mode,
    required this.startedAt,
    required this.seconds,
    required this.devices,
    required this.serverBefore,
    required this.serverAfter,
    required this.cancelled,
    this.savedPaths = const [],
  });

  bool get probeRan => mode != StressMode.flood;
  bool get floodRan => mode != StressMode.probe;

  bool get allPassed => devices.isNotEmpty && devices.every((d) => d.verdict(probeRan, floodRan).startsWith('PASS'));

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'mode': mode.name,
        'startedAt': startedAt.toIso8601String(),
        'durationSeconds': double.parse(seconds.toStringAsFixed(1)),
        'cancelled': cancelled,
        'overallPassed': allPassed,
        'devices': [
          for (final d in devices) {...d.toJson(), 'verdict': d.verdict(probeRan, floodRan)}
        ],
        'server': {'before': serverBefore, 'after': serverAfter},
      };

  String toText() {
    final b = StringBuffer();
    void line(String s) {
      b.writeln(s);
    }
    line('=' * 78);
    line('GMWF SERVER STRESS TEST REPORT');
    line('=' * 78);
    line('Test id   : $testId');
    line('Mode      : ${mode.name.toUpperCase()}${cancelled ? "  (CANCELLED EARLY)" : ""}');
    line('Started    : ${startedAt.toIso8601String()}');
    line('Duration   : ${seconds.toStringAsFixed(1)} s');
    line('Devices    : ${devices.length}');
    line('Verdict    : ${allPassed ? "ALL DEVICES PASSED" : (devices.isEmpty ? "NO DEVICES CONNECTED" : "ISSUES FOUND")}');
    line('');
    line('SERVER   before -> after');
    for (final k in serverBefore.keys) {
      line('  ${k.padRight(18)}: ${serverBefore[k]}  ->  ${serverAfter[k]}');
    }
    line('');
    line('PER DEVICE');
    line('-' * 78);
    for (final d in devices) {
      final j = d.toJson();
      final pr = j['probe'] as Map<String, dynamic>;
      final fl = j['flood'] as Map<String, dynamic>;
      line('${d.username} (${d.role})  ${d.ip}');
      line('  verdict   : ${d.verdict(probeRan, floodRan)}');
      if (probeRan) {
        final r = pr['rttMs'] as Map<String, dynamic>;
        line('  probe     : ${pr['acked']}/${pr['sent']} answered (${pr['lossPercent']}% lost)  '
            'round trip p50=${r['p50']}ms p95=${r['p95']}ms max=${r['max']}ms');
      }
      if (floodRan) {
        final r = fl['rttMs'] as Map<String, dynamic>;
        line('  tokens    : ${fl['acked']}/${fl['sent']} delivered (${fl['lossPercent']}% lost)  '
            'delivery p50=${r['p50']}ms p95=${r['p95']}ms max=${r['max']}ms');
      }
      if (floodRan) {
        final rq = j['requestsApprovals'] as Map<String, dynamic>;
        final r = rq['rttMs'] as Map<String, dynamic>;
        line('  requests  : ${rq['acked']}/${rq['sent']} delivered (${rq['lossPercent']}% lost)  '
            'delivery p50=${r['p50']}ms p95=${r['p95']}ms max=${r['max']}ms');
      }
      line('  connection: ${d.lostConnection ? "LOST during test" : (d.reconnected ? "dropped and reconnected" : "stable")}'
          '${d.sendFailures > 0 ? "  (${d.sendFailures} sends failed)" : ""}');
      line('  cleanup   : ${d.cleanupAnswered ? "removed ${d.cleanupRemoved}, ${d.cleanupRemaining} left on device" : "no answer (device will purge on reconnect)"}');
      line('');
    }
    if (savedPaths.isNotEmpty) {
      line('Saved to:');
      for (final p in savedPaths) {
        line('  $p');
      }
    }
    return b.toString();
  }
}

class StressTestEngine {
  final LanServer server;
  final int Function() cloudQueueSize;

  StressTestEngine({required this.server, required this.cloudQueueSize});

  static const int probeRounds = 100;
  static const Duration probeGap = Duration(milliseconds: 150);
  static const int floodTokens = 100;
  static const Duration floodGap = Duration(milliseconds: 20);
  static const int requestCount = 40;

  late String _testId;
  final Map<String, DeviceStress> _bySocket = {};
  final Map<String, int> _sentAt = {};
  final Stopwatch _clock = Stopwatch();

  Map<String, dynamic> _serverSnapshot() {
    final m = SystemMetricsService().currentSnapshot;
    return {
      'cpu': m.cpuKnown ? '${(m.cpuPercent * 100).round()}%' : 'n/a',
      'memory': m.ramKnown ? '${m.usedRamGb}/${m.totalRamGb} GB' : 'n/a',
      'appRamMb': m.appProcessRamMb,
      'lanMessagesIn': LanServer.trafficMsgsIn,
      'lanMessagesOut': LanServer.trafficMsgsOut,
      'lanKBytes': ((LanServer.trafficBytesIn + LanServer.trafficBytesOut) / 1024).round(),
      'cloudQueue': cloudQueueSize(),
      'devicesConnected': server.stressClientSnapshot().length,
    };
  }

  void _onMessage(String socketId, Map<String, dynamic> m) {
    final type = (m['event_type'] ?? m['type'] ?? '').toString();
    if (m['testId'] != _testId) return; // reply from an older / other test
    final dev = _bySocket[socketId];
    if (dev == null) return;
    final now = _clock.elapsedMilliseconds;
    switch (type) {
      case 'stress_probe_ack':
        final t0 = _sentAt['p:${m['seq']}:$socketId'];
        if (t0 != null) {
          dev.probesAcked++;
          dev.probeRttMs.add(now - t0);
        }
        break;
      case 'stress_token_ack':
        final t0 = _sentAt['t:${m['i']}:$socketId'];
        if (t0 != null) {
          dev.tokensAcked++;
          dev.tokenRttMs.add(now - t0);
        }
        break;
      case 'stress_request_ack':
        final t0 = _sentAt['r:${m['i']}:$socketId'];
        if (t0 != null) {
          dev.requestsAcked++;
          dev.requestRttMs.add(now - t0);
        }
        break;
      case 'stress_cleanup_ack':
        dev.cleanupAnswered = true;
        dev.cleanupRemoved = (m['removed'] as num?)?.toInt() ?? 0;
        dev.cleanupRemaining = (m['remaining'] as num?)?.toInt() ?? -1;
        break;
    }
  }

  bool _send(DeviceStress d, Map<String, dynamic> msg) {
    final ok = server.sendToSocket(d.socketId, jsonEncode(msg));
    if (!ok) d.sendFailures++;
    return ok;
  }

  Future<StressResult> run(
    StressMode mode, {
    void Function(String phase, double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final startedAt = DateTime.now();
    _testId = 'st${startedAt.millisecondsSinceEpoch}';
    _clock
      ..reset()
      ..start();
    _bySocket.clear();
    _sentAt.clear();

    final before = _serverSnapshot();
    final startSnapshot = server.stressClientSnapshot();
    for (final c in startSnapshot) {
      final id = c['socketId'].toString();
      _bySocket[id] = DeviceStress(
        socketId: id,
        clientId: (c['clientId'] ?? '').toString(),
        role: (c['role'] ?? 'unknown').toString(),
        username: (c['username'] ?? 'unknown').toString(),
        ip: (c['ip'] ?? '').toString(),
      );
    }
    final devices = _bySocket.values.toList();
    server.onStressMessage = _onMessage;
    var cancelled = false;
    bool stop() {
      if (isCancelled?.call() == true) cancelled = true;
      return cancelled;
    }

    try {
      if (devices.isNotEmpty && (mode == StressMode.probe || mode == StressMode.both)) {
        for (var seq = 1; seq <= probeRounds && !stop(); seq++) {
          onProgress?.call('Probing devices ($seq/$probeRounds)', seq / probeRounds);
          final t = _clock.elapsedMilliseconds;
          for (final d in devices) {
            _sentAt['p:$seq:${d.socketId}'] = t;
            if (_send(d, {
              'event_type': 'stress_probe',
              'testId': _testId,
              'seq': seq,
              'pad': 'x' * 200, // a realistic small frame size
            })) {
              d.probesSent++;
            }
          }
          await Future.delayed(probeGap);
        }
        onProgress?.call('Waiting for late probe answers', 1);
        await Future.delayed(const Duration(seconds: 3));
      }

      if (devices.isNotEmpty && (mode == StressMode.flood || mode == StressMode.both) && !stop()) {
        for (var i = 1; i <= floodTokens && !stop(); i++) {
          onProgress?.call('Sending test tokens ($i/$floodTokens)', i / floodTokens);
          final t = _clock.elapsedMilliseconds;
          final serial = 'STRESS-$_testId-${i.toString().padLeft(3, '0')}';
          for (final d in devices) {
            _sentAt['t:$i:${d.socketId}'] = t;
            if (_send(d, {
              'event_type': 'stress_token',
              'testId': _testId,
              'i': i,
              'serial': serial,
              'data': {
                'patientName': 'STRESS TEST #$i',
                'status': 'waiting',
                'dispenseStatus': 'waiting',
                'queueType': 'zakat',
                'branchId': 'stress_test',
                'isStressTest': true,
              },
            })) {
              d.tokensSent++;
            }
          }
          await Future.delayed(floodGap);
        }
        // Request / approval style traffic (token reversals, stock requests, approvals) is carried
        // by the same channel; this measures its delivery without touching any real stock or
        // request data.
        for (var i = 1; i <= requestCount && !stop(); i++) {
          onProgress?.call('Sending requests and approvals ($i/$requestCount)', i / requestCount);
          final t = _clock.elapsedMilliseconds;
          for (final d in devices) {
            _sentAt['r:$i:${d.socketId}'] = t;
            if (_send(d, {
              'event_type': 'stress_request',
              'testId': _testId,
              'i': i,
              'kind': i.isEven ? 'approval' : 'inventory_request',
            })) {
              d.requestsSent++;
            }
          }
          await Future.delayed(const Duration(milliseconds: 40));
        }
        onProgress?.call('Waiting for late deliveries', 1);
        await Future.delayed(const Duration(seconds: 4));
      }
    } finally {
      // ── Who is still connected? ──────────────────────────────────────────────
      final now = server.stressClientSnapshot();
      for (final d in devices) {
        final still = now.where((c) => c['socketId'].toString() == d.socketId).isNotEmpty;
        if (!still) {
          final back = d.clientId.isNotEmpty && now.any((c) => (c['clientId'] ?? '') == d.clientId);
          if (back) {
            d.reconnected = true;
          } else {
            d.lostConnection = true;
          }
        }
      }

      // ── Always clean up, even when cancelled ─────────────────────────────────
      onProgress?.call('Deleting test tokens from every device', 1);
      for (final d in devices) {
        // A device that reconnected has a new socket id: find it by client id.
        var target = d.socketId;
        if (d.reconnected) {
          final c = now.firstWhere((c) => (c['clientId'] ?? '') == d.clientId, orElse: () => {});
          if (c.isNotEmpty) {
            target = c['socketId'].toString();
            _bySocket[target] = d;
          }
        }
        server.sendToSocket(target, jsonEncode({'event_type': 'stress_cleanup', 'testId': _testId}));
      }
      for (var waited = 0; waited < 100 && devices.any((d) => !d.cleanupAnswered && !d.lostConnection); waited++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      server.onStressMessage = null;
    }

    final after = _serverSnapshot();
    final result = StressResult(
      testId: _testId,
      mode: mode,
      startedAt: startedAt,
      seconds: _clock.elapsedMilliseconds / 1000.0,
      devices: devices,
      serverBefore: before,
      serverAfter: after,
      cancelled: cancelled,
    );
    final saved = await _save(result);
    return StressResult(
      testId: result.testId,
      mode: result.mode,
      startedAt: result.startedAt,
      seconds: result.seconds,
      devices: result.devices,
      serverBefore: result.serverBefore,
      serverAfter: result.serverAfter,
      cancelled: result.cancelled,
      savedPaths: saved,
    );
  }

  Future<List<String>> _save(StressResult r) async {
    final stamp = r.startedAt.toIso8601String().substring(0, 19).replaceAll(':', '-').replaceAll('T', '_');
    final saved = <String>[];
    final dirs = <Directory>[];
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null) {
      for (final p in ['$home${Platform.pathSeparator}Desktop', '$home${Platform.pathSeparator}OneDrive${Platform.pathSeparator}Desktop']) {
        final d = Directory(p);
        if (d.existsSync()) dirs.add(d);
      }
    }
    if (dirs.isEmpty) dirs.add(Directory.current);
    final text = r.toText();
    final json = const JsonEncoder.withIndent('  ').convert(r.toJson());
    for (final d in dirs) {
      try {
        final sep = Platform.pathSeparator;
        final t = File('${d.path}${sep}GMWF_Server_StressTest_$stamp.txt');
        await t.writeAsString(text, flush: true);
        await File('${d.path}${sep}GMWF_Server_StressTest_$stamp.json').writeAsString(json, flush: true);
        saved.add(t.path);
      } catch (e) {
        debugPrint('[StressTest] Could not save report to ${d.path}: $e');
      }
    }
    return saved;
  }
}
