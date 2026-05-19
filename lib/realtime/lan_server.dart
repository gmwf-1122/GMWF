// lib/realtime/lan_server.dart
//
// CHANGES IN THIS VERSION:
//   1. _handleMessage() now extracts 'username' from identify payload
//      and stores it in _clientInfo.
//   2. getConnectedClients() includes username in returned map.
//   3. onClientConnected callback info map includes username.
//   4. [DEDUP] Server-side _messageId deduplication with 24-hour TTL.
//      Duplicate messages receive an immediate ACK but are NOT processed
//      or broadcast again — eliminates double-processing on reconnect.
//   5. [DEDUP] _purgeOldMessageIds() runs every 10 minutes to keep memory bounded.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import '../config/constants.dart';

class LanServer {
  HttpServer? _server;

  final List<WebSocket>                      _clients    = [];
  final Map<String, WebSocket>               _socketById = {};
  final Map<WebSocket, Map<String, dynamic>> _clientInfo = {};

  final int port;

  int _messagesReceived = 0;
  int _messagesSent     = 0;

  RawDatagramSocket? _udpSocket;
  Timer? _udpTimer;

  // ── [DEDUP] Processed message IDs with timestamps for 24-hour TTL ──────────
  // LinkedHashMap preserves insertion order so oldest entries can be purged fast.
  final LinkedHashMap<String, DateTime> _processedMessageIds =
      LinkedHashMap<String, DateTime>();
  static const _dedupTtl       = Duration(hours: 24);
  static const _dedupMaxSize   = 50000; // hard cap to prevent unbounded growth
  Timer? _dedupPurgeTimer;

  // ── Callbacks ──────────────────────────────────────────────────────────────
  Function(String socketId, Map<String, dynamic> info)? onClientConnected;
  Function(String socketId)?                             onClientDisconnected;
  Function(Map<String, dynamic>)?                        onMessageReceived;

  LanServer({this.port = AppNetwork.websocketPort});

  int get clientCount      => _clientInfo.length;
  int get messagesReceived => _messagesReceived;
  int get messagesSent     => _messagesSent;

  // ── Start ──────────────────────────────────────────────────────────────────
  Future<void> start(String? forcedIp) async {
    try {
      _server = await HttpServer.bind(
          InternetAddress.anyIPv4, port, shared: true);

      final ipShown = forcedIp ?? 'your-LAN-IP';
      print('╔════════════════════════════════════════════════════════════╗');
      print('║ LAN WebSocket Server STARTED                               ║');
      print('║ Listening: 0.0.0.0:$port  (share $ipShown:$port)          ║');
      print('╚════════════════════════════════════════════════════════════╝');

      _server!.listen((HttpRequest request) async {
        // Handle preflight requests for Chrome/Edge Private Network Access (PNA)
        if (request.method == 'OPTIONS') {
          request.response
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            ..headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept')
            ..headers.add('Access-Control-Allow-Private-Network', 'true')
            ..statusCode = HttpStatus.noContent
            ..close();
          return;
        }

        if (WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            _addClient(socket);
          } catch (e) {
            print('WebSocket upgrade failed: $e');
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write('WebSocket upgrade failed')
              ..close();
          }
        } else {
          // HTTP health-check — LanDiscovery._verify() looks for 'GMWF'.
          request.response
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..headers.add('Access-Control-Allow-Private-Network', 'true')
            ..statusCode = HttpStatus.ok
            ..write('GMWF LAN Token Server — ws://$ipShown:$port')
            ..close();
        }
      });

      _startUdpBroadcast(ipShown);
      _startDedupPurgeTimer();

    } catch (e) {
      print('╔════════════════════════════════════════════════════════════╗');
      print('║ FAILED TO START LAN SERVER on port $port                   ║');
      print('║ Error: $e');
      print('╚════════════════════════════════════════════════════════════╝');
      rethrow;
    }
  }

  // ── UDP Broadcast ──────────────────────────────────────────────────────────
  void _startUdpBroadcast(String ipShown) {
    try {
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
        socket.broadcastEnabled = true;
        _udpSocket = socket;
        
        final payload = utf8.encode('${AppNetwork.udpMessagePrefix}$ipShown:$port');
        final broadcastAddr = InternetAddress('255.255.255.255');
        
        _udpTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          try {
            _udpSocket?.send(payload, broadcastAddr, AppNetwork.udpBroadcastPort);
          } catch (e) {
            print('[LanServer] UDP send error: $e');
          }
        });
        print('[LanServer] UDP Broadcaster started.');
      });
    } catch (e) {
      print('[LanServer] Failed to start UDP broadcast: $e');
    }
  }

  // ── [DEDUP] Purge processed-ID map every 10 minutes ───────────────────────
  void _startDedupPurgeTimer() {
    _dedupPurgeTimer?.cancel();
    _dedupPurgeTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _purgeOldMessageIds();
    });
  }

  void _purgeOldMessageIds() {
    final cutoff = DateTime.now().subtract(_dedupTtl);
    // Remove entries older than TTL (LinkedHashMap is insertion-ordered).
    _processedMessageIds.removeWhere((_, ts) => ts.isBefore(cutoff));

    // Hard cap — remove oldest entries first if still over size limit.
    if (_processedMessageIds.length > _dedupMaxSize) {
      final overflow = _processedMessageIds.length - _dedupMaxSize;
      final keysToRemove = _processedMessageIds.keys.take(overflow).toList();
      for (final k in keysToRemove) {
        _processedMessageIds.remove(k);
      }
    }
    print('[LanServer] Dedup purge: ${_processedMessageIds.length} IDs retained');
  }

  // ── Add client ─────────────────────────────────────────────────────────────
  void _addClient(WebSocket socket) {
    final socketId = socket.hashCode.toString();
    _clients.add(socket);
    _socketById[socketId] = socket;

    print('╔════════════════════════════════════════════════════════════╗');
    print('║ NEW CLIENT CONNECTED  Socket: $socketId  '
        'Total: ${_clients.length}');
    print('╚════════════════════════════════════════════════════════════╝');

    // Ask the new client to identify itself.
    socket.add(jsonEncode({
      'event_type': 'identify_request',
      'timestamp':  DateTime.now().toIso8601String(),
      'message':    'Please identify your role and branch',
    }));

    socket.listen(
      (message) => _handleMessage(socket, socketId, message),
      onDone:  () => _removeClient(socket),
      onError: (_) => _removeClient(socket),
    );
  }

  // ── Handle message ─────────────────────────────────────────────────────────
  void _handleMessage(WebSocket socket, String socketId, dynamic message) {
    if (message is! String) return;
    final trimmed = message.trim();

    // Ping / pong keep-alive.
    if (trimmed == 'ping' || trimmed == '{"type":"ping"}') {
      socket.add('pong');
      return;
    }
    if (trimmed == 'pong' || trimmed == '{"type":"pong"}') return;

    try {
      final data      = jsonDecode(message) as Map<String, dynamic>;
      final eventType = data['event_type'] as String?;
      _messagesReceived++;

      // ── Identify handshake ────────────────────────────────────────────────
      if (eventType == 'identify') {
        final role     = data['role']     as String?;
        final branchId = data['branchId'] as String?;
        final clientId = data['_clientId'] as String?;
        // Extract username sent by client; fall back to role label.
        final username = (data['username'] as String?)?.trim().isNotEmpty == true
            ? data['username'] as String
            : role ?? 'unknown';

        if (role != null && branchId != null) {
          final info = {
            'role':        role.toLowerCase().trim(),
            'branchId':    branchId.toLowerCase().trim(),
            'username':    username,
            'clientId':    clientId,
            'identified':  true,
            'connectedAt': DateTime.now().toIso8601String(),
          };
          _clientInfo[socket] = info;

          print('╔════════════════════════════════════════════════════════════╗');
          print('║ CLIENT IDENTIFIED  Socket: $socketId');
          print('║ Role: $role  Branch: $branchId  Username: $username');
          print('║ Total identified: ${_clientInfo.length}');
          print('╚════════════════════════════════════════════════════════════╝');

          // Confirm identification to client.
          socket.add(jsonEncode({
            'event_type': 'identified',
            'role':       role,
            'branchId':   branchId,
            'username':   username,
            'clientId':   clientId,
            'timestamp':  DateTime.now().toIso8601String(),
          }));

          onClientConnected?.call(socketId, info);
          _broadcastClientCount();
        } else {
          print('⚠️ Incomplete identification: role=$role branch=$branchId');
        }
        return;
      }

      // ── Reject unidentified clients ───────────────────────────────────────
      if (_clientInfo[socket]?['identified'] != true) {
        print('❌ Message from UNIDENTIFIED client $socketId — rejecting');
        return;
      }

      // ── [DEDUP] Server-side deduplication ─────────────────────────────────
      final messageId = data['_messageId'] as String?;
      if (messageId != null && messageId.isNotEmpty) {
        if (_processedMessageIds.containsKey(messageId)) {
          // Already processed — send immediate ACK so client removes from outbox
          // but do NOT process or broadcast.
          print('[LanServer] ⚠️ Duplicate messageId=$messageId from $socketId — ACK & ignore');
          socket.add(jsonEncode({
            'event_type': 'message_ack',
            'messageId':  messageId,
            'duplicate':  true,
          }));
          return;
        }
        // Mark as processed with current timestamp.
        _processedMessageIds[messageId] = DateTime.now();
      }

      // ── Acknowledge message immediately ───────────────────────────────────
      if (messageId != null && messageId.isNotEmpty) {
        socket.add(jsonEncode({
          'event_type': 'message_ack',
          'messageId':  messageId,
          'duplicate':  false,
        }));
      }

      // ── Enrich and route ──────────────────────────────────────────────────
      final enhanced = Map<String, dynamic>.from(data);
      enhanced['_serverTimestamp']  = DateTime.now().toIso8601String();
      enhanced['_senderRole']       = _clientInfo[socket]!['role'];
      enhanced['_senderBranch']     = _clientInfo[socket]!['branchId'];
      enhanced['_senderUsername']   = _clientInfo[socket]!['username'];
      enhanced['_clientId']       ??= _clientInfo[socket]!['clientId'];
      // Attach socket ID so SSM can correctly credit the right connected user
      enhanced['_socketId']         = socketId;

      onMessageReceived?.call(enhanced);
      _routeMessage(socket, enhanced);
    } catch (e) {
      print('❌ Error processing message from $socketId: $e');
    }
  }

  // ── Route message to branch peers ──────────────────────────────────────────
  void _routeMessage(WebSocket sender, Map<String, dynamic> message) {
    final senderInfo = _clientInfo[sender];
    if (senderInfo == null) return;

    final senderBranch = senderInfo['branchId'] as String;
    final messageBranch =
        (message['branchId'] as String?)?.toLowerCase().trim() ??
        (message['data'] is Map
            ? (message['data']['branchId'] as String?)?.toLowerCase().trim()
            : null) ??
        senderBranch;

    final messageJson = jsonEncode(message);
    int sentCount = 0;

    for (final client in List<WebSocket>.from(_clients)) {
      if (client == sender) continue;
      if (client.readyState != WebSocket.open) continue;

      final info = _clientInfo[client];
      if (info == null || info['identified'] != true) continue;

      final clientBranch = (info['branchId'] as String?) ?? '';
      if (clientBranch != messageBranch && clientBranch != senderBranch) {
        continue;
      }

      try {
        client.add(messageJson);
        sentCount++;
        _messagesSent++;
      } catch (e) {
        print('❌ ERROR routing to ${client.hashCode}: $e');
      }
    }

    if (sentCount == 0 && message['event_type'] != 'identify') {
      print('⚠️ "${message['event_type']}" not delivered to any peer');
    }
  }

  // ── Remove client ──────────────────────────────────────────────────────────
  void _removeClient(WebSocket socket) {
    final socketId = socket.hashCode.toString();
    _clients.remove(socket);
    _socketById.remove(socketId);
    _clientInfo.remove(socket);

    print('╔════════════════════════════════════════════════════════════╗');
    print('║ CLIENT DISCONNECTED: $socketId  Remaining: ${_clients.length}');
    print('╚════════════════════════════════════════════════════════════╝');

    onClientDisconnected?.call(socketId);
    _broadcastClientCount();
  }

  // ── Public send helpers ────────────────────────────────────────────────────

  /// Send to ONE specific client by socketId (used for catch-up push).
  void sendToSocket(String socketId, String rawMessage) {
    final socket = _socketById[socketId];
    if (socket == null) {
      print('⚠️ sendToSocket: socket $socketId not found');
      return;
    }
    if (socket.readyState != WebSocket.open) {
      print('⚠️ sendToSocket: socket $socketId not open');
      return;
    }
    try {
      socket.add(rawMessage);
      _messagesSent++;
    } catch (e) {
      print('❌ sendToSocket error for $socketId: $e');
    }
  }

  /// Broadcast to ALL connected + identified clients.
  void broadcast(String rawMessage, {WebSocket? exclude}) {
    int forwarded = 0;
    for (final client in List<WebSocket>.from(_clients)) {
      if (client == exclude) continue;
      if (client.readyState != WebSocket.open) continue;
      try {
        client.add(rawMessage);
        forwarded++;
        _messagesSent++;
      } catch (_) {}
    }
    if (forwarded > 0) print('[LanServer] Broadcast → $forwarded client(s)');
  }

  /// Returns metadata (including username) for all identified clients.
  List<Map<String, dynamic>> getConnectedClients() {
    return _clientInfo.entries.map((e) {
      final socketId = e.key.hashCode.toString();
      return {
        'socketId': socketId,
        'role':     e.value['role'],
        'branchId': e.value['branchId'],
        'username': e.value['username'],
        'clientId': e.value['clientId'],
      };
    }).toList();
  }

  // ── Broadcast client count ─────────────────────────────────────────────────
  void _broadcastClientCount() {
    final countMsg = jsonEncode({
      'event_type': 'client_count_update',
      'count':      _clientInfo.length,
      'timestamp':  DateTime.now().toIso8601String(),
    });
    for (final client in _clients) {
      if (client.readyState == WebSocket.open &&
          _clientInfo.containsKey(client)) {
        try { client.add(countMsg); } catch (_) {}
      }
    }
  }

  Future<void> stop() async {
    print('[LanServer] Shutting down (${_clients.length} clients)...');
    _udpTimer?.cancel();
    _udpTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    _dedupPurgeTimer?.cancel();
    _dedupPurgeTimer = null;
    _processedMessageIds.clear();
    
    for (final client in _clients) {
      try { client.close(); } catch (_) {}
    }
    _clients.clear();
    _socketById.clear();
    _clientInfo.clear();
    try {
      await _server?.close(force: true);
    } catch (e) {
      print('[LanServer] Error closing server socket: $e');
    }
    _server = null;
    print('[LanServer] Fully stopped');
  }
}
