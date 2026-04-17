// lib/realtime/server_sync_manager.dart
//
// FULLY UPDATED — Deduplication, User Attribution, Failed Box & Complete Downloads
//
// EXISTING (preserved):
//
//   [USER-TRACK] Full user identity captured per message.
//     - _connectedUsers map tracks {username, role, branchId, clientId}
//       for every identified socket.
//     - Every _interceptMessage() call resolves the performer:
//         primary:  _senderUsername from enriched message
//         fallback: stored connection identity from _connectedUsers
//         last:     'unknown_<clientId>'
//     - All save operations (_saveEntry, _savePrescription, _saveDispense,
//       _savePatient, _saveDispensaryRecord) embed:
//           performedBy, performedByRole, performedByClientId, performedAt
//     - _executeOp() writes these audit fields to Firestore.
//
//   [FAIL-BOX] Dead-letter box 'server_sync_failed'
//     - Operations that exhaust max attempts (5) are moved to the failed
//       box with failedAt, reason, originalKey metadata — instead of being
//       silently deleted.
//     - retryFailedBox() moves entries back to the main queue.
//     - Called automatically on every connectivity-restore event.
//
// NEW IN THIS REVISION:
//
//   [DOWNLOADS] All previously-stubbed download methods are now fully
//     implemented:
//       _downloadTodayTokens()     — fetches today's serials for all queue types
//       _downloadPatients()        — fetches all patients for the branch
//       _downloadInventory()       — fetches all inventory items
//       _downloadPrescriptions()   — fetches all CNIC-keyed prescriptions
//       _downloadTodayDispensary() — fetches today's dispensary records

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../services/local_storage_service.dart';
import 'lan_server.dart';
import 'realtime_events.dart';

// ── Lightweight user context record ───────────────────────────────────────────
class _UserContext {
  final String username;
  final String role;
  final String clientId;

  const _UserContext({
    required this.username,
    required this.role,
    required this.clientId,
  });

  Map<String, dynamic> toAuditMap() => {
    'performedBy':         username,
    'performedByRole':     role,
    'performedByClientId': clientId,
    'performedAt':         DateTime.now().toIso8601String(),
  };
}

class ServerSyncManager {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ServerSyncManager _i = ServerSyncManager._();
  factory ServerSyncManager() => _i;
  ServerSyncManager._();

  // ── State ──────────────────────────────────────────────────────────────────
  LanServer? _server;
  String? _branchId;
  bool _running   = false;
  bool _uploading = false;

  Function(Map<String, dynamic>)? _prevOnMessage;
  Function(String socketId, Map<String, dynamic>)? _prevOnConnected;
  Function(String socketId)? _prevOnDisconnected;

  Timer? _syncTimer;
  Timer? _downloadTimer;
  Timer? _catchUpTimer;
  StreamSubscription? _connSub;

  final Map<String, Map<String, dynamic>> _pendingPrescriptions = {};

  // Per-client serial tracking
  final Map<String, Set<String>> _clientSeenSerials = {};
  static const int _maxSeenPerClient = 500;

  // [USER-TRACK] Connected user identity by socketId
  final Map<String, _UserContext> _connectedUsers = {};

  static const _serverQueueBox  = 'server_sync_queue';
  static const _editRequestsBox = 'local_edit_requests';
  static const _failedBox       = 'server_sync_failed';

  final _db = FirebaseFirestore.instance;

  // ── Queue-type resolver ────────────────────────────────────────────────────
  static String resolveQueueType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'zakat';
    final s = raw.toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) return 'non-zakat';
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    if (s == 'zakat') return 'zakat';
    debugPrint('[SSM] ⚠️ Unknown queueType "$raw" — defaulting to zakat');
    return 'zakat';
  }

  static String _dateKeyFromSerial(String serial, String fallback) {
    if (serial.contains('-')) {
      final part = serial.split('-')[0];
      if (part.length == 6 && int.tryParse(part) != null) return part;
    }
    return fallback;
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  Future<void> start({
    required LanServer server,
    required String branchId,
  }) async {
    final cleanBranch = branchId.toLowerCase().trim();

    if (_running && _branchId == cleanBranch && _server == server) {
      debugPrint('[SSM] Already running for branch $cleanBranch — skipping');
      return;
    }

    stop();

    _server   = server;
    _branchId = cleanBranch;
    _running  = true;
    _clientSeenSerials.clear();
    _connectedUsers.clear();

    debugPrint('╔══════════════════════════════════════════════════════╗');
    debugPrint('║  ServerSyncManager  STARTED  branch: $_branchId');
    debugPrint('╚══════════════════════════════════════════════════════╝');

    _prevOnMessage = server.onMessageReceived;
    server.onMessageReceived = (msg) {
      _interceptMessage(msg);
      _prevOnMessage?.call(msg);
    };

    _prevOnConnected = server.onClientConnected;
    server.onClientConnected = (socketId, info) {
      _clientSeenSerials[socketId] = {};

      // [USER-TRACK] Store identity for this socket as fallback source.
      final username = (info['username'] as String?)?.trim() ?? '';
      final role     = (info['role']     as String?)?.trim() ?? 'unknown';
      final clientId = (info['clientId'] as String?)?.trim() ?? socketId;
      _connectedUsers[socketId] = _UserContext(
        username: username.isNotEmpty ? username : role,
        role:     role,
        clientId: clientId,
      );

      _prevOnConnected?.call(socketId, info);
      Future.delayed(const Duration(seconds: 1), () {
        if (_running) _pushCatchUpToSocket(socketId, info).ignore();
      });
    };

    _prevOnDisconnected = server.onClientDisconnected;
    server.onClientDisconnected = (socketId) {
      _clientSeenSerials.remove(socketId);
      _connectedUsers.remove(socketId);
      debugPrint('[SSM] Cleaned seen-set & user for disconnected: $socketId');
      _prevOnDisconnected?.call(socketId);
    };

    _downloadAllFromFirestore().ignore();
    _uploadQueue().ignore();

    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_running) _uploadQueue().ignore();
    });

    _downloadTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_running) _downloadTodayTokens().ignore();
    });

    _catchUpTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_running) _periodicCatchUpAll();
    });

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && _running) {
        retryFailedBox();
        _uploadQueue().ignore();
        _downloadAllFromFirestore().ignore();
      }
    });
  }

  void stop() {
    _running = false;
    _syncTimer?.cancel();
    _downloadTimer?.cancel();
    _catchUpTimer?.cancel();
    _connSub?.cancel();
    _clientSeenSerials.clear();
    _connectedUsers.clear();

    if (_server != null) {
      _server!.onMessageReceived    = _prevOnMessage;
      _server!.onClientConnected    = _prevOnConnected;
      _server!.onClientDisconnected = _prevOnDisconnected;
    }
    _prevOnMessage = _prevOnConnected = _prevOnDisconnected = null;
    _server = null;

    debugPrint('[SSM] Stopped');
  }

  static Future<void> initHive() async {
    await LocalStorageService.openBoxSafe(_serverQueueBox);
    await LocalStorageService.openBoxSafe(_editRequestsBox);
    await LocalStorageService.openBoxSafe(_failedBox);
  }


  // ── [FAIL-BOX] Move dead-letter entries back to main queue ─────────────────
  void retryFailedBox() {
    try {
      final failed = Hive.box(_failedBox);
      if (failed.isEmpty) return;

      final queue  = Hive.box(_serverQueueBox);
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      int moved    = 0;

      for (final key in failed.keys.toList()) {
        final raw = failed.get(key);
        if (raw is! Map) { failed.delete(key); continue; }

        final item = Map<String, dynamic>.from(raw);

        // Expire entries older than 24 h
        final tsStr = (item['createdAt'] ?? item['_failedAt'])?.toString();
        final ts    = tsStr != null ? DateTime.tryParse(tsStr) : null;
        if (ts != null && ts.isBefore(cutoff)) {
          failed.delete(key);
          debugPrint('[SSM] Expired failed entry: ${item['type']}');
          continue;
        }

        item.remove('_attempts');
        item.remove('_err');
        item.remove('_failedAt');
        item.remove('_originalKey');
        final newKey = 'ssync_retry_${DateTime.now().microsecondsSinceEpoch}';
        queue.put(newKey, LocalStorageService.sanitize(item));
        failed.delete(key);
        moved++;
      }

      if (moved > 0) {
        debugPrint('[SSM] ♻️ Moved $moved failed entries back to upload queue');
        _uploadQueue().ignore();
      }
    } catch (e) {
      debugPrint('[SSM] retryFailedBox error: $e');
    }
  }

  // ── Periodic Catch-up ─────────────────────────────────────────────────────
  void _periodicCatchUpAll() {
    if (_server == null || _branchId == null || !_running) return;
    final clients = _server!.getConnectedClients();
    if (clients.isEmpty) return;

    debugPrint('[SSM] Periodic catch-up: pushing to ${clients.length} client(s)');
    for (final client in clients) {
      final socketId = client['socketId']?.toString();
      if (socketId == null || socketId.isEmpty) continue;
      _pushCatchUpToSocket(socketId, Map<String, dynamic>.from(client)).ignore();
    }
  }

  // ── Message Interception ───────────────────────────────────────────────────
  void _interceptMessage(Map<String, dynamic> msg) {
    if (_branchId == null || !_running) return;

    final type = msg['event_type']?.toString() ?? '';
    final data = (msg['data'] is Map)
        ? Map<String, dynamic>.from(msg['data'] as Map)
        : Map<String, dynamic>.from(msg);

    for (final field in ['queueType', 'dateKey', 'serial', 'branchId']) {
      if (!data.containsKey(field) && msg.containsKey(field)) {
        data[field] = msg[field];
      }
    }

    if (type == 'ack_serials') {
      _handleClientAck(msg);
      return;
    }

    final user = _resolveUser(msg);
    debugPrint('[SSM] intercept: $type | serial=${data['serial']} | by=${user.username}');

    switch (type) {
      case 'save_entry':
      case 'token_created':
        _saveEntry(data, msg, user: user);
        _flushPendingPrescription(data['serial']?.toString().trim());
        break;

      case 'save_prescription':
      case 'prescription_created':
        _savePrescription(data, msg, user: user);
        break;

      case 'dispense_completed':
        _saveDispense(data, msg, user: user);
        break;

      case 'save_patient':
        _savePatient(data, msg, user: user);
        break;

      case 'save_dispensary_record':
        _saveDispensaryRecord(data, msg, user: user);
        break;

      case 'save_stock_item':
        final medData = data['data'] is Map ? Map<String, dynamic>.from(data['data']) : data;
        final medicineId = data['medicineId']?.toString() ?? medData['id']?.toString();
        final delta = data['_quantityDelta'];

        if (delta != null && medicineId != null) {
          final deltaVal = (delta is num)
              ? delta.toDouble()
              : double.tryParse(delta.toString()) ?? 0.0;

          if (deltaVal != 0) {
            debugPrint('[SSM] Intercepted stock addition for $medicineId delta=$deltaVal');
            // Update local Hive for immediate visual consistency on host
            LocalStorageService.updateLocalStockQuantity(medicineId, deltaVal);

            // Enqueue for Firestore
            _enqueue({
              'type': 'add_inventory_stock',
              'branchId': data['branchId'] ?? _branchId,
              'medicineId': medicineId,
              'quantity': deltaVal,
              'performedBy': data['performedBy'] ?? user.clientId,
              'performedByName': data['performedByName'] ?? user.username,
              'createdAt': DateTime.now().toIso8601String(),
            });
          }
        } else if (medicineId != null) {
          debugPrint('[SSM] Intercepted new medicine registration: $medicineId');
          // Update local Hive
          LocalStorageService.saveLocalInventoryItem(medData);

          // Enqueue for Firestore
          _enqueue({
            'type': 'register_medicine',
            'branchId': data['branchId'] ?? _branchId,
            'medicineId': medicineId,
            'data': medData,
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
        break;

      case RealtimeEvents.tokenExceptionRequest:
        _saveTokenExceptionRequest(data, msg, user: user);
        break;

      case RealtimeEvents.tokenExceptionApproved:
        _saveTokenExceptionApproval(data, msg, user: user);
        break;

      case RealtimeEvents.savePrescription:
        _handlePrescriptionRestriction(data, msg);
        break;
    }
  }

  // ── [USER-TRACK] Resolve user context from message ─────────────────────────
  _UserContext _resolveUser(Map<String, dynamic> msg) {
    final username = (msg['_senderUsername'] as String?)?.trim() ??
                     (msg['_username']       as String?)?.trim();
    final role     = (msg['_senderRole']   as String?)?.trim() ?? 'unknown';
    final clientId = (msg['_clientId']     as String?)?.trim() ?? '';
    final socketId = (msg['_socketId']     as String?)?.trim() ?? '';

    if (username != null && username.isNotEmpty) {
      return _UserContext(username: username, role: role, clientId: clientId);
    }

    if (socketId.isNotEmpty && _connectedUsers.containsKey(socketId)) {
      return _connectedUsers[socketId]!;
    }

    final fallbackUsername = role != 'unknown' ? role : 'unknown_$clientId';
    debugPrint('[SSM] ⚠️ Username not found for socket=$socketId, using: $fallbackUsername');
    return _UserContext(
      username: fallbackUsername,
      role:     role,
      clientId: clientId,
    );
  }

  void _handleClientAck(Map<String, dynamic> msg) {
    final socketId = (msg['_socketId'] ?? msg['_clientId'] ?? '').toString();
    final serials  = msg['serials'];
    if (socketId.isEmpty || serials is! List) return;

    _clientSeenSerials[socketId] ??= {};
    for (final s in serials) {
      final serial = s?.toString().trim() ?? '';
      if (serial.isNotEmpty) _clientSeenSerials[socketId]!.add(serial);
    }

    final seen = _clientSeenSerials[socketId]!;
    if (seen.length > _maxSeenPerClient) {
      final overflow = seen.length - _maxSeenPerClient;
      seen.removeAll(seen.take(overflow).toList());
    }
  }

  void _flushPendingPrescription(String? serial) {
    if (serial == null || serial.isEmpty) return;
    final pending = _pendingPrescriptions.remove(serial);
    if (pending != null) {
      _savePrescription(pending, pending);
    }
  }

  // ── Save Methods ───────────────────────────────────────────────────────────

  void _saveEntry(
    Map<String, dynamic> data,
    Map<String, dynamic> full, {
    _UserContext? user,
  }) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = data['serial']?.toString().trim();
    if (serial == null || serial.isEmpty) return;

    final dateKey   = data['dateKey']?.toString() ??
        _dateKeyFromSerial(serial, _todayKey());
    final queueType = resolveQueueType(
        (data['queueType'] ?? full['queueType'])?.toString());

    final entry = <String, dynamic>{
      'serial':      serial,
      'branchId':    branchId,
      'queueType':   queueType,
      'patientId':   data['patientId']   ?? '',
      'patientName': data['patientName'] ?? data['name'] ?? 'Unknown',
      'patientCnic': data['patientCnic'] ?? data['cnic'] ?? '',
      'createdAt':   data['createdAt']   ?? DateTime.now().toIso8601String(),
      'status':      data['status']      ?? 'waiting',
      'dateKey':     dateKey,
      ...?user?.toAuditMap(),
    };

    data.forEach((k, v) {
      if (!entry.containsKey(k) && v != null) entry[k] = v;
    });

    LocalStorageService.saveEntryLocal(branchId, serial, entry);
    _enqueue({
      'type':      'save_entry',
      'branchId':  branchId,
      'dateKey':   dateKey,
      'queueType': queueType,
      'serial':    serial,
      'data':      entry,
    });
  }

  void _savePrescription(
    Map<String, dynamic> data,
    Map<String, dynamic> full, {
    _UserContext? user,
  }) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = (data['serial'] ?? data['id'])?.toString().trim();
    if (serial == null || serial.isEmpty) return;

    final prescWithBranch = {
      ...data,
      'branchId': branchId,
      'serial':   serial,
      ...?user?.toAuditMap(),
    };

    LocalStorageService.saveLocalPrescription(prescWithBranch);
    LocalStorageService.saveLocalPrescription({...prescWithBranch, 'serial': serial});

    final entryKey = '$branchId-$serial';
    final box      = Hive.box(LocalStorageService.entriesBox);
    final existing = box.get(entryKey);

    if (existing != null) {
      final upd = Map<String, dynamic>.from(existing);
      upd['status']      = 'completed';
      upd['completedAt'] = data['completedAt'] ?? DateTime.now().toIso8601String();
      upd['prescription'] = prescWithBranch;
      if (user != null) upd.addAll(user.toAuditMap());
      box.put(entryKey, upd);
    } else {
      _pendingPrescriptions[serial] = data;
    }

    final cnic = _cleanCnic(
      data['patientCnic']?.toString() ??
          data['cnic']?.toString() ??
          'unknown_$serial',
    );

    final queueType = resolveQueueType(
        (existing?['queueType'] ?? data['queueType'])?.toString());
    final dateKey   = existing?['dateKey']?.toString() ??
        _dateKeyFromSerial(serial, _todayKey());

    _enqueue({
      'type':     'save_prescription',
      'branchId': branchId,
      'cnic':     cnic,
      'serial':   serial,
      'data':     prescWithBranch,
    });

    _enqueue({
      'type':      'update_serial_status',
      'branchId':  branchId,
      'serial':    serial,
      'queueType': queueType,
      'dateKey':   dateKey,
      'data': {
        'status':      'completed',
        'completedAt': data['completedAt'] ?? DateTime.now().toIso8601String(),
        ...?user?.toAuditMap(),
      },
    });
  }

  void _saveDispense(
    Map<String, dynamic> data,
    Map<String, dynamic> full, {
    _UserContext? user,
  }) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = data['serial']?.toString().trim();
    if (serial == null || serial.isEmpty) return;

    final now    = DateTime.now().toIso8601String();
    final update = {
      'dispenseStatus': 'dispensed',
      'status':         'completed',
      'dispensedAt':    data['dispensedAt'] ?? now,
      'dispensedBy':    data['dispensedBy'] ?? user?.username ?? '',
      'completedAt':    data['completedAt'] ?? now,
      ...?user?.toAuditMap(),
    };

    LocalStorageService.updateLocalEntryField(branchId, serial, update);
    debugPrint('[SSM] ✅ dispense saved: $branchId-$serial by ${user?.username}');

    final entryKey  = '$branchId-$serial';
    final box       = Hive.box(LocalStorageService.entriesBox);
    final existing  = box.get(entryKey);

    final rawQT     = (existing?['queueType'] ?? data['queueType'])?.toString();
    final queueType = resolveQueueType(rawQT);
    final dateKey   = existing?['dateKey']?.toString() ??
        _dateKeyFromSerial(serial, _todayKey());

    _enqueue({
      'type':      'update_serial_status',
      'branchId':  branchId,
      'serial':    serial,
      'queueType': queueType,
      'dateKey':   dateKey,
      'data':      update,
    });

  }

  void _maybeDeductInventoryFromRemote(
      String branchId, String serial, Map<String, dynamic> data) {
    if (data['_serverPush'] == true) return;
    _deductInventory(branchId, serial, data);
  }

  void _deductInventory(
      String branchId, String serial, Map<String, dynamic> data) {
    try {
      final medicines = data['medicines'] as List? ?? [];
      for (final med in medicines) {
        if (med is! Map) continue;
        final medMap     = Map<String, dynamic>.from(med);
        final medicineId =
            (medMap['medicineId'] ?? medMap['id'] ?? '').toString().trim();
        final qtyNum = (medMap['quantity'] ?? medMap['qty'] ?? 0) as num;

        if (medicineId.isEmpty || qtyNum <= 0) continue;

        _enqueue({
          'type':       'update_inventory',
          'branchId':   branchId,
          'medicineId': medicineId,
          'delta':      -qtyNum.toDouble(),
          'serial':     serial,
          'data': {
            'medicineId': medicineId,
            'delta':      -qtyNum.toDouble(),
            'serial':     serial,
          },
        });
      }
    } catch (e) {
      debugPrint('[SSM] _deductInventory error: $e');
    }
  }

  void _savePatient(
    Map<String, dynamic> data,
    Map<String, dynamic> full, {
    _UserContext? user,
  }) {
    final p = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'])
        : data;
    final patientData = {
      ...p,
      'branchId': _branchId,
      ...?user?.toAuditMap(),
    };
    LocalStorageService.saveLocalPatient(patientData);

    _enqueue({
      'type':      'save_patient',
      'branchId':  _branchId,
      'patientId': p['patientId'],
      'data':      patientData,
    });
  }

  void _saveDispensaryRecord(
    Map<String, dynamic> data,
    Map<String, dynamic> full, {
    _UserContext? user,
  }) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = data['serial']?.toString().trim();
    final dateKey  = data['dateKey']?.toString() ?? _todayKey();
    if (serial == null || serial.isEmpty) return;

    final record = {
      ...data,
      'branchId': branchId,
      'dateKey':  dateKey,
      ...?user?.toAuditMap(),
    };
    LocalStorageService.saveLocalDispensaryRecord(record);

    _enqueue({
      'type':     'save_dispensary_record',
      'branchId': branchId,
      'dateKey':  dateKey,
      'serial':   serial,
      'data':     record,
    });
  }

  // ── Catch-up Push ─────────────────────────────────────────────────────────
  Future<void> _pushCatchUpToSocket(
      String socketId, Map<String, dynamic> info) async {
    if (_server == null || _branchId == null || !_running) return;

    final role = (info['role'] ?? '').toString().toLowerCase();
    if (role == 'receptionist') return;

    final today   = _todayKey();
    final entries = LocalStorageService.getLocalEntries(_branchId!)
        .where((e) => (e['dateKey'] ?? '') == today)
        .toList();

    final clientSeen = _clientSeenSerials[socketId] ?? <String>{};
    final unseen = entries.where((e) {
      final serial = e['serial']?.toString().trim() ?? '';
      return serial.isNotEmpty && !clientSeen.contains(serial);
    }).toList();

    if (unseen.isEmpty) return;

    debugPrint('[SSM] Catch-up to $role ($socketId): ${unseen.length} unseen');

    for (final entry in unseen) {
      if (!_running || _server == null) break;

      final serial = entry['serial']?.toString() ?? '';
      if (serial.isEmpty) continue;

      _sendToSocket(socketId, {
        'event_type':  'save_entry',
        'branchId':    _branchId,
        'data':        entry,
        '_serverPush': true,
      });

      final presc = LocalStorageService.getLocalPrescription(serial) ??
          entry['prescription'] as Map<String, dynamic>?;
      if (presc != null && presc.isNotEmpty) {
        _sendToSocket(socketId, {
          'event_type':  'save_prescription',
          'branchId':    _branchId,
          'data':        presc,
          '_serverPush': true,
        });
      }

      if ((entry['dispenseStatus'] ?? '') == 'dispensed') {
        _sendToSocket(socketId, {
          'event_type':  'dispense_completed',
          'branchId':    _branchId,
          'data':        entry,
          '_serverPush': true,
        });
      }

      _clientSeenSerials[socketId] ??= {};
      _clientSeenSerials[socketId]!.add(serial);

      if (_clientSeenSerials[socketId]!.length > _maxSeenPerClient) {
        final overflow = _clientSeenSerials[socketId]!.length - _maxSeenPerClient;
        _clientSeenSerials[socketId]!.removeAll(
            _clientSeenSerials[socketId]!.take(overflow).toList());
      }

      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  void _sendToSocket(String socketId, Map<String, dynamic> payload) {
    try {
      _server?.sendToSocket(socketId, jsonEncode(payload));
    } catch (e) {
      debugPrint('[SSM] sendToSocket failed: $e');
    }
  }

  // ── Upload Queue ───────────────────────────────────────────────────────────
  void _enqueue(Map<String, dynamic> op) {
    try {
      final box = Hive.box(_serverQueueBox);
      final key = 'ssync_${DateTime.now().microsecondsSinceEpoch}';
      op['createdAt'] = DateTime.now().toIso8601String();
      box.put(key, LocalStorageService.sanitize(op));
    } catch (e) {
      debugPrint('[SSM] _enqueue failed: $e');
    }
  }

  Future<void> _uploadQueue() async {
    if (_uploading || !_running) return;

    final conn = await Connectivity().checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) return;

    _uploading = true;
    final box  = Hive.box(_serverQueueBox);
    final keys = box.keys.toList();

    for (final key in keys) {
      if (!_running) break;

      final raw = box.get(key);
      if (raw == null || raw is! Map) {
        box.delete(key);
        continue;
      }

      final op       = Map<String, dynamic>.from(raw);
      final attempts = (op['_attempts'] as int?) ?? 0;

      if (attempts >= 5) {
        _moveToFailedBox(key, op, reason: op['_err']?.toString() ?? 'max attempts');
        box.delete(key);
        continue;
      }

      try {
        await _executeOp(op);
        box.delete(key);
      } catch (e) {
        op['_attempts'] = attempts + 1;
        op['_err']      =
            e.toString().substring(0, e.toString().length.clamp(0, 200));
        final retryKey = 'ssync_retry_${DateTime.now().microsecondsSinceEpoch}';
        box.put(retryKey, op);
        box.delete(key);
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    _uploading = false;
  }

  // ── [FAIL-BOX] Move op to dead-letter box ─────────────────────────────────
  void _moveToFailedBox(dynamic originalKey, Map<String, dynamic> op,
      {String? reason}) {
    try {
      final failed    = Hive.box(_failedBox);
      final failedKey = 'failed_${DateTime.now().microsecondsSinceEpoch}';
      final entry     = Map<String, dynamic>.from(op);
      entry['_failedAt']    = DateTime.now().toIso8601String();
      entry['_failReason']  =
          reason?.substring(0, reason.length.clamp(0, 300));
      entry['_originalKey'] = originalKey?.toString();
      failed.put(failedKey, LocalStorageService.sanitize(entry));

      debugPrint('[SSM] ⚠️ Op moved to failed box: ${op['type']} '
          'serial=${op['serial']} key=$failedKey');
    } catch (e) {
      debugPrint('[SSM] _moveToFailedBox error: $e');
    }
  }

  // ── Execute Op ────────────────────────────────────────────────────────────
  Future<void> _executeOp(Map<String, dynamic> op) async {
    final type      = op['type']?.toString() ?? '';
    final branchId  = (op['branchId'] ?? _branchId!).toString();
    final data      = Map<String, dynamic>.from(op['data'] ?? {});
    final cleanData = LocalStorageService.sanitize(data);

    switch (type) {
      case 'save_entry':
        final dateKey = (op['dateKey'] ?? cleanData['dateKey'])?.toString();
        final serial  = op['serial']?.toString();
        if (dateKey == null || serial == null) return;

        final queueType = resolveQueueType(
            (op['queueType'] ?? cleanData['queueType'])?.toString());

        await _db
            .collection('branches').doc(branchId)
            .collection('serials').doc(dateKey)
            .collection(queueType).doc(serial)
            .set(cleanData, SetOptions(merge: true));

        final num = int.tryParse(serial.split('-').last);
        if (num != null) {
          await _db
              .collection('branches').doc(branchId)
              .collection('serials').doc(dateKey)
              .set({'lastSerialNumber': num}, SetOptions(merge: true));
        }
        break;

      case 'save_prescription':
        final serial = op['serial']?.toString();
        final cnic   = (op['cnic'] ??
            _cleanCnic(cleanData['patientCnic']?.toString() ?? '')).toString();
        if (serial == null) return;

        await _db
            .collection('branches').doc(branchId)
            .collection('prescriptions').doc(cnic)
            .collection('prescriptions').doc(serial)
            .set(cleanData, SetOptions(merge: true));

        _handlePrescriptionRestriction(cleanData, op);
        break;

      case 'update_serial_status':
        final serial = op['serial']?.toString();
        if (serial == null) return;

        String? rawQT   = (op['queueType'] ?? data['queueType'])?.toString();
        String? dateKey = (op['dateKey']   ?? data['dateKey'])?.toString();

        if (rawQT == null || dateKey == null) {
          final local = LocalStorageService.getLocalEntry(branchId, serial);
          rawQT   ??= local?['queueType']?.toString();
          dateKey ??= local?['dateKey']?.toString() ?? _todayKey();
        }

        final queueType = resolveQueueType(rawQT);

        await _db
            .collection('branches').doc(branchId)
            .collection('serials').doc(dateKey)
            .collection(queueType).doc(serial)
            .set(cleanData, SetOptions(merge: true));
        break;

      case 'save_dispensary_record':
        final dateKey = (op['dateKey'] ?? cleanData['dateKey'] ?? _todayKey()).toString();
        final serial  = op['serial']?.toString();
        if (serial == null) return;

        await _db
            .collection('branches').doc(branchId)
            .collection('dispensary').doc(dateKey)
            .collection(dateKey).doc(serial)
            .set(cleanData, SetOptions(merge: true));
        break;

      case 'save_patient':
        final patientId = op['patientId']?.toString();
        if (patientId == null) return;
        await _db
            .collection('branches').doc(branchId)
            .collection('patients').doc(patientId)
            .set(cleanData, SetOptions(merge: true));
        break;

      case 'update_inventory':
        final medicineId = op['medicineId']?.toString();
        if (medicineId == null || medicineId.isEmpty) return;
        final delta = (op['delta'] is num)
            ? (op['delta'] as num).toDouble()
            : double.tryParse(op['delta']?.toString() ?? '') ?? 0.0;
        if (delta == 0) return;

        await _db
            .collection('branches').doc(branchId)
            .collection('inventory').doc(medicineId)
            .update({'quantity': FieldValue.increment(delta)});
        break;

      case 'approve_token_exception':
      case 'save_token_exception_request':
        final requestId = op['requestId']?.toString() ?? cleanData['requestId']?.toString();
        if (requestId == null) return;
        await _db
            .collection('branches').doc(branchId)
            .collection('edit_requests').doc(requestId)
            .set(cleanData, SetOptions(merge: true));
        break;

      case 'add_inventory_stock':
        final medicineId = op['medicineId']?.toString();
        final qty = op['quantity'];
        if (medicineId == null) return;

        final qtyVal = (qty is num) ? qty.toDouble() : double.tryParse(qty?.toString() ?? '') ?? 0.0;
        if (qtyVal == 0) return;

        await _db
            .collection('branches').doc(branchId)
            .collection('inventory').doc(medicineId)
            .update({'quantity': FieldValue.increment(qtyVal)});

        // Log the action
        await _db
            .collection('branches').doc(branchId)
            .collection('inventory_log').add({
          'action': 'add_stock',
          'medicineId': medicineId,
          'quantityAdded': qtyVal,
          'performedBy': op['performedBy'] ?? '',
          'performedByName': op['performedByName'] ?? '',
          'timestamp': FieldValue.serverTimestamp(),
        });
        break;

      case 'register_medicine':
        final medData = Map<String, dynamic>.from(op['data'] ?? {});
        final medicineId = op['medicineId']?.toString() ?? medData['id']?.toString() ?? '';
        if (medicineId.isEmpty) return;

        // Clean local-only fields
        final fsData = Map<String, dynamic>.from(medData)
          ..remove('id')
          ..remove('syncStatus');

        await _db
            .collection('branches').doc(branchId)
            .collection('inventory').doc(medicineId)
            .set(fsData, SetOptions(merge: true));

        // Log the action
        await _db
            .collection('branches').doc(branchId)
            .collection('inventory_log').add({
          'action': 'medicine_registered_directly',
          'medicineName': fsData['name'] ?? '',
          'medicineType': fsData['type'] ?? '',
          'dose': fsData['dose'] ?? '',
          'expiryDate': fsData['expiryDate'] ?? '',
          'quantityAdded': fsData['quantity'] ?? 0,
          'price': fsData['price'] ?? '',
          'performedBy': fsData['createdBy'] ?? '',
          'performedByName': fsData['createdByName'] ?? '',
          'timestamp': FieldValue.serverTimestamp(),
          'docId': medicineId,
        });
        break;

      default:
        debugPrint('[SSM] Unknown op type: $type');
    }
  }

  // ── Downloads ──────────────────────────────────────────────────────────────

  Future<void> _downloadAllFromFirestore() async {
    if (_branchId == null || !_running) return;
    final conn = await Connectivity().checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) return;

    await Future.wait([
      _downloadPatients(),
      _downloadInventory(),
      _downloadPrescriptions(),
      _downloadTodayTokens(),
      _downloadTodayDispensary(),
    ]);
  }

  /// Fetches today's serial documents for all three queue types and saves
  /// them to the local entries box.
  Future<void> _downloadTodayTokens() async {
    if (_branchId == null || !_running) return;
    try {
      final today      = _todayKey();
      final queueTypes = ['zakat', 'non-zakat', 'gmwf'];

      for (final queueType in queueTypes) {
        final snap = await _db
            .collection('branches')
            .doc(_branchId)
            .collection('serials')
            .doc(today)
            .collection(queueType)
            .get();

        for (final doc in snap.docs) {
          final d = doc.data();
          d['serial']    = doc.id;
          d['queueType'] = queueType;
          d['dateKey']   = today;
          d['branchId']  = _branchId;
          LocalStorageService.saveEntryLocal(_branchId!, doc.id, d);
        }
      }
      debugPrint('[SSM] Downloaded today tokens for $_branchId ($today)');
    } catch (e) {
      debugPrint('[SSM] _downloadTodayTokens error: $e');
    }
  }

  /// Fetches all patient documents for the branch and saves them locally.
  Future<void> _downloadPatients() async {
    if (_branchId == null || !_running) return;
    try {
      final snap = await _db
          .collection('branches')
          .doc(_branchId)
          .collection('patients')
          .get();

      for (final doc in snap.docs) {
        final d = doc.data();
        d['patientId'] = doc.id;
        d['branchId']  = _branchId;
        await LocalStorageService.saveLocalPatient(d);
        // Mark synced so backfill never re-uploads patients from Firestore
        await Hive.box('app_flags').put('patient_synced_${doc.id}', true);
      }
      debugPrint('[SSM] Downloaded ${snap.docs.length} patients for $_branchId');
    } catch (e) {
      debugPrint('[SSM] _downloadPatients error: $e');
    }
  }

  /// Fetches all inventory documents for the branch and saves them locally.
  Future<void> _downloadInventory() async {
    if (_branchId == null || !_running) return;
    try {
      final snap = await _db
          .collection('branches')
          .doc(_branchId)
          .collection('inventory')
          .get();

      for (final doc in snap.docs) {
        final d = doc.data();
        d['medicineId'] = doc.id;
        d['branchId']   = _branchId;
        LocalStorageService.saveLocalInventoryItem(d);
      }
      debugPrint('[SSM] Downloaded ${snap.docs.length} inventory items for $_branchId');
    } catch (e) {
      debugPrint('[SSM] _downloadInventory error: $e');
    }
  }

  /// Fetches all CNIC-keyed prescription subcollections and saves them locally.
  Future<void> _downloadPrescriptions() async {
    if (_branchId == null || !_running) return;
    try {
      final cnicDocs = await _db
          .collection('branches')
          .doc(_branchId)
          .collection('prescriptions')
          .get();

      int total = 0;
      for (final cnicDoc in cnicDocs.docs) {
        final presSnap = await _db
            .collection('branches')
            .doc(_branchId)
            .collection('prescriptions')
            .doc(cnicDoc.id)
            .collection('prescriptions')
            .get();

        for (final presDoc in presSnap.docs) {
          final d = presDoc.data();
          d['id']          = presDoc.id;
          d['patientCnic'] = cnicDoc.id;
          d['branchId']    = _branchId;
          await LocalStorageService.saveLocalPrescription(d);
          total++;
        }
      }
      debugPrint('[SSM] Downloaded $total prescriptions for $_branchId');
    } catch (e) {
      debugPrint('[SSM] _downloadPrescriptions error: $e');
    }
  }

  /// Fetches today's dispensary records and saves them locally.
  Future<void> _downloadTodayDispensary() async {
    if (_branchId == null || !_running) return;
    try {
      final today = _todayKey();
      final snap  = await _db
          .collection('branches')
          .doc(_branchId)
          .collection('dispensary')
          .doc(today)
          .collection(today)
          .get();

      for (final doc in snap.docs) {
        final d = doc.data();
        d['serial']   = doc.id;
        d['dateKey']  = today;
        d['branchId'] = _branchId;
        LocalStorageService.saveLocalDispensaryRecord(d);
      }
      debugPrint('[SSM] Downloaded ${snap.docs.length} dispensary records for $_branchId ($today)');
    } catch (e) {
      debugPrint('[SSM] _downloadTodayDispensary error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _todayKey() => DateFormat('ddMMyy').format(DateTime.now());

  String? _field(
    Map<String, dynamic> data,
    Map<String, dynamic> full,
    String field,
  ) =>
      data[field]?.toString() ??
      full[field]?.toString() ??
      full['_senderBranch']?.toString();

  String _cleanCnic(String raw) =>
      raw.replaceAll(RegExp(r'[-\s]'), '').toLowerCase();

  void _saveTokenExceptionRequest(
    Map<String, dynamic> data,
    Map<String, dynamic> full, {
    _UserContext? user,
  }) {
    final branchId  = _field(data, full, 'branchId') ?? _branchId!;
    final requestId = data['requestId']?.toString() ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    
    final record = {
      ...data,
      'branchId': branchId,
      'status':   'pending',
      'requestedAt': DateTime.now().toIso8601String(),
      ...?user?.toAuditMap(),
    };

    _enqueue({
      'type':      'save_token_exception_request',
      'branchId':  branchId,
      'requestId': requestId,
      'data':      record,
    });
  }

  void _saveTokenExceptionApproval(
    Map<String, dynamic> data,
    Map<String, dynamic> full, {
    _UserContext? user,
  }) {
    final branchId  = _field(data, full, 'branchId') ?? _branchId!;
    final requestId = data['requestId']?.toString();
    final patientId = data['patientId']?.toString();
    if (requestId == null) return;

    final update = {
      'status':         'approved',
      'doctorReason':   data['reason'] ?? data['doctorReason'] ?? '',
      'approvedBy':     user?.username ?? 'Doctor',
      'approvedByName': user?.username ?? 'Doctor',
      'approvedAt':     DateTime.now().toIso8601String(),
      ...?user?.toAuditMap(),
    };

    // ── FIRESTORE FIX: Clear local restriction immediately on server device ──
    if (patientId != null) {
      LocalStorageService.clearMedicineRestriction(branchId, patientId).ignore();
    }

    _enqueue({
      'type':      'approve_token_exception',
      'branchId':  branchId,
      'requestId': requestId,
      'patientId': patientId, // CRITICAL: pass to SyncService
      'data':      update,
    });
  }

  void _handlePrescriptionRestriction(Map<String, dynamic> data, Map<String, dynamic> full) {
    final days = int.tryParse(data['daysOfMedicine']?.toString() ?? '1') ?? 1;
    if (days <= 1) return;

    final bId = _field(data, full, 'branchId') ?? _branchId;
    final pId = data['patientCnic']?.toString() ??
               data['cnic']?.toString() ??
               data['patientId']?.toString();

    if (bId != null && pId != null && pId.trim().isNotEmpty) {
      LocalStorageService.saveMedicineRestriction(
        branchId: bId,
        patientId: pId.trim(),
        daysCovered: days,
      );
      debugPrint('[SSM] 💊 Multi-day restriction applied: $pId ($days days)');
    }
  }
}
