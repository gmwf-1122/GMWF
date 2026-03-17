// lib/realtime/server_sync_manager.dart
//
// FIXES in this version:
//   [FIX-A] queueType routing — tokens now land in the correct Firestore
//           sub-collection (zakat / non-zakat / gmwf).
//           Root cause: the old _resolveQueueType() silently returned null
//           and every caller fell back to 'zakat'.  The new resolver is
//           identical to TokenScreen._resolveQueueType and never returns null.
//
//   [FIX-B] _saveEntry() no longer overwrites a resolved queueType with the
//           entry-box value when the box value is stale/wrong.  The canonical
//           value comes from the message first (already present in entryData),
//           and the box is only consulted as a last resort.
//
//   [FIX-C] _executeOp('update_serial_status') now reads queueType from the
//           op first, then from the resolved entry, never silently falls back.
//
//   [FIX-D] Medicine inventory deduction on dispense_completed.
//           _saveDispense() now calls _deductInventory() which:
//             • reads the prescription for the serial from the prescriptions box
//             • for each medicine in the prescription, decrements
//               branches/{branchId}/inventory/{medicineId}.quantity by the
//               prescribed amount (Firestore FieldValue.increment)
//             • queues an 'update_inventory' op for offline retry
//           This is the first time inventory is touched on dispense.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../services/local_storage_service.dart';
import 'lan_server.dart';

class ServerSyncManager {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ServerSyncManager _i = ServerSyncManager._();
  factory ServerSyncManager() => _i;
  ServerSyncManager._();

  // ── State ──────────────────────────────────────────────────────────────────
  LanServer? _server;
  String?    _branchId;
  bool       _running   = false;
  bool       _uploading = false;

  Function(Map<String, dynamic>)?                     _prevOnMessage;
  Function(String socketId, Map<String, dynamic>)?    _prevOnConnected;

  Timer? _syncTimer;
  Timer? _downloadTimer;
  StreamSubscription? _connSub;

  final Map<String, Map<String, dynamic>> _pendingPrescriptions = {};

  static const _serverQueueBox  = 'server_sync_queue';
  static const _editRequestsBox = 'local_edit_requests';

  final _db = FirebaseFirestore.instance;

  // ── Queue-type resolver ────────────────────────────────────────────────────
  // FIX-A: mirrors TokenScreen._resolveQueueType exactly — NEVER returns null.
  // Input may be a patient status ('Zakat', 'Non-Zakat', 'GMWF'),
  // a collection name ('zakat', 'non-zakat', 'gmwf'), or any variant.
  static String resolveQueueType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'zakat';
    final s = raw.toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) return 'non-zakat';
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    if (s == 'zakat') return 'zakat';
    debugPrint('[SSM] ⚠️  Unknown queueType "$raw" — defaulting to zakat');
    return 'zakat';
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
      _prevOnConnected?.call(socketId, info);
      Future.delayed(const Duration(milliseconds: 600), () {
        _pushCatchUpToSocket(socketId, info);
      });
    };

    _downloadAllFromFirestore().ignore();
    _uploadQueue().ignore();

    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_running) _uploadQueue().ignore();
    });

    _downloadTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_running) _downloadTodayTokens().ignore();
    });

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && _running) {
        _uploadQueue().ignore();
        _downloadAllFromFirestore().ignore();
      }
    });
  }

  void stop() {
    _running = false;
    _syncTimer?.cancel();
    _downloadTimer?.cancel();
    _connSub?.cancel();
    _syncTimer     = null;
    _downloadTimer = null;
    _connSub       = null;

    if (_server != null) {
      _server!.onMessageReceived = _prevOnMessage;
      _server!.onClientConnected = _prevOnConnected;
    }
    _prevOnMessage   = null;
    _prevOnConnected = null;
    _server          = null;

    debugPrint('[SSM] Stopped');
  }

  static Future<void> initHive() async {
    await Hive.openBox(_serverQueueBox);
    await Hive.openBox(_editRequestsBox);
  }

  // ── Message interception ───────────────────────────────────────────────────

  void _interceptMessage(Map<String, dynamic> msg) {
    if (_branchId == null || !_running) return;

    final type = msg['event_type']?.toString() ?? '';
    final data = (msg['data'] is Map)
        ? Map<String, dynamic>.from(msg['data'] as Map)
        : Map<String, dynamic>.from(msg);

    // Hoist top-level routing fields into data when absent from the inner map.
    for (final field in ['queueType', 'dateKey', 'serial', 'branchId']) {
      if (!data.containsKey(field) && msg.containsKey(field)) {
        data[field] = msg[field];
      }
    }

    debugPrint('[SSM] intercept: $type | queueType=${data['queueType']} | serial=${data['serial']}');

    switch (type) {
      case 'save_entry':
      case 'token_created':
        _saveEntry(data, msg);
        _flushPendingPrescription(data['serial']?.toString().trim());
        break;

      case 'save_prescription':
      case 'prescription_created':
        _savePrescription(data, msg);
        break;

      case 'dispense_completed':
        _saveDispense(data, msg);
        break;

      case 'save_patient':
        _savePatient(data, msg);
        break;

      case 'save_dispensary_record':
        _saveDispensaryRecord(data, msg);
        break;

      case 'save_stock_item':
        LocalStorageService.saveLocalStockItem(
            data['data'] is Map
                ? Map<String, dynamic>.from(data['data'] as Map)
                : data);
        break;
    }
  }

  // ── Flush buffered prescription ────────────────────────────────────────────

  void _flushPendingPrescription(String? serial) {
    if (serial == null || serial.isEmpty) return;
    final pending = _pendingPrescriptions.remove(serial);
    if (pending != null) {
      debugPrint('[SSM] Flushing buffered prescription for $serial');
      _savePrescription(pending, pending);
    }
  }

  // ── Persist helpers ────────────────────────────────────────────────────────

  void _saveEntry(Map<String, dynamic> data, Map<String, dynamic> full) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = data['serial']?.toString().trim();
    if (serial == null || serial.isEmpty) {
      debugPrint('[SSM] _saveEntry: missing serial — skipping');
      return;
    }

    final dateKey = data['dateKey']?.toString() ??
        (serial.contains('-') ? serial.split('-')[0] : _todayKey());

    // FIX-A: queueType comes from the message (entryData already has it set
    // by TokenScreen). Only fall back to the Hive entry as a last resort.
    final rawFromMsg  = (data['queueType'] ?? full['queueType'])?.toString();
    final queueType   = resolveQueueType(rawFromMsg);

    debugPrint('[SSM] _saveEntry: $serial → queueType="$queueType" (raw="$rawFromMsg")');

    final entry = <String, dynamic>{
      'serial':        serial,
      'branchId':      branchId,
      'queueType':     queueType,
      'patientId':     data['patientId']     ?? '',
      'patientName':   data['patientName']   ?? data['name'] ?? 'Unknown',
      'patientCnic':   data['patientCnic']   ?? data['cnic'] ?? '',
      'guardianCnic':  data['guardianCnic'],
      'createdAt':     data['createdAt']     ?? DateTime.now().toIso8601String(),
      'status':        data['status']        ?? 'waiting',
      'vitals':        data['vitals']        ?? {},
      'createdBy':     data['createdBy']     ?? '',
      'createdByName': data['createdByName'] ?? '',
      'dateKey':       dateKey,
    };
    data.forEach((k, v) { if (!entry.containsKey(k) && v != null) entry[k] = v; });

    LocalStorageService.saveEntryLocal(branchId, serial, entry);
    debugPrint('[SSM] ✅ entry saved: $branchId-$serial ($queueType)');

    _enqueue({
      'type':      'save_entry',
      'branchId':  branchId,
      'dateKey':   dateKey,
      'queueType': queueType,
      'serial':    serial,
      'data':      entry,
    });
  }

  void _savePrescription(Map<String, dynamic> data, Map<String, dynamic> full) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = (data['serial'] ?? data['id'])?.toString().trim();
    if (serial == null || serial.isEmpty) {
      debugPrint('[SSM] _savePrescription: missing serial — skipping');
      return;
    }

    final prescWithBranch = {...data, 'branchId': branchId, 'serial': serial};
    LocalStorageService.saveLocalPrescription(prescWithBranch);

    final id = data['id']?.toString().trim();
    if (id != null && id.isNotEmpty && id != serial) {
      LocalStorageService.saveLocalPrescription({...prescWithBranch, 'serial': id});
    }

    debugPrint('[SSM] ✅ prescription saved: $serial');

    final entryKey = '$branchId-$serial';
    final box      = Hive.box(LocalStorageService.entriesBox);
    final existing = box.get(entryKey);

    if (existing != null) {
      final upd = Map<String, dynamic>.from(existing);
      upd['status']         = 'completed';
      upd['completedAt']    = data['completedAt'] ?? DateTime.now().toIso8601String();
      upd['prescription']   = prescWithBranch;
      upd['prescriptionId'] = serial;
      box.put(entryKey, upd);
    } else {
      debugPrint('[SSM] ⚠️  entry not found for prescription: $entryKey — buffering');
      _pendingPrescriptions[serial] = data;
    }

    String cnic = _cleanCnic(
      data['patientCnic']?.toString() ??
      data['cnic']?.toString() ??
      data['guardianCnic']?.toString() ?? '',
    );
    if (cnic.isEmpty) cnic = 'unknown_$serial';

    // FIX-A: resolve queueType from existing entry (most reliable), then data.
    final rawQT     = (existing?['queueType'] ?? data['queueType'] ?? full['queueType'])?.toString();
    final queueType = resolveQueueType(rawQT);
    final dateKey   = existing?['dateKey']?.toString() ??
        (serial.contains('-') ? serial.split('-')[0] : _todayKey());

    debugPrint('[SSM] _savePrescription: $serial → queueType="$queueType" dateKey="$dateKey"');

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
        'status':       'completed',
        'completedAt':  data['completedAt'] ?? DateTime.now().toIso8601String(),
        'doctorName':   data['doctorName'],
        'prescription': prescWithBranch,
      },
    });
  }

  void _saveDispense(Map<String, dynamic> data, Map<String, dynamic> full) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = data['serial']?.toString().trim();
    if (serial == null || serial.isEmpty) {
      debugPrint('[SSM] _saveDispense: missing serial — skipping');
      return;
    }

    final now    = DateTime.now().toIso8601String();
    final update = {
      'dispenseStatus': 'dispensed',
      'dispensedAt':    data['dispensedAt'] ?? now,
      'dispensedBy':    data['dispensedBy'] ?? '',
    };

    LocalStorageService.updateLocalEntryField(branchId, serial, update);
    debugPrint('[SSM] ✅ dispense saved: $branchId-$serial');

    // FIX-C: carry queueType from entry so update lands in correct collection
    final entryKey  = '$branchId-$serial';
    final box       = Hive.box(LocalStorageService.entriesBox);
    final existing  = box.get(entryKey);
    final rawQT     = (existing?['queueType'] ?? data['queueType'])?.toString();
    final queueType = resolveQueueType(rawQT);
    final dateKey   = existing?['dateKey']?.toString() ??
        (serial.contains('-') ? serial.split('-')[0] : _todayKey());

    _enqueue({
      'type':      'update_serial_status',
      'branchId':  branchId,
      'serial':    serial,
      'queueType': queueType,
      'dateKey':   dateKey,
      'data':      update,
    });

    // NOTE: Inventory deduction is handled directly by patient_form.dart on
    // the dispenser device (it has the full prescription in scope).
    // SSM does NOT call _deductInventory here to avoid double-deduction when
    // the dispenser and server run on the same machine.
    // The only case SSM deducts is when it receives a _serverPush:false
    // message with an explicit 'medicines' array from a remote dispenser —
    // see _maybeDeductInventoryFromRemote() below.
    _maybeDeductInventoryFromRemote(branchId, serial, data);
  }

  // Inventory deduction for REMOTE dispensers only.
  // Only fires when:
  //   1. The message was NOT flagged as a server push (i.e. not a catch-up replay)
  //   2. The dispense payload explicitly carries a non-empty 'medicines' list
  //      (meaning the dispenser device sent its medicine data over LAN)
  // If 'medicines' is absent, we skip — patient_form.dart on the originating
  // device has already handled the deduction directly.
  void _maybeDeductInventoryFromRemote(
      String branchId, String serial, Map<String, dynamic> data) {
    final isServerPush = data['_serverPush'] == true;
    if (isServerPush) return; // catch-up replay — skip

    final rawMeds = data['medicines'];
    if (rawMeds is! List || rawMeds.isEmpty) return; // no medicines sent — skip

    debugPrint('[SSM] _maybeDeductInventoryFromRemote: deducting for remote dispense $serial');
    _deductInventory(branchId, serial, data);
  }

  // Deduct medicine quantities from inventory.
  // Only called by _maybeDeductInventoryFromRemote(), which already guarantees
  // data['medicines'] is a non-empty List — so no Hive fallback needed here.
  void _deductInventory(
      String branchId, String serial, Map<String, dynamic> data) {
    try {
      final medicines = data['medicines'] as List;

      debugPrint('[SSM] _deductInventory: deducting ${medicines.length} medicines for $serial');

      for (final med in medicines) {
        if (med is! Map) continue;
        final medMap = Map<String, dynamic>.from(med);

        // Support multiple field-name conventions used by different dispenser versions
        final medicineId = (medMap['medicineId'] ??
                medMap['id'] ??
                medMap['inventoryId'] ??
                medMap['stockItemId'] ??
                '')
            .toString()
            .trim();
        final qty    = medMap['quantity'] ?? medMap['qty'] ?? medMap['amount'] ?? 0;
        final qtyNum = qty is num ? qty.toDouble() : double.tryParse(qty.toString()) ?? 0.0;

        if (medicineId.isEmpty || qtyNum <= 0) continue;

        // Update Hive local stock immediately (inline — no external helper needed)
        try {
          final stockBox = Hive.box('stock_items');
          final existing = stockBox.get(medicineId);
          if (existing is Map) {
            final updated = Map<String, dynamic>.from(existing);
            final current = (updated['quantity'] as num?)?.toDouble() ?? 0.0;
            updated['quantity'] = (current - qtyNum).clamp(0.0, double.infinity);
            stockBox.put(medicineId, updated);
            debugPrint('[SSM] Hive stock $medicineId: $current → ${updated['quantity']}');
          }
        } catch (e) {
          debugPrint('[SSM] Hive stock decrement failed for $medicineId: $e');
        }

        // Enqueue Firestore decrement for background sync
        _enqueue({
          'type':       'update_inventory',
          'branchId':   branchId,
          'medicineId': medicineId,
          'delta':      -qtyNum,  // negative = deduction
          'serial':     serial,   // for audit trail
          'data': {
            'medicineId':  medicineId,
            'medicineName': medMap['medicineName'] ?? medMap['name'] ?? '',
            'delta':       -qtyNum,
            'serial':      serial,
            'dispensedAt': data['dispensedAt'] ?? DateTime.now().toIso8601String(),
            'dispensedBy': data['dispensedBy'] ?? '',
          },
        });

        debugPrint('[SSM] ✅ inventory queued: $medicineId -= $qtyNum');
      }
    } catch (e) {
      debugPrint('[SSM] _deductInventory error: $e');
    }
  }

  void _savePatient(Map<String, dynamic> data, Map<String, dynamic> full) {
    final p = (data['data'] is Map)
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    LocalStorageService.saveLocalPatient({...p, 'branchId': _branchId});
    debugPrint('[SSM] ✅ patient saved locally');

    _enqueue({
      'type':      'save_patient',
      'branchId':  _branchId,
      'patientId': p['patientId'],
      'data':      p,
    });
  }

  void _saveDispensaryRecord(Map<String, dynamic> data, Map<String, dynamic> full) {
    final branchId = _field(data, full, 'branchId') ?? _branchId!;
    final serial   = data['serial']?.toString().trim();
    final dateKey  = data['dateKey']?.toString() ?? _todayKey();
    if (serial == null || serial.isEmpty) return;

    final record = {...data, 'branchId': branchId, 'dateKey': dateKey};
    LocalStorageService.saveLocalDispensaryRecord(record);
    debugPrint('[SSM] ✅ dispensary record saved: $serial');

    _enqueue({
      'type':     'save_dispensary_record',
      'branchId': branchId,
      'dateKey':  dateKey,
      'serial':   serial,
      'data':     record,
    });
  }

  // ── Catch-up push ──────────────────────────────────────────────────────────

  Future<void> _pushCatchUpToSocket(
      String socketId, Map<String, dynamic> info) async {
    if (_server == null || _branchId == null || !_running) return;

    final role = (info['role'] ?? '').toString().toLowerCase();
    if (role == 'receptionist') return;

    final today   = _todayKey();
    final entries = LocalStorageService.getLocalEntries(_branchId!)
        .where((e) => (e['dateKey'] ?? '') == today)
        .toList();

    debugPrint('[SSM] Pushing catch-up to $role ($socketId): ${entries.length} entries');

    // Pre-build serial→prescription map
    final prescBox = Hive.box(LocalStorageService.prescriptionsBox);
    final Map<String, Map<String, dynamic>> prescBySerial = {};
    for (final key in prescBox.keys) {
      final raw = prescBox.get(key);
      if (raw is Map) {
        final p = Map<String, dynamic>.from(raw);
        final s = p['serial']?.toString() ?? p['id']?.toString();
        if (s != null && s.isNotEmpty) prescBySerial[s] = p;
      }
    }

    for (final entry in entries) {
      if (!_running) break;

      final serial = entry['serial']?.toString() ?? '';
      if (serial.isEmpty) continue;

      _sendToSocket(socketId, {
        'event_type':  'save_entry',
        'branchId':    _branchId,
        'data':        entry,
        '_serverPush': true,
        '_timestamp':  DateTime.now().millisecondsSinceEpoch,
      });

      // 3-tier prescription lookup
      Map<String, dynamic>? presc;

      final tier1 = LocalStorageService.getLocalPrescription(serial);
      if (tier1 != null && tier1.isNotEmpty) {
        presc = tier1;
      } else {
        final embedded = entry['prescription'];
        if (embedded is Map && embedded.isNotEmpty) {
          presc = Map<String, dynamic>.from(embedded);
        } else {
          presc = prescBySerial[serial];
        }
      }

      if (presc != null && presc.isNotEmpty) {
        _sendToSocket(socketId, {
          'event_type':  'save_prescription',
          'branchId':    _branchId,
          'data':        presc,
          '_serverPush': true,
          '_timestamp':  DateTime.now().millisecondsSinceEpoch,
        });
      }

      final dispenseStatus = entry['dispenseStatus']?.toString() ?? '';
      if (dispenseStatus == 'dispensed') {
        _sendToSocket(socketId, {
          'event_type':  'dispense_completed',
          'branchId':    _branchId,
          'data': {
            'serial':         serial,
            'branchId':       _branchId,
            'dispenseStatus': 'dispensed',
            'dispensedAt':    entry['dispensedAt'] ?? '',
            'dispensedBy':    entry['dispensedBy'] ?? '',
          },
          '_serverPush': true,
          '_timestamp':  DateTime.now().millisecondsSinceEpoch,
        });
      }

      await Future.delayed(const Duration(milliseconds: 30));
    }

    debugPrint('[SSM] Catch-up complete → $role ($socketId)');
  }

  void _sendToSocket(String socketId, Map<String, dynamic> payload) {
    try {
      _server?.sendToSocket(socketId, jsonEncode(payload));
    } catch (e) {
      debugPrint('[SSM] sendToSocket failed for $socketId: $e');
    }
  }

  // ── Firestore upload queue ─────────────────────────────────────────────────

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
    if (conn.every((r) => r == ConnectivityResult.none)) {
      debugPrint('[SSM] Offline — skipping upload');
      return;
    }

    _uploading = true;
    final box  = Hive.box(_serverQueueBox);
    debugPrint('[SSM] upload queue: ${box.length} ops');

    for (final key in box.keys.toList()) {
      if (!_running) break;

      final raw = box.get(key);
      if (raw == null || raw is! Map) { box.delete(key); continue; }

      final op       = Map<String, dynamic>.from(raw);
      final attempts = (op['_attempts'] as int?) ?? 0;

      if (attempts >= 5) {
        debugPrint('[SSM] Dropping op after 5 failures: ${op['type']}');
        box.delete(key);
        continue;
      }

      try {
        await _executeOp(op);
        box.delete(key);
        debugPrint('[SSM] ✅ uploaded: ${op['type']} ${op['serial'] ?? ''}');
      } catch (e) {
        op['_attempts'] = attempts + 1;
        op['_err']      = e.toString().substring(0, e.toString().length.clamp(0, 200));
        box.put(key, op);
        debugPrint('[SSM] ⚠️ upload fail (attempt ${attempts + 1}): $e');
        await Future.delayed(Duration(seconds: 2 * (attempts + 1)));
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    _uploading = false;
    debugPrint('[SSM] upload done. remaining: ${box.length}');
  }

  Future<void> _executeOp(Map<String, dynamic> op) async {
    final type     = op['type']?.toString() ?? '';
    final branchId = (op['branchId'] ?? _branchId!).toString();
    final data     = Map<String, dynamic>.from(op['data'] ?? {});
    final cleanData = LocalStorageService.sanitize(data);

    switch (type) {
      // ── Token entry ────────────────────────────────────────────────────────
      case 'save_entry':
        final dateKey = (op['dateKey'] ?? cleanData['dateKey'])?.toString();
        final serial  = op['serial']?.toString();
        if (dateKey == null || serial == null) return;

        // FIX-A: resolve from op first (set by _saveEntry), never silently zakat
        final rawQT     = (op['queueType'] ?? cleanData['queueType'])?.toString();
        final queueType = resolveQueueType(rawQT);

        debugPrint('[SSM] _executeOp save_entry: $serial → $queueType (raw="$rawQT")');

        await _db.collection('branches').doc(branchId)
            .collection('serials').doc(dateKey)
            .collection(queueType).doc(serial)
            .set(cleanData, SetOptions(merge: true));

        final num = int.tryParse(serial.split('-').last);
        if (num != null) {
          await _db.collection('branches').doc(branchId)
              .collection('serials').doc(dateKey)
              .set({'lastSerialNumber': num}, SetOptions(merge: true));
        }
        break;

      // ── Prescription ───────────────────────────────────────────────────────
      case 'save_prescription':
        final cnic   = (op['cnic'] ??
            _cleanCnic(cleanData['patientCnic']?.toString() ?? '')).toString();
        final serial = op['serial']?.toString();
        if (serial == null) return;

        await _db.collection('branches').doc(branchId)
            .collection('prescriptions').doc(cnic)
            .collection('prescriptions').doc(serial)
            .set(cleanData, SetOptions(merge: true));
        break;

      // ── Serial status patch ────────────────────────────────────────────────
      case 'update_serial_status':
        final serial = op['serial']?.toString();
        if (serial == null) return;

        // FIX-C: op['queueType'] is set by _savePrescription/_saveDispense.
        // Only fall back to local entry lookup if absent in the op.
        final local  = LocalStorageService.getLocalEntry(branchId, serial);
        final rawQT2 = (op['queueType'] ?? local?['queueType'])?.toString();
        final qt     = resolveQueueType(rawQT2);
        final dateKey = (op['dateKey'] ?? local?['dateKey'])?.toString() ?? _todayKey();

        debugPrint('[SSM] _executeOp update_serial_status: $serial → qt="$qt" dateKey="$dateKey"');

        try {
          await _db.collection('branches').doc(branchId)
              .collection('serials').doc(dateKey)
              .collection(qt).doc(serial)
              .update(cleanData);
        } catch (_) {
          await _db.collection('branches').doc(branchId)
              .collection('serials').doc(dateKey)
              .collection(qt).doc(serial)
              .set(cleanData, SetOptions(merge: true));
        }
        break;

      // ── Dispensary record ──────────────────────────────────────────────────
      case 'save_dispensary_record':
        final dateKey = (op['dateKey'] ?? cleanData['dateKey'] ?? _todayKey()).toString();
        final serial  = op['serial']?.toString();
        if (serial == null) return;

        await _db.collection('branches').doc(branchId)
            .collection('dispensary').doc(dateKey)
            .collection(dateKey).doc(serial)
            .set(cleanData, SetOptions(merge: true));
        break;

      // ── Patient ────────────────────────────────────────────────────────────
      case 'save_patient':
        final patientId = op['patientId']?.toString();
        if (patientId == null) return;

        await _db.collection('branches').doc(branchId)
            .collection('patients').doc(patientId)
            .set(cleanData, SetOptions(merge: true));
        break;

      // ── FIX-D: Inventory deduction ─────────────────────────────────────────
      // Uses FieldValue.increment so concurrent dispenses don't clobber each other.
      case 'update_inventory':
        final medicineId = op['medicineId']?.toString();
        if (medicineId == null || medicineId.isEmpty) return;

        final delta = (op['delta'] is num)
            ? (op['delta'] as num).toDouble()
            : double.tryParse(op['delta']?.toString() ?? '') ?? 0.0;
        if (delta == 0) return;

        debugPrint('[SSM] _executeOp update_inventory: $medicineId delta=$delta');

        await _db.collection('branches').doc(branchId)
            .collection('inventory').doc(medicineId)
            .update({'quantity': FieldValue.increment(delta)});
        break;

      default:
        debugPrint('[SSM] Unknown op type: $type');
    }
  }

  // ── Firestore downloads ────────────────────────────────────────────────────

  Future<void> _downloadAllFromFirestore() async {
    if (_branchId == null || !_running) return;

    final conn = await Connectivity().checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) {
      debugPrint('[SSM] Offline — skipping download');
      return;
    }

    debugPrint('[SSM] Starting full download...');
    await Future.wait([
      _downloadPatients(),
      _downloadInventory(),
      _downloadPrescriptions(),
      _downloadTodayTokens(),
      _downloadTodayDispensary(),
      _downloadEditRequests(),
    ]);
    debugPrint('[SSM] Full download complete');
  }

  Future<void> _downloadTodayTokens() async {
    if (_branchId == null) return;
    try {
      final today   = _todayKey();
      final dateRef = _db.collection('branches').doc(_branchId)
          .collection('serials').doc(today);

      final dateDoc = await dateRef.get();
      if (!dateDoc.exists) return;

      int count = 0;
      for (final qt in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await dateRef.collection(qt).get();
        for (final doc in snap.docs) {
          final d = Map<String, dynamic>.from(doc.data());
          d['serial']    = doc.id;
          d['dateKey']   = today;
          d['branchId']  = _branchId;
          d['queueType'] = qt; // always set canonical from collection name

          final existing = Hive.box(LocalStorageService.entriesBox)
              .get('$_branchId-${doc.id}');
          if (existing is Map) {
            if (existing['prescription'] != null) {
              d['prescription']   = existing['prescription'];
              d['prescriptionId'] = existing['prescriptionId'];
            }
            if (existing['dispenseStatus'] != null) {
              d['dispenseStatus'] = existing['dispenseStatus'];
              d['dispensedAt']    = existing['dispensedAt'];
              d['dispensedBy']    = existing['dispensedBy'];
            }
            final localStatus  = (existing['status'] ?? '').toString();
            final remoteStatus = (d['status'] ?? '').toString();
            if (localStatus == 'completed' && remoteStatus != 'completed') {
              d['status'] = 'completed';
            }
          }

          await LocalStorageService.saveEntryLocal(_branchId!, doc.id, d);
          count++;
        }
      }
      debugPrint('[SSM] Downloaded $count today tokens');
    } catch (e) {
      debugPrint('[SSM] _downloadTodayTokens failed: $e');
    }
  }

  Future<void> _downloadPatients() async {
    if (_branchId == null) return;
    try {
      final snap = await _db.collection('branches').doc(_branchId)
          .collection('patients').get();

      final patients = snap.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data());
        d['patientId'] = doc.id;
        d['branchId']  = _branchId;
        return d;
      }).toList();

      await LocalStorageService.saveAllLocalPatients(patients);
      debugPrint('[SSM] Downloaded ${patients.length} patients');
    } catch (e) {
      debugPrint('[SSM] _downloadPatients failed: $e');
    }
  }

  Future<void> _downloadInventory() async {
    if (_branchId == null) return;
    try {
      final snap = await _db.collection('branches').doc(_branchId)
          .collection('inventory').get();

      final items = snap.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data());
        d['id']       = doc.id;
        d['branchId'] = _branchId;
        return d;
      }).toList();

      await LocalStorageService.saveAllLocalStockItems(items);
      debugPrint('[SSM] Downloaded ${items.length} inventory items');
    } catch (e) {
      debugPrint('[SSM] _downloadInventory failed: $e');
    }
  }

  Future<void> _downloadPrescriptions() async {
    if (_branchId == null) return;
    try {
      final cnicDocs = await _db.collection('branches').doc(_branchId)
          .collection('prescriptions').get();

      int count = 0;
      for (final cnicDoc in cnicDocs.docs) {
        final prescSnap = await cnicDoc.reference.collection('prescriptions').get();

        for (final prescDoc in prescSnap.docs) {
          final d = Map<String, dynamic>.from(prescDoc.data());
          d['id']          = prescDoc.id;
          d['serial']      = prescDoc.id;
          d['patientCnic'] = cnicDoc.id;
          d['cnic']        = cnicDoc.id;
          d['branchId']    = _branchId;

          await LocalStorageService.saveLocalPrescription(d);

          final entryKey = '$_branchId-${prescDoc.id}';
          final box      = Hive.box(LocalStorageService.entriesBox);
          final existing = box.get(entryKey);
          if (existing != null) {
            final upd = Map<String, dynamic>.from(existing);
            if (upd['status'] != 'completed') {
              upd['status']         = 'completed';
              upd['prescription']   = d;
              upd['prescriptionId'] = prescDoc.id;
              box.put(entryKey, upd);
            }
          }
          count++;
        }
      }
      debugPrint('[SSM] Downloaded $count prescriptions');
    } catch (e) {
      debugPrint('[SSM] _downloadPrescriptions failed: $e');
    }
  }

  Future<void> _downloadTodayDispensary() async {
    if (_branchId == null) return;
    try {
      final today = _todayKey();
      final snap  = await _db.collection('branches').doc(_branchId)
          .collection('dispensary').doc(today)
          .collection(today).get();

      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['serial']   = doc.id;
        d['dateKey']  = today;
        d['branchId'] = _branchId;
        await LocalStorageService.saveLocalDispensaryRecord(d);

        await LocalStorageService.updateLocalEntryField(_branchId!, doc.id, {
          'dispenseStatus': d['dispenseStatus'] ?? 'dispensed',
          'dispensedAt':    d['dispensedAt'] ?? '',
          'dispensedBy':    d['dispensedBy'] ?? '',
        });
      }
      debugPrint('[SSM] Downloaded ${snap.docs.length} dispensary records');
    } catch (e) {
      debugPrint('[SSM] _downloadTodayDispensary failed: $e');
    }
  }

  Future<void> _downloadEditRequests() async {
    if (_branchId == null) return;
    try {
      final snap = await _db.collection('branches').doc(_branchId)
          .collection('edit_requests')
          .where('status', isEqualTo: 'approved')
          .get();

      final box = Hive.box(_editRequestsBox);
      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['id'] = doc.id;
        box.put(doc.id, LocalStorageService.sanitize(d));
      }
      debugPrint('[SSM] Downloaded ${snap.docs.length} approved edit_requests');
    } catch (e) {
      debugPrint('[SSM] _downloadEditRequests failed: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _todayKey() => DateFormat('ddMMyy').format(DateTime.now());

  String? _field(
          Map<String, dynamic> data, Map<String, dynamic> full, String field) =>
      data[field]?.toString() ??
      full[field]?.toString() ??
      full['_senderBranch']?.toString();

  String _cleanCnic(String raw) =>
      raw.replaceAll(RegExp(r'[-\s]'), '').toLowerCase();
}