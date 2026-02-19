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
    Duration timeout = const Duration(seconds: 12),
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Searching for server...');
    debugPrint('LanDiscovery: Starting parallel discovery');

    final completer = Completer<DiscoveredServer?>();

    _tryMdns(completer, onStatus);
    _tryUdp(completer, onStatus);
    _tryScan(completer, onStatus);

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
            d.stop();
          }
        }
      });
      Future.delayed(const Duration(seconds: 8), d.stop);
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
      Future.delayed(const Duration(seconds: 10), () { try { sock.close(); } catch (_) {} });
    } catch (e) {
      debugPrint('UDP error: $e');
    }
  }

  static Future<void> _tryScan(Completer<DiscoveredServer?> c, void Function(String)? s) async {
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (c.isCompleted) return;

      final myIp = await getPrimaryLanIp();
      if (myIp == null || myIp.isEmpty) return;

      final parts = myIp.split('.');
      if (parts.length != 4) return;
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      final port = AppNetwork.websocketPort;

      debugPrint('Subnet scan: $subnet.1-254 :$port');
      s?.call('Scanning $subnet.*...');

      const batchSize = 25;
      for (int b = 0; b < 11 && !c.isCompleted; b++) {
        final start = b * batchSize + 1;
        final end = ((b + 1) * batchSize).clamp(1, 254);
        await Future.wait([
          for (int i = start; i <= end; i++)
            if ('$subnet.$i' != myIp) _probe('$subnet.$i', port, c)
        ]);
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    }
  }

  static Future<void> _probe(String host, int port, Completer<DiscoveredServer?> c) async {
    if (c.isCompleted) return;
    try {
      final sock = await Socket.connect(host, port, timeout: const Duration(milliseconds: 500));
      sock.destroy();
      if (!c.isCompleted) {
        final ok = await _verify(host, port);
        if (ok && !c.isCompleted) {
          debugPrint('Scan found: $host:$port');
          c.complete(DiscoveredServer(ip: host, port: port, method: 'scan'));
        }
      }
    } on SocketException {
      // unreachable
    } catch (_) {}
  }

  static Future<bool> _verify(String host, int port) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 400);
      final req = await client.get(host, port, '/');
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      return body.contains('GMWF');
    } catch (_) {
      return true; // TCP connected = probably our server
    }
  }

  static Future<bool> isReachable(String ip, int port) async {
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 800));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}