// lib/realtime/lan_discovery.dart
// Automatic server discovery: mDNS → UDP broadcast → parallel subnet scan.
// No manual IP needed. Usually finds server in under 3 seconds.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../utils/network_utils.dart';

class DiscoveredServer {
  final String ip;
  final int port;
  final String method;
  const DiscoveredServer({required this.ip, required this.port, required this.method});
  @override
  String toString() => '$ip:$port (via $method)';
}

class LanDiscovery {
  static Future<DiscoveredServer?> findServer({
    Duration timeout = const Duration(seconds: 8),
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Searching for server...');
    debugPrint('LanDiscovery: Starting parallel discovery');

    final completer = Completer<DiscoveredServer?>();

    _tryUdp(completer, onStatus);
    _tryScan(completer, onStatus);
    _tryMdns(completer, onStatus);

    Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  static Future<void> _tryMdns(Completer<DiscoveredServer?> c, void Function(String)? s) async {
    try {
      final d = BonsoirDiscovery(type: '_gmwftoken._tcp');
      await d.start();
      d.eventStream?.listen((e) {
        if (c.isCompleted) return;
        if (e is BonsoirDiscoveryServiceResolvedEvent) {
          final ip = e.service.host;
          final port = e.service.port;
          if (ip != null && ip.isNotEmpty) {
            debugPrint('mDNS found: $ip:$port');
            s?.call('Found server at $ip');
            c.complete(DiscoveredServer(ip: ip, port: port, method: 'mdns'));
            try { d.stop(); } catch (_) {}
          }
        }
      });
      Future.delayed(const Duration(seconds: 6), () {
        try { d.stop(); } catch (_) {}
      });
    } catch (e) {
      debugPrint('mDNS error: $e');
    }
  }

  static Future<void> _tryUdp(Completer<DiscoveredServer?> c, void Function(String)? s) async {
    try {
      final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, AppNetwork.udpBroadcastPort);
      sock.listen((ev) {
        if (c.isCompleted) { try { sock.close(); } catch (_) {} return; }
        if (ev == RawSocketEvent.read) {
          final dg = sock.receive();
          if (dg != null) {
            final msg = utf8.decode(dg.data);
            if (msg.startsWith(AppNetwork.udpMessagePrefix)) {
              final payload = msg.substring(AppNetwork.udpMessagePrefix.length).trim();
              final parts = payload.split(':');
              final ip = parts[0];
              final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? AppNetwork.websocketPort) : AppNetwork.websocketPort;
              if (ip.isNotEmpty) {
                debugPrint('UDP found: $ip:$port');
                s?.call('Found server at $ip');
                try { sock.close(); } catch (_) {}
                c.complete(DiscoveredServer(ip: ip, port: port, method: 'udp'));
              }
            }
          }
        }
      });
      Future.delayed(const Duration(seconds: 7), () { try { sock.close(); } catch (_) {} });
    } catch (e) {
      debugPrint('UDP error: $e');
    }
  }

  static Future<void> _tryScan(Completer<DiscoveredServer?> c, void Function(String)? s) async {
    try {
      if (c.isCompleted) return;

      final myIp = await getPrimaryLanIp();
      if (myIp == null || myIp.isEmpty) return;

      final parts = myIp.split('.');
      if (parts.length != 4) return;
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      final myLastOctet = int.tryParse(parts[3]) ?? 100;
      final port = AppNetwork.websocketPort;

      debugPrint('Subnet scan: $subnet.1-254 :$port');
      s?.call('Scanning $subnet.*...');

      // Build ordered list of IPs to probe:
      // Priority 1: Common static server IPs (.1, .100, .2, .10, .50, .200, .254)
      // Priority 2: Neighborhood around client's current IP (±15)
      // Priority 3: Remaining subnet IPs
      final prioritySet = <int>{1, 100, 2, 10, 50, 200, 254};
      for (int offset = 1; offset <= 15; offset++) {
        if (myLastOctet - offset >= 1) prioritySet.add(myLastOctet - offset);
        if (myLastOctet + offset <= 254) prioritySet.add(myLastOctet + offset);
      }
      prioritySet.remove(myLastOctet); // Skip self

      final allRemaining = <int>[];
      for (int i = 1; i <= 254; i++) {
        if (i != myLastOctet && !prioritySet.contains(i)) {
          allRemaining.add(i);
        }
      }

      final probeOrder = [...prioritySet, ...allRemaining];

      // Scan in parallel chunks of 40
      const batchSize = 40;
      for (int i = 0; i < probeOrder.length && !c.isCompleted; i += batchSize) {
        final chunk = probeOrder.sublist(i, (i + batchSize).clamp(0, probeOrder.length));
        await Future.wait(chunk.map((octet) => _probe('$subnet.$octet', port, c)));
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    }
  }

  static Future<void> _probe(String host, int port, Completer<DiscoveredServer?> c) async {
    if (c.isCompleted) return;
    try {
      final sock = await Socket.connect(host, port, timeout: const Duration(milliseconds: 350));
      sock.destroy();
      if (!c.isCompleted) {
        debugPrint('Scan found open port: $host:$port');
        c.complete(DiscoveredServer(ip: host, port: port, method: 'scan'));
      }
    } on SocketException {
      // unreachable
    } catch (_) {}
  }

  static Future<bool> isReachable(String ip, int port) async {
    if (kIsWeb) return true; // Web cannot use dart:io Socket, proceed directly to WebSocket connect
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 500));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
