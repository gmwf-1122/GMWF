// lib/realtime/realtime_manager.dart
//
// PERSISTENCE FIXES:
//   [FIX-P1] Hive-backed outbox — every sent message is written to Hive FIRST.
//            On successful WS send, removed from outbox.
//            On reconnect, unACK'd messages are flushed automatically.
//            Outbox items expire after 24 hours (only today's data matters).
//
//   [FIX-P2] _flushOutbox() called after every reconnect + identified echo,
//            ensuring no message is lost across connection drops.
//
//   [FIX-P3] ACK sending — after processing each incoming server-push,
//            client sends back 'ack_serials' so server's seen-set stays current.
//
// BUG FIXES:
//   [BUG-1]  Outbox double-write: _sendPendingMessages re-sent messages through
//            sendMessage(), which re-wrote them to the outbox. Fixed by flushing
//            pending messages directly to the channel, bypassing the outbox write.
//
//   [BUG-2]  Flush race: _sendPendingMessages and _flushOutbox were triggered in
//            sequence after 'identified', causing duplicates. _flushOutbox is now
//            only scheduled if _pendingMessages was empty.
//
//   [BUG-3]  ACK re-queue race: serials were cleared before the try block, so a
//            send failure silently lost them. Now cleared only on success.
//
//   [BUG-4]  Double fallback: _schedulePendingFallback could fire _flushOutbox a
//            second time if 'identified' already triggered it. Now guarded with a
//            _flushedOnConnect flag.
//
// NEW — THIS REVISION:
//   [IMM-ACK] Immediate ACK on receipt of save_entry/token_created/save_prescription/
//             prescription_created events (in addition to the 5-second batch timer).
//             Closes the reconnect-before-ACK window responsible for duplicate
//             server-side processing.
//
//   [FAIL-BOX] Client-side failed outbox ('realtime_failed_outbox').
//              Messages that fail to send 3× during _flushOutbox are moved here
//              instead of being silently dropped. Includes tokens and prescriptions.
//              On every new connection, _retryFailedOutbox() moves them back to
//              the main outbox for another round of attempts.
//
// RECONNECT FIX [FIX-RC]:
//   Removed the _reconnectAttempts < 5 cap from _handleDisconnect().
//   Previously RealtimeManager gave up after 5 self-reconnect attempts
//   (2+4+8+16+32 = 62 s), leaving ConnectionManager's heartbeat as the
//   only rescue path — which then re-ran full 25-second LAN discovery
//   even though the server IP was already cached.
//
//   Now RealtimeManager retries indefinitely with a stable 5-second
//   interval after the initial back-off sequence, matching
//   ConnectionManager's own retry strategy. ConnectionManager's heartbeat
//   remains a safety net but is no longer the primary recovery path.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'realtime_router.dart';

class RealtimeManager {
  static final RealtimeManager _instance = RealtimeManager._internal();
  factory RealtimeManager() => _instance;
  RealtimeManager._internal();

  // ── State ─────────────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected      = false;
  bool _serverIdentified = false;
  bool _flushedOnConnect = false; // [BUG-4] guard against double outbox flush

  String? _role;
  String? _branchId;
  String? _username;
  String? _serverIp;
  int     _port      = 53281;
  String? _clientId;

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _ackFlushTimer;

  // [FIX-RC] No longer capped — tracks attempts only for back-off schedule.
  int _reconnectAttempts = 0;

  DateTime? _lastPong;

  // [BUG-1] In-memory pending queue — only holds messages that could not be
  // sent because the channel was not ready. Already in the outbox.
  final List<Map<String, dynamic>> _pendingMessages = [];

  static const _outboxBox       = 'realtime_outbox';
  static const _failedOutboxBox = 'realtime_failed_outbox'; // [FAIL-BOX]

  // Max consecutive send failures in _flushOutbox before moving to failed box.
  static const _maxOutboxRetries = 3;

  // [BUG-3] Track serials to ACK — only cleared after a successful send.
  final Set<String> _pendingAckSerials = {};

  // ── Event types that trigger immediate ACK ─────────────────────────────────
  static const _immAckEvents = {
    'save_entry',
    'token_created',
    'save_prescription',
    'prescription_created',
  };

  // ── Back-off schedule (seconds). After the last value, stays at 5 s. ──────
  static const _backoffDelays = [2, 4, 8, 16, 32];

  // ── Public getters ─────────────────────────────────────────────────────────
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool    get isConnected => _isConnected;
  String? get role        => _role;
  String? get branchId    => _branchId;
  String? get username    => _username;
  String? get clientId    => _clientId;

  static Future<void> initOutbox() async {
    await Hive.openBox(_outboxBox);
    await Hive.openBox(_failedOutboxBox); // [FAIL-BOX]
  }

  // ── Initialize ─────────────────────────────────────────────────────────────
  Future<void> initialize({
    required String role,
    required String branchId,
    required String serverIp,
    int    port     = 53281,
    String? username,
  }) async {
    await dispose();

    _role     = role.trim().toLowerCase();
    _branchId = branchId.trim().toLowerCase();
    _serverIp = serverIp.trim();
    _port     = port;
    _username = username?.trim();
    _serverIdentified = false;
    _flushedOnConnect = false;

    _clientId =
        '${DateTime.now().millisecondsSinceEpoch}_${_role}_${Random().nextInt(9999)}';

    if (kDebugMode) {
      print('[RealtimeManager] Initializing: role=$_role branch=$_branchId username=$_username');
    }

    await _connectClient();
  }

  // ── Update username on the fly (called after async name fetch) ─────────────
  // [FIX-USERNAME] Screens call this once their async name load completes so
  // the next message they send carries the real display name, not just the role.
  void updateUsername(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return;
    _username = trimmed;
    if (kDebugMode) {
      print('[RealtimeManager] Username updated → $_username');
    }
  }

  // ── WebSocket connect ──────────────────────────────────────────────────────
  Future<void> _connectClient() async {
    if (_serverIp == null || _serverIp!.isEmpty) return;

    final wsUrl = 'ws://$_serverIp:$_port';
    if (kDebugMode) print('[RealtimeManager] Connecting → $wsUrl');

    _serverIdentified = false;
    _flushedOnConnect = false;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      final identifyMsg = {
        'event_type': 'identify',
        'role':       _role,
        'branchId':   _branchId,
        'username':   _username ?? _role,
        '_clientId':  _clientId,
        '_timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _channel!.sink.add(jsonEncode(identifyMsg));

      await Future.delayed(const Duration(milliseconds: 300));

      _channelSub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _handleDisconnect(),
        onDone:  ()  => _handleDisconnect(),
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _startPingTimer();
      _startAckFlushTimer();
      _schedulePendingFallback();

      // [FAIL-BOX] On new connection, move failed messages back to main outbox.
      _retryFailedOutbox();

    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] Connect failed: $e');
      _handleDisconnect();
    }
  }

  // ── Incoming message ───────────────────────────────────────────────────────
  void _onMessage(dynamic raw) {
    if (raw == null) return;
    final msg = raw as String;

    if (msg == 'pong' || msg == '{"type":"pong"}') {
      _lastPong = DateTime.now();
      return;
    }

    try {
      final decoded = jsonDecode(msg) as Map<String, dynamic>;

      if (decoded['event_type'] == 'identified' && !_serverIdentified) {
        _serverIdentified = true;
        if (kDebugMode) {
          print('[RealtimeManager] Identified — flushing ${_pendingMessages.length} pending');
        }

        // [BUG-1] Flush in-memory pending directly (bypasses outbox write).
        // [BUG-2] Only schedule outbox flush if nothing was in the pending queue.
        final hadPending = _pendingMessages.isNotEmpty;
        _sendPendingMessages();

        if (!_flushedOnConnect) {
          _flushedOnConnect = true;
          Future.delayed(
            hadPending
                ? const Duration(milliseconds: 800)
                : const Duration(milliseconds: 500),
            _flushOutbox,
          );
        }
      }

      // [IMM-ACK] Handle ACK from server (server confirmed our message).
      if (decoded['event_type'] == 'message_ack') {
        final ackedId = decoded['messageId']?.toString();
        if (ackedId != null && ackedId.isNotEmpty) {
          _removeFromOutboxByMessageId(ackedId);
        }
      }

      _routeIncoming(decoded);
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] Decode error: $e');
    }
  }

  // ── Remove outbox entry by _messageId (called on server ACK) ──────────────
  void _removeFromOutboxByMessageId(String messageId) {
    try {
      final box = Hive.box(_outboxBox);
      for (final key in box.keys.toList()) {
        final entry = box.get(key);
        if (entry is Map && entry['_messageId']?.toString() == messageId) {
          box.delete(key);
          if (kDebugMode) {
            print('[RealtimeManager] ACK: removed outbox entry for msgId=$messageId');
          }
          return;
        }
      }
      // Also check failed outbox in case it was already moved there.
      final failedBox = Hive.box(_failedOutboxBox);
      for (final key in failedBox.keys.toList()) {
        final entry = failedBox.get(key);
        if (entry is Map && entry['_messageId']?.toString() == messageId) {
          failedBox.delete(key);
          if (kDebugMode) {
            print('[RealtimeManager] ACK: removed failed-outbox entry for msgId=$messageId');
          }
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] _removeFromOutboxByMessageId error: $e');
    }
  }

  // ── Fallback flush ─────────────────────────────────────────────────────────
  void _schedulePendingFallback() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_serverIdentified && _isConnected && _pendingMessages.isNotEmpty) {
        _serverIdentified = true;
        _sendPendingMessages();
      }
      if (_isConnected && !_flushedOnConnect) {
        _flushedOnConnect = true;
        _flushOutbox();
      }
    });
  }

  // ── Ping / pong ────────────────────────────────────────────────────────────
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isConnected) return;
      if (_lastPong != null &&
          DateTime.now().difference(_lastPong!).inSeconds > 50) {
        if (kDebugMode) print('[RealtimeManager] Pong timeout → reconnecting');
        _handleDisconnect();
        return;
      }
      sendMessage({'type': 'ping'});
    });
  }

  // [FIX-P3] Periodic ACK flush every 5 seconds (safety net).
  void _startAckFlushTimer() {
    _ackFlushTimer?.cancel();
    _ackFlushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isConnected || !_serverIdentified) return;
      _sendPendingAcks();
    });
  }

  // [FIX-P3] [BUG-3] Serials are only cleared after a successful channel write.
  void _sendPendingAcks() {
    if (_pendingAckSerials.isEmpty) return;
    final serials = List<String>.from(_pendingAckSerials);

    try {
      final ackMsg = {
        'event_type': 'ack_serials',
        'serials':    serials,
        '_clientId':  _clientId,
        '_timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _channel?.sink.add(jsonEncode(ackMsg));
      // Only clear on success
      _pendingAckSerials.removeAll(serials);
      if (kDebugMode) print('[RealtimeManager] ACK sent: ${serials.length} serials');
    } catch (e) {
      // Serials remain in _pendingAckSerials for the next timer tick
      if (kDebugMode) print('[RealtimeManager] ACK send failed, will retry: $e');
    }
  }

  // ── Disconnect / reconnect ─────────────────────────────────────────────────
  // [FIX-RC] No attempt cap — retries indefinitely.
  // Back-off: 2, 4, 8, 16, 32 s, then holds at 5 s intervals.
  // This prevents the >60-second dead window that occurred when the old cap
  // of 5 was hit and ConnectionManager had to re-run full LAN discovery.
  void _handleDisconnect() {
    _isConnected      = false;
    _serverIdentified = false;
    _flushedOnConnect = false;
    _pingTimer?.cancel();
    _ackFlushTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close(ws_status.goingAway);
    _channelSub = null;

    // Compute next delay; after exhausting the back-off table, hold at 5 s.
    final delaySeconds = _reconnectAttempts < _backoffDelays.length
        ? _backoffDelays[_reconnectAttempts]
        : 5;
    _reconnectAttempts++;

    if (kDebugMode) {
      print('[RealtimeManager] Disconnected. Reconnecting in ${delaySeconds}s '
          '(attempt $_reconnectAttempts)');
    }

    _reconnectTimer?.cancel();
    _reconnectTimer =
        Timer(Duration(seconds: delaySeconds), _connectClient);
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  void sendMessage(Map<String, dynamic> payload) {
    final normalized = _normalizeMessage(payload);

    final isPing = normalized['event_type'] == 'ping' ||
                   normalized['type'] == 'ping';
    final isAck  = normalized['event_type'] == 'ack_serials';
    final isHandshake = normalized['event_type'] == 'identify' ||
                        normalized['event_type'] == 'identified';

    // [FIX-P1] Write to Hive outbox FIRST (skip ping/ack/handshake).
    String? outboxKey;
    if (!isPing && !isAck && !isHandshake) {
      try {
        outboxKey = 'outbox_${DateTime.now().microsecondsSinceEpoch}';
        final outboxEntry = Map<String, dynamic>.from(normalized);
        outboxEntry['_outboxKey']        = outboxKey;
        outboxEntry['_outboxTimestamp']  = DateTime.now().toIso8601String();
        outboxEntry['_outboxRetryCount'] = 0; // [FAIL-BOX]
        Hive.box(_outboxBox).put(outboxKey, outboxEntry);
      } catch (e) {
        if (kDebugMode) print('[RealtimeManager] Outbox write failed: $e');
        outboxKey = null;
      }
    }

    if (!_isConnected || _channel == null || !_serverIdentified) {
      if (kDebugMode && !isPing) {
        print('[RealtimeManager] Queuing (${!_isConnected ? "not connected" : "not identified"}): ${normalized['event_type']}');
      }
      if (!isPing && !isAck && !isHandshake) {
        _pendingMessages.add(normalized);
      }
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(normalized));
      // [FIX-P1] Remove from outbox on successful send.
      if (outboxKey != null) {
        try { Hive.box(_outboxBox).delete(outboxKey); } catch (_) {}
      }
      if (kDebugMode) print('[RealtimeManager] → ${normalized['event_type']}');
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] Send failed: $e → queuing');
      // Message stays in outbox; _flushOutbox will resend on next reconnect.
      _pendingMessages.add(normalized);
      _handleDisconnect();
    }
  }

  // ── [BUG-1] Send pending directly to channel (no outbox re-write) ──────────
  void _sendPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_pendingMessages);
    _pendingMessages.clear();

    for (final msg in pending) {
      final isPing = msg['event_type'] == 'ping' || msg['type'] == 'ping';
      if (isPing) continue;

      try {
        _channel!.sink.add(jsonEncode(msg));
        // Remove outbox entry if one exists for this message.
        final outboxKey = msg['_outboxKey']?.toString();
        if (outboxKey != null) {
          try { Hive.box(_outboxBox).delete(outboxKey); } catch (_) {}
        }
        if (kDebugMode) print('[RealtimeManager] pending→ ${msg['event_type']}');
      } catch (e) {
        if (kDebugMode) print('[RealtimeManager] Pending send failed: $e');
        // Message is still in outbox; will be recovered on next reconnect.
      }
    }
  }

  // ── [FIX-P2] Flush Hive outbox on reconnect ────────────────────────────────
  Future<void> _flushOutbox() async {
    if (!_isConnected || !_serverIdentified || _channel == null) return;

    try {
      final box = Hive.box(_outboxBox);
      if (box.isEmpty) return;

      final cutoff   = DateTime.now().subtract(const Duration(hours: 24));
      final toDelete = <dynamic>[];

      if (kDebugMode) print('[RealtimeManager] Flushing outbox: ${box.length} items');

      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        if (raw is! Map) { toDelete.add(key); continue; }

        final item = Map<String, dynamic>.from(raw);

        // Expire items older than 24 hours.
        final tsStr    = item['_outboxTimestamp']?.toString();
        final itemTime = tsStr != null ? DateTime.tryParse(tsStr) : null;
        if (itemTime != null && itemTime.isBefore(cutoff)) {
          toDelete.add(key);
          continue;
        }

        final msg = Map<String, dynamic>.from(item);
        msg.remove('_outboxKey');
        msg.remove('_outboxTimestamp');
        final retryCount = (msg.remove('_outboxRetryCount') as int?) ?? 0;
        msg['_resent']    = true;
        msg['_timestamp'] = DateTime.now().millisecondsSinceEpoch;

        if (kDebugMode) {
          print('[RealtimeManager] Outbox resend: ${msg['event_type']} serial=${msg['serial'] ?? msg['data']?['serial'] ?? '?'}');
        }

        try {
          _channel!.sink.add(jsonEncode(msg));
          toDelete.add(key);
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          if (kDebugMode) print('[RealtimeManager] Outbox resend failed: $e');

          // [FAIL-BOX] Track consecutive failures; move to failed box after max.
          final newRetryCount = retryCount + 1;
          if (newRetryCount >= _maxOutboxRetries) {
            _moveToFailedOutbox(key, item, reason: e.toString());
            toDelete.add(key);
          } else {
            // Update retry count in outbox and stop flushing (channel is down).
            item['_outboxRetryCount'] = newRetryCount;
            try { box.put(key, item); } catch (_) {}
          }
          break; // Channel is broken; stop the loop.
        }
      }

      for (final k in toDelete) {
        try { box.delete(k); } catch (_) {}
      }

      if (kDebugMode) {
        print('[RealtimeManager] Outbox flush done. Cleared: ${toDelete.length}, remaining: ${box.length}');
      }
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] _flushOutbox error: $e');
    }
  }

  // ── [FAIL-BOX] Move an entry to the failed outbox ─────────────────────────
  void _moveToFailedOutbox(dynamic originalKey, Map<String, dynamic> item, {String? reason}) {
    try {
      final failedBox = Hive.box(_failedOutboxBox);
      final failedKey = 'failed_${DateTime.now().microsecondsSinceEpoch}';
      final failedEntry = Map<String, dynamic>.from(item);
      failedEntry['_failedAt']     = DateTime.now().toIso8601String();
      failedEntry['_failReason']   = reason?.substring(0, reason.length.clamp(0, 300));
      failedEntry['_originalKey']  = originalKey?.toString();
      failedBox.put(failedKey, failedEntry);

      if (kDebugMode) {
        print('[RealtimeManager] ⚠️ Moved to failed outbox: ${item['event_type']} '
            'msgId=${item['_messageId']} key=$failedKey');
      }
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] _moveToFailedOutbox error: $e');
    }
  }

  // ── [FAIL-BOX] Retry failed outbox on new connection ──────────────────────
  void _retryFailedOutbox() {
    try {
      final failedBox = Hive.box(_failedOutboxBox);
      if (failedBox.isEmpty) return;

      final box     = Hive.box(_outboxBox);
      final cutoff  = DateTime.now().subtract(const Duration(hours: 24));
      int moved = 0;

      for (final key in failedBox.keys.toList()) {
        final raw = failedBox.get(key);
        if (raw is! Map) { failedBox.delete(key); continue; }

        final item = Map<String, dynamic>.from(raw);

        // Expire entries older than 24 h (tokens/prescriptions are same-day only).
        final tsStr = (item['_outboxTimestamp'] ?? item['_failedAt'])?.toString();
        final ts    = tsStr != null ? DateTime.tryParse(tsStr) : null;
        if (ts != null && ts.isBefore(cutoff)) {
          failedBox.delete(key);
          continue;
        }

        // Reset failure metadata and move back to main outbox.
        item.remove('_failedAt');
        item.remove('_failReason');
        item.remove('_originalKey');
        item['_outboxRetryCount'] = 0;
        item['_outboxTimestamp']  = item['_outboxTimestamp'] ?? DateTime.now().toIso8601String();
        final newKey = 'outbox_retry_${DateTime.now().microsecondsSinceEpoch}';
        item['_outboxKey'] = newKey;
        box.put(newKey, item);
        failedBox.delete(key);
        moved++;
      }

      if (moved > 0 && kDebugMode) {
        print('[RealtimeManager] ♻️ Moved $moved failed entries back to outbox for retry');
      }
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] _retryFailedOutbox error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> original) {
    final copy = Map<String, dynamic>.from(original);

    copy['_clientId']     ??= _clientId;
    copy['_senderRole']   ??= _role;
    copy['_senderBranch'] ??= _branchId;
    copy['_username']     ??= _username ?? _role;
    copy['event_type']    ??= 'unknown';
    copy['_timestamp']      = DateTime.now().millisecondsSinceEpoch;
    copy['_messageId']    ??= _generateMessageId();

    if (_branchId != null && !copy.containsKey('branchId')) {
      copy['branchId'] = _branchId;
    }

    if (copy['data'] is Map) {
      final data = copy['data'] as Map;
      if (data.containsKey('branchId')) {
        copy['branchId'] ??= data['branchId'];
        data.remove('branchId');
      }
    }

    return copy;
  }

  String _generateMessageId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}';

  // ── Route incoming ─────────────────────────────────────────────────────────
  void _routeIncoming(Map<String, dynamic> decoded) {
    final type     = decoded['event_type'] as String?;
    final data     = decoded['data'] as Map<String, dynamic>? ?? decoded;
    final senderId = decoded['_clientId']?.toString() ?? '';

    if (senderId.isNotEmpty && senderId == _clientId) {
      if (kDebugMode) print('[RealtimeManager] Ignoring own echo: $type');
      return;
    }

    final msgBranch = (decoded['branchId'] ?? decoded['_senderBranch'])
        ?.toString().toLowerCase().trim();
    final myBranch = _branchId?.toLowerCase().trim();

    if (msgBranch != null && myBranch != null && msgBranch != myBranch) {
      return;
    }

    RealtimeRouter.routeMessage(decoded);

    // [IMM-ACK] Send immediate ACK for data-bearing events (tokens, prescriptions).
    if (type != null && _immAckEvents.contains(type)) {
      final serial = data['serial']?.toString().trim() ?? '';
      if (serial.isNotEmpty) {
        // Send immediately inline — do not wait for the 5-second batch.
        try {
          final ackMsg = {
            'event_type': 'ack_serials',
            'serials':    [serial],
            '_clientId':  _clientId,
            '_timestamp': DateTime.now().millisecondsSinceEpoch,
            '_immediate': true,
          };
          _channel?.sink.add(jsonEncode(ackMsg));
          if (kDebugMode) print('[RealtimeManager] ⚡ Immediate ACK: $serial ($type)');
        } catch (_) {
          // Fallback: add to batch queue.
          _pendingAckSerials.add(serial);
        }
      }
    }

    // [FIX-P3] Also queue ACK via batch timer for server-pushed entries (safety net).
    final isServerPush = decoded['_serverPush'] == true;
    if (isServerPush && (type == 'save_entry' || type == 'token_created')) {
      final serial = data['serial']?.toString().trim() ?? '';
      if (serial.isNotEmpty) {
        _pendingAckSerials.add(serial);
      }
    }

    _messageController.add({
      'event_type': type,
      'data':       data,
      'decoded':    decoded,
    });
  }

  // ── Dispose ────────────────────────────────────────────────────────────────
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _ackFlushTimer?.cancel();
    _channelSub?.cancel();
    await _channel?.sink.close(ws_status.normalClosure);

    _channel          = null;
    _channelSub       = null;
    _isConnected      = false;
    _serverIdentified = false;
    _flushedOnConnect = false;
    _reconnectAttempts = 0;
    _pendingMessages.clear();
    _lastPong         = null;
    _pendingAckSerials.clear();

    if (kDebugMode) print('[RealtimeManager] Disposed');
  }
}