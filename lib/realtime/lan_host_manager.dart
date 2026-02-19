// lib/realtime/lan_host_manager.dart
// CHANGE FROM ORIGINAL: 
//   1. startHost() ALWAYS fetches fresh IP (removed the early-return that skipped IP detection)
//   2. Added _ipWatchTimer that auto-restarts when router changes
//   3. stopHost() now accepts clearBranchId param so internal restart preserves branchId
// Everything else is identical to your original.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import 'lan_server.dart';
import 'lan_client.dart';
import '../utils/network_utils.dart';

class LanHostManager {
  static LanServer? _server;
  static LanClient? _localClient;
  static BonsoirBroadcast? _mdnsBroadcast;
  static bool get isHostRunning => _server != null;
  static String? _hostBranchId;

  static LanClient? get localClient => _localClient;

  static Timer? _broadcastTimer;
  static Timer? _ipWatchTimer; // ← NEW: watches for router/IP changes
  static String? _currentIp;

  static Future<void> startHost({
    bool forceRefreshIp = false,
    String? branchId,
  }) async {
    if (branchId != null) {
      _hostBranchId = branchId.toLowerCase().trim();
    }

    // ── FIX: ALWAYS get a fresh IP — never trust the cached value ──────────
    // Original code did: if (_server != null && !forceRefreshIp) return;
    // That skipped IP detection entirely after first start, so switching routers
    // left the server bound to the old IP.
    final freshIp = await getPrimaryLanIp();

    if (freshIp == null || freshIp.isEmpty) {
      debugPrint('LanHostManager: No LAN IP available — cannot start host');
      return;
    }

    final oldIp = _currentIp;
    final ipChanged = oldIp != null && oldIp != freshIp;
    final alreadyRunning = _server != null && !ipChanged && !forceRefreshIp;

    if (alreadyRunning) {
      debugPrint('LanHostManager: Already running on $oldIp — skipping');
      return;
    }

    if (ipChanged) {
      debugPrint('LanHostManager: IP changed $oldIp → $freshIp → restarting');
      await stopHost(clearBranchId: false);
    }
    // ── END FIX ─────────────────────────────────────────────────────────────

    _currentIp = freshIp;

    try {
      // Step 1: Start the server
      _server = LanServer(port: AppNetwork.websocketPort);
      await _server!.start(_currentIp);
      debugPrint('✅ Step 1: LAN server started on $_currentIp:${AppNetwork.websocketPort}');

      // Step 2: Wait for server to be fully ready
      await Future.delayed(const Duration(milliseconds: 800));

      // Step 3: Create local client and connect
      _localClient = LanClient(
        serverIp: _currentIp ?? '127.0.0.1',
        port: AppNetwork.websocketPort,
      );

      debugPrint('🔄 Step 2: Connecting local client to own server...');
      await _localClient!.connect();

      // Step 4: Wait for connection to be established
      int attempts = 0;
      while (!_localClient!.isConnected && attempts < 15) {
        await Future.delayed(const Duration(milliseconds: 300));
        attempts++;
        debugPrint('   Waiting for local client connection... attempt $attempts/15');
      }

      if (!_localClient!.isConnected) {
        throw Exception('Local client failed to connect after ${attempts * 300}ms');
      }

      debugPrint('✅ Step 3: Local client connected successfully');

      // Step 5: Identify the local client (if we have branchId)
      if (_hostBranchId != null) {
        await _identifyLocalClient(_hostBranchId!);
      } else {
        debugPrint('⚠️ No branchId provided yet - will identify later');
      }

      // Step 6: Start mDNS and UDP broadcast
      await _startMdnsAdvertisement();
      _startIpBroadcast(_currentIp!);

      // Step 7: NEW — watch for IP changes (router switch)
      _startIpWatcher();

      debugPrint('✅ Host startup complete!');
    } catch (e, stack) {
      debugPrint('❌ Failed to start LAN host: $e\n$stack');
      rethrow;
    }
  }

  // ── NEW: polls every 10s, auto-restarts if IP changes ─────────────────────
  static void _startIpWatcher() {
    _ipWatchTimer?.cancel();
    _ipWatchTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final ip = await getPrimaryLanIp();
      if (ip != null && ip.isNotEmpty && ip != _currentIp) {
        debugPrint('LanHostManager: IP changed to $ip — auto-restarting');
        await startHost(forceRefreshIp: true, branchId: _hostBranchId);
      }
    });
  }

  // ── Everything below is IDENTICAL to your original ─────────────────────────

  static Future<void> identifyLocalClientWithBranch(String branchId) async {
    _hostBranchId = branchId.toLowerCase().trim();

    if (_localClient == null || !_localClient!.isConnected) {
      debugPrint('❌ Cannot identify - local client not ready');
      return;
    }

    await _identifyLocalClient(_hostBranchId!);
  }

  static Future<void> _identifyLocalClient(String branchId) async {
    debugPrint('╔════════════════════════════════════════════════════════════╗');
    debugPrint('║ IDENTIFYING LOCAL CLIENT TO SERVER                        ║');
    debugPrint('╠════════════════════════════════════════════════════════════╣');
    debugPrint('║ Role: receptionist                                         ║');
    debugPrint('║ Branch: $branchId                                          ║');
    debugPrint('╚════════════════════════════════════════════════════════════╝');

    final identifyMsg = {
      'event_type': 'identify',
      'role': 'receptionist',
      'branchId': branchId,
      '_clientId': 'receptionist_local_${DateTime.now().millisecondsSinceEpoch}',
      '_timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localClient!.sendMessage(identifyMsg);
    debugPrint('📤 Sent identification message');

    final completer = Completer<bool>();
    late StreamSubscription subscription;
    subscription = _localClient!.onMessage.listen((message) {
      try {
        final data = jsonDecode(message);
        if (data['event_type'] == 'identified') {
          debugPrint('✅ Server confirmed local client identification!');
          if (!completer.isCompleted) completer.complete(true);
        }
      } catch (e) {
        // Not JSON or different message
      }
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final success = await completer.future;
    await subscription.cancel();

    if (success) {
      debugPrint('✅✅✅ Local client successfully identified as receptionist! ✅✅✅');
    } else {
      debugPrint('⚠️⚠️⚠️ No identification confirmation - but continuing anyway ⚠️⚠️⚠️');
    }
  }

  static Future<void> _startMdnsAdvertisement() async {
    try {
      // Stop any existing broadcast before starting a new one
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;

      final service = BonsoirService(
        name: 'GMWF Token Server',
        type: '_gmwftoken._tcp',
        port: AppNetwork.websocketPort,
        attributes: {'txtvers': '1', 'app': 'gmwf'},
      );

      _mdnsBroadcast = BonsoirBroadcast(service: service);
      await _mdnsBroadcast!.start();

      debugPrint('mDNS service advertised: ${service.name} on port ${AppNetwork.websocketPort}');
    } catch (e) {
      debugPrint('mDNS advertisement failed: $e (UDP fallback still active)');
    }
  }

  static void _startIpBroadcast(String primaryIp) {
    _broadcastTimer?.cancel();

    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;

        final message = utf8.encode(
            '${AppNetwork.udpMessagePrefix}$primaryIp:${AppNetwork.websocketPort}');

        socket.send(
            message, InternetAddress('255.255.255.255'), AppNetwork.udpBroadcastPort);
        debugPrint('UDP Broadcast sent: $primaryIp:${AppNetwork.websocketPort}');

        socket.close();
      } catch (e) {
        debugPrint('UDP broadcast failed: $e');
      }
    });
  }

  static void broadcast(String message) {
    if (_server == null) {
      debugPrint('Cannot broadcast: LanServer not running');
      return;
    }
    _server!.broadcast(message);
  }

  static Future<Map<String, dynamic>?> autoDiscoverServer({int retries = 4}) async {
    final mdnsResult = await _discoverViaMdns();
    if (mdnsResult != null) return mdnsResult;

    debugPrint('mDNS discovery failed → falling back to UDP');
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4, AppNetwork.udpBroadcastPort);
        debugPrint('UDP listening on port ${AppNetwork.udpBroadcastPort} (attempt $attempt)...');

        final completer = Completer<Map<String, dynamic>?>();

        final sub = socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null) {
              final received = utf8.decode(datagram.data);
              if (received.startsWith(AppNetwork.udpMessagePrefix)) {
                final payload =
                    received.substring(AppNetwork.udpMessagePrefix.length).trim();
                final parts = payload.split(':');
                final ip = parts[0];
                final port = parts.length > 1
                    ? int.tryParse(parts[1]) ?? AppNetwork.websocketPort
                    : AppNetwork.websocketPort;
                if (ip.isNotEmpty && !completer.isCompleted) {
                  debugPrint('UDP discovered: $ip:$port');
                  completer.complete({'ip': ip, 'port': port});
                }
              }
            }
          }
        });

        Timer(const Duration(seconds: 6), () {
          if (!completer.isCompleted) completer.complete(null);
        });

        final result = await completer.future;
        sub.cancel();
        socket.close();

        if (result != null) return result;
      } catch (e) {
        debugPrint('UDP auto-discovery attempt $attempt failed: $e');
      }

      await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint('Auto-discovery failed after $retries attempts');
    return null;
  }

  static Future<Map<String, dynamic>?> _discoverViaMdns() async {
    try {
      final discovery = BonsoirDiscovery(type: '_gmwftoken._tcp');
      await discovery.start();

      final completer = Completer<Map<String, dynamic>?>();

      final sub = discovery.eventStream!.listen((event) {
        if (event is BonsoirDiscoveryServiceResolvedEvent) {
          final service = event.service;
          debugPrint('mDNS resolved: ${service.name} → ${service.host}:${service.port}');
          completer.complete({'ip': service.host, 'port': service.port});
          discovery.stop();
        }
      });

      Timer(const Duration(seconds: 12), () {
        if (!completer.isCompleted) {
          completer.complete(null);
          discovery.stop();
        }
      });

      final result = await completer.future;
      sub.cancel();
      await discovery.stop();

      return result;
    } catch (e) {
      debugPrint('mDNS discovery failed: $e');
      return null;
    }
  }

  // ── stopHost gets an optional clearBranchId param so internal restart works ─
  static Future<void> stopHost({bool clearBranchId = true}) async {
    print('Stopping LAN host mode...');
    _broadcastTimer?.cancel();
    _ipWatchTimer?.cancel();
    _broadcastTimer = null;
    _ipWatchTimer = null;

    try {
      await _localClient?.disconnect();
      await _server?.stop();
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      debugPrint('LAN host mode fully stopped');
    } catch (e) {
      debugPrint('Error stopping host: $e');
    } finally {
      _localClient = null;
      _server = null;
      _currentIp = null;
      if (clearBranchId) _hostBranchId = null;
    }
  }
}