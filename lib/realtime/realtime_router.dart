// lib/realtime/realtime_router.dart
//
// FIXES IN THIS VERSION:
//
// [P2] Non-server devices now enqueue directly to SyncService on every LAN
//      message receipt. _handleSaveEntry, _handleSavePrescription, and
//      _handleDispenseCompleted each call LocalStorageService.enqueueSync()
//      so that any device with internet connectivity uploads to Firestore
//      independently — without relying on the LAN server to relay.
//      Messages flagged with _serverPush:true are excluded to prevent the
//      server device from double-enqueuing its own catch-up pushes.
//
// [P3] _processedMessageIds is now persisted to a Hive box ('realtime_dedup_ids')
//      with a 24-hour TTL so deduplication survives app restarts.
//      Keys are stored as "<timestampMs>_<messageId>" enabling O(1) TTL
//      pruning by prefix comparison without scanning values.
//      Call RealtimeRouter.init() at app startup alongside other Hive opens.

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/local_storage_service.dart';
import 'realtime_events.dart';
import 'realtime_manager.dart';

class RealtimeRouter {
  // ── [P3] Hive-backed dedup store ──────────────────────────────────────────
  static const _dedupBox = 'realtime_dedup_ids';

  /// Must be called once at app startup alongside other Hive.openBox() calls.
  static Future<void> init() async {
    await Hive.openBox<String>(_dedupBox);
    await RealtimeManager.initOutbox();
    _pruneExpired();
  }

  /// Removes dedup entries older than 24 hours.
  /// Keys are formatted as "<timestampMs>_<messageId>" so comparison is
  /// purely lexicographic — no value scanning required.
  static void _pruneExpired() {
    try {
      final box    = Hive.box<String>(_dedupBox);
      if (box.isEmpty) return;

      final cutoffMs = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;

      final expired = box.keys.where((k) {
        final parts = k.toString().split('_');
        if (parts.isEmpty) return true;
        final ts = int.tryParse(parts.first);
        return ts == null || ts < cutoffMs;
      }).toList();

      if (expired.isNotEmpty) {
        box.deleteAll(expired);
        if (kDebugMode) {
          print('RealtimeRouter: pruned ${expired.length} expired dedup entries');
        }
      }
    } catch (e) {
      if (kDebugMode) print('RealtimeRouter: _pruneExpired error: $e');
    }
  }

  static DateTime _lastCleanup = DateTime.now();

  // ── Queue-type resolver (mirrors SyncService) ─────────────────────────────
  static String _resolveQueueType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'zakat';
    final s = raw.toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) {
      return 'non-zakat';
    }
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    if (s == 'zakat') return 'zakat';
    return 'zakat';
  }

  // ── Main router ───────────────────────────────────────────────────────────

  static Future<void> routeMessage(Map<String, dynamic> message) async {
    // Periodic prune — replaces the old 5-min in-memory clear
    if (DateTime.now().difference(_lastCleanup).inMinutes > 5) {
      _pruneExpired();
      _lastCleanup = DateTime.now();
    }

    // Generate a stable message ID (prefer server-assigned, fall back to
    // clientId + timestamp composite which is good enough for same-session dedup)
    final messageId = message['_messageId']?.toString() ??
        '${message['_clientId'] ?? 'unknown'}_'
        '${message['_timestamp'] ?? DateTime.now().millisecondsSinceEpoch}';

    // [P3] Check Hive dedup store
    final box = Hive.box<String>(_dedupBox);
    final alreadySeen = box.values.contains(messageId);
    if (alreadySeen) {
      if (kDebugMode) print('⚠️ Duplicate message ignored: $messageId');
      return;
    }

    // [P3] Persist with timestamped key so TTL prune works by prefix
    final dedupKey =
        '${DateTime.now().millisecondsSinceEpoch}_$messageId';
    await box.put(dedupKey, messageId);

    final type = message['event_type']?.toString() ?? '';
    final data = message['data'] as Map<String, dynamic>? ?? message;

    if (kDebugMode) {
      print('''
════════════ REALTIME ROUTER ════════════
Type: $type
Msg ID: $messageId
Sender: ${message['_senderRole'] ?? '?'}
Branch: ${data['branchId'] ?? message['branchId'] ?? '?'}
Serial: ${data['serial'] ?? 'N/A'}
════════════════════════════════════════
''');
    }

    switch (type) {
      case 'token_created':
      case RealtimeEvents.saveEntry:
        await _handleSaveEntry(data, message);
        break;

      case RealtimeEvents.deleteEntry:
        await _handleDeleteEntry(data);
        break;

      case 'prescription_created':
      case RealtimeEvents.savePrescription:
        await _handleSavePrescription(data, message);
        break;

      case RealtimeEvents.deletePrescription:
        await _handleDeletePrescription(data);
        break;

      case RealtimeEvents.savePatient:
        await LocalStorageService.saveLocalPatient(
          data['data'] as Map<String, dynamic>? ?? data,
        );
        break;

      case RealtimeEvents.deletePatient:
        if (data['patientId'] != null) {
          await LocalStorageService.deleteLocalPatient(data['patientId']);
        }
        break;

      case 'dispense_completed':
        await _handleDispenseCompleted(data, message);
        break;

      // ── INVENTORY: stock addition or new medicine registration ──────────────
      case RealtimeEvents.saveStockItem:
        await _handleSaveStockItem(data, message);
        break;

      case RealtimeEvents.deleteStockItem:
        await _handleDeleteStockItem(data);
        break;

      // ── ATTENDANCE EVENTS ──────────────────────────────────────────────────
      case RealtimeEvents.saveBiometricLog:
      case RealtimeEvents.saveEmployeeAttendance:
      case RealtimeEvents.saveFacultyAttendance:
      case RealtimeEvents.saveStudentAttendance:
        await _handleAttendanceEvent(type, data);
        break;

      // ── MADRASSA & SCHOOL EVENTS ───────────────────────────────────────────
      case RealtimeEvents.saveMadrassaAdmission:
      case RealtimeEvents.saveMadrassaFee:
      case RealtimeEvents.saveMadrassaHifzProgress:
      case RealtimeEvents.saveExamResult:
        await _handleMadrassaEvent(type, data);
        break;

      // ── FINANCE EVENTS ────────────────────────────────────────────────────
      case RealtimeEvents.saveExpense:
      case RealtimeEvents.deleteExpense:
      case RealtimeEvents.saveLoan:
      case RealtimeEvents.deleteLoan:
      case RealtimeEvents.saveFinanceEntry:
        await _handleFinanceEvent(type, data);
        break;

      // ── DONATION EVENTS ───────────────────────────────────────────────────
      case RealtimeEvents.saveDonationReceipt:
      case RealtimeEvents.saveDonor:
      case RealtimeEvents.saveDonationCollection:
        await _handleDonationEvent(type, data);
        break;

      // ── DASTERKHWAAN EVENTS ───────────────────────────────────────────────
      case RealtimeEvents.saveDasterkhwanEntry:
      case RealtimeEvents.saveDasterkhwanStock:
      case RealtimeEvents.saveOfficeBoyToken:
      case RealtimeEvents.saveKitchenServeLog:
        await _handleDasterkhwanEvent(type, data);
        break;

      // ── LIBRARY EVENTS ───────────────────────────────────────────────────
      case RealtimeEvents.saveLibraryBook:
      case RealtimeEvents.saveLibraryIssue:
      case RealtimeEvents.deleteLibraryBook:
        await _handleLibraryEvent(type, data);
        break;

      // ── FACULTY & STAFF EVENTS ────────────────────────────────────────────
      case RealtimeEvents.saveFaculty:
      case RealtimeEvents.saveStaffProfile:
        await _handleStaffEvent(type, data);
        break;

      // ── SUPERVISOR EVENTS ─────────────────────────────────────────────────
      case RealtimeEvents.saveSupervisorAction:
      case RealtimeEvents.approveEditRequest:
      case RealtimeEvents.rejectEditRequest:
        await _handleSupervisorEvent(type, data);
        break;

      case 'welcome':
      case 'identify_request':
      case 'identified':
        // ignore connection handshake messages
        break;

      default:
        if (kDebugMode) print('⚠️ Unhandled realtime event: $type');
    }
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  static Future<void> _handleSaveEntry(
    Map<String, dynamic> data,
    Map<String, dynamic> fullMessage,
  ) async {
    // CRITICAL: Extract branchId correctly from EITHER location
    final branchId = (fullMessage['branchId']?.toString() ??
                     data['branchId']?.toString() ??
                     '').toLowerCase().trim();

    final serial = data['serial']?.toString().trim();

    if (branchId.isEmpty || serial == null || serial.isEmpty) {
      if (kDebugMode) {
        print('❌ save_entry missing branchId or serial');
        print('   fullMessage branchId: ${fullMessage['branchId']}');
        print('   data branchId: ${data['branchId']}');
        print('   serial: $serial');
      }
      return;
    }

    // CRITICAL: Use CONSISTENT key format across all devices
    final uniqueKey = '$branchId-$serial';

    // Build complete entry data — merge everything
    final entryData = <String, dynamic>{
      'serial':       serial,
      'branchId':     branchId,
      'queueType':    data['queueType'] ?? 'zakat',
      'patientId':    data['patientId'] ?? '',
      'patientName':  data['patientName'] ?? 'Unknown',
      'patientCnic':  data['patientCnic'] ?? data['cnic'] ?? '',
      'guardianCnic': data['guardianCnic'],
      'createdAt':    data['createdAt'] ?? DateTime.now().toIso8601String(),
      'status':       data['status'] ?? 'waiting',
      'vitals':       data['vitals'] ?? {},
      'createdBy':    data['createdBy'] ?? '',
      'createdByName':data['createdByName'] ?? '',
      'dateKey':      data['dateKey'] ?? serial.split('-')[0],
    };

    // Add any additional fields from data not already included
    data.forEach((key, value) {
      if (!entryData.containsKey(key) && value != null) {
        entryData[key] = value;
      }
    });

    // CRITICAL: Save to Hive IMMEDIATELY
    final box = Hive.box(LocalStorageService.entriesBox);
    await box.put(uniqueKey, entryData);

    if (kDebugMode) print('✅ ENTRY SAVED → $uniqueKey');

    // [P2] Enqueue for direct Firestore upload on non-server devices.
    // Skip when the message originated from the server's own catch-up push
    // to prevent the server device from double-enqueuing.
    if (fullMessage['_serverPush'] != true) {
      final dateKey   = (entryData['dateKey'] as String?) ??
          serial.split('-')[0];
      final queueType = _resolveQueueType(entryData['queueType']?.toString());
      await LocalStorageService.enqueueSync({
        'type':      'save_entry',
        'branchId':  branchId,
        'dateKey':   dateKey,
        'queueType': queueType,
        'serial':    serial,
        'data':      entryData,
      });
      if (kDebugMode) print('[P2] Enqueued save_entry for direct upload: $serial');
    }
  }

  static Future<void> _handleDeleteEntry(Map<String, dynamic> data) async {
    final branchId = data['branchId']?.toString().toLowerCase().trim();
    final serial   = data['serial']?.toString().trim();

    if (branchId == null || branchId.isEmpty ||
        serial == null || serial.isEmpty) {
      if (kDebugMode) print('❌ delete_entry missing branchId or serial');
      return;
    }

    final key = '$branchId-$serial';
    await Hive.box(LocalStorageService.entriesBox).delete(key);
    if (kDebugMode) print('✅ ENTRY DELETED → $key');
  }

  static Future<void> _handleSavePrescription(
    Map<String, dynamic> data,
    Map<String, dynamic> fullMessage,
  ) async {
    final serial   = data['serial']?.toString().trim();
    final branchId = (fullMessage['branchId']?.toString() ??
                     data['branchId']?.toString() ??
                     '').toLowerCase().trim();

    if (serial == null || serial.isEmpty) {
      if (kDebugMode) print('❌ save_prescription missing serial');
      return;
    }

    // CRITICAL: Save prescription to its own box IMMEDIATELY
    await LocalStorageService.saveLocalPrescription(data);

    // NEW: Handle medicine restriction for multi-day prescriptions
    _handleMedicineRestriction(data, fullMessage);

    // CRITICAL: Also update the entry status if we have branchId
    if (branchId.isNotEmpty) {
      final entryKey = '$branchId-$serial';
      final box      = Hive.box(LocalStorageService.entriesBox);
      final entry    = box.get(entryKey);

      if (entry != null) {
        final updated = Map<String, dynamic>.from(entry);
        updated['status']         = 'completed';
        updated['prescription']   = data;
        updated['prescriptionId'] = data['id'] ?? serial;
        updated['completedAt']    =
            data['completedAt'] ?? DateTime.now().toIso8601String();

        await box.put(entryKey, updated);

        if (kDebugMode) {
          print('╔════════════════════════════════════════════════════════════╗');
          print('║ ✅ PRESCRIPTION SAVED TO HIVE (ROUTER)                    ║');
          print('╠════════════════════════════════════════════════════════════╣');
          print('║ Serial: $serial');
          print('║ Entry Key: $entryKey');
          print('║ Entry Status Updated: completed');
          print('║ Prescription ID: ${updated['prescriptionId']}');
          print('╚════════════════════════════════════════════════════════════╝');
        }
      } else {
        if (kDebugMode) print('⚠️ Entry not found for prescription: $entryKey');
      }
    }

    // [P2] Enqueue prescription + serial status patch for direct Firestore
    // upload. queueType and dateKey are resolved by SyncService from the
    // local entries box at upload time (same fallback path as P1 fix).
    if (fullMessage['_serverPush'] != true && branchId.isNotEmpty) {
      await LocalStorageService.enqueueSync({
        'type':     'save_prescription',
        'branchId': branchId,
        'serial':   serial,
        // queueType + dateKey intentionally omitted here — SyncService
        // resolves them from Hive at upload time via the P1 fallback,
        // which is safer than caching potentially-wrong values now.
        'data':     data,
      });
      if (kDebugMode) {
        print('[P2] Enqueued save_prescription for direct upload: $serial');
      }
    }
  }

  static Future<void> _handleDeletePrescription(Map<String, dynamic> data) async {
    final id = data['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await LocalStorageService.deleteLocalPrescription(id);
      if (kDebugMode) print('✅ PRESCRIPTION DELETED → $id');
    }
  }

  // Updated signature: now receives fullMessage to access _serverPush flag
  static Future<void> _handleDispenseCompleted(
    Map<String, dynamic> data,
    Map<String, dynamic> fullMessage,
  ) async {
    final branchId = (data['branchId']?.toString() ?? '').toLowerCase().trim();
    final serial   = data['serial']?.toString().trim();

    if (branchId.isEmpty || serial == null || serial.isEmpty) {
      if (kDebugMode) print('❌ dispense_completed missing branchId or serial');
      return;
    }

    final key      = '$branchId-$serial';
    final box      = Hive.box(LocalStorageService.entriesBox);
    final existing = box.get(key);

    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing);
      updated['dispenseStatus'] = 'dispensed';
      updated['status']         = 'completed';
      updated['dispensedAt']    =
          data['dispensedAt'] ?? DateTime.now().toIso8601String();
      updated['dispensedBy']    = data['dispensedBy'];
      updated['completedAt']    =
          data['completedAt'] ?? DateTime.now().toIso8601String();

      await box.put(key, updated);

      if (kDebugMode) {
        print('╔════════════════════════════════════════════════════════════╗');
        print('║ ✅ DISPENSE COMPLETED (ROUTER)                            ║');
        print('╠════════════════════════════════════════════════════════════╣');
        print('║ Serial: $serial');
        print('║ Entry Key: $key');
        print('║ Dispensed By: ${data['dispensedBy']}');
        print('╚════════════════════════════════════════════════════════════╝');
      }
    } else {
      if (kDebugMode) print('⚠️ Entry not found for dispense: $key');
    }

    // [P2] Enqueue serial status patch for direct Firestore upload.
    // queueType and dateKey are pulled from the now-updated Hive entry
    // (or the just-fetched existing entry) so they are as accurate as possible.
    if (fullMessage['_serverPush'] != true) {
      final entryForQueue = existing != null
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};

      await LocalStorageService.enqueueSync({
        'type':      'update_serial_status',
        'branchId':  branchId,
        'serial':    serial,
        'queueType': entryForQueue['queueType'],  // resolved by SyncService if null
        'dateKey':   entryForQueue['dateKey'],     // resolved by SyncService if null
        'data': {
          'dispenseStatus': 'dispensed',
          'status':         'completed',
          'dispensedAt':    data['dispensedAt'] ?? DateTime.now().toIso8601String(),
          'dispensedBy':    data['dispensedBy'] ?? '',
          'completedAt':    data['completedAt'] ?? DateTime.now().toIso8601String(),
        },
      });
      if (kDebugMode) {
        print('[P2] Enqueued update_serial_status (dispense) for direct upload: $serial');
      }
    }
  }

  static void _handleMedicineRestriction(Map<String, dynamic> data, Map<String, dynamic> full) {
    // Check for daysOfMedicine (1 is default, 2+ is multi-day)
    final days = int.tryParse(data['daysOfMedicine']?.toString() ?? '1') ?? 1;
    if (days <= 1) return;

    final bId = (full['branchId']?.toString() ?? data['branchId']?.toString())
        ?.toLowerCase().trim();
    
    // Fallback chain for patient identity
    final pId = data['patientCnic']?.toString() ??
               data['cnic']?.toString() ??
               data['patientId']?.toString();

    if (bId != null && bId.isNotEmpty && pId != null && pId.trim().isNotEmpty) {
      LocalStorageService.saveMedicineRestriction(
        branchId:    bId,
        patientId:   pId.trim(),
        daysCovered: days,
      );
      if (kDebugMode) {
        print('💊 [Router] Multi-day restriction applied: $pId ($days days)');
      }
    }
  }

  // ── INVENTORY: handle incoming stock update from another LAN device ──────────
  //
  // Two sub-cases:
  //   (a) Full medicine data (new registration or replaced item) → saveLocalInventoryItem
  //   (b) Quantity delta only (add-stock) → updateLocalStockQuantity
  //
  // In both cases we also enqueue for Firestore sync so the server can
  // upload when connectivity is restored.
  static Future<void> _handleSaveStockItem(
    Map<String, dynamic> data,
    Map<String, dynamic> fullMessage,
  ) async {
    final branchId = (fullMessage['branchId']?.toString() ??
                     data['branchId']?.toString() ??
                     '').toLowerCase().trim();

    final medicineId = (data['id'] ?? data['medicineId'])?.toString().trim();

    if (medicineId == null || medicineId.isEmpty) {
      if (kDebugMode) print('❌ save_stock_item missing medicineId');
      return;
    }

    // Check whether this is a quantity-only delta update or a full item save
    final rawDelta = data['_quantityDelta'];
    final bool isDelta = rawDelta != null;

    if (isDelta) {
      // ── Case (b): add-stock delta — increment existing Hive quantity ──
      final delta = rawDelta is num
          ? rawDelta.toDouble()
          : double.tryParse(rawDelta.toString()) ?? 0.0;

      if (delta != 0) {
        await LocalStorageService.updateLocalStockQuantity(medicineId, delta);
        if (kDebugMode) {
          print('✅ STOCK DELTA applied via LAN → $medicineId +$delta');
        }
      }

      // Note: We DO NOT enqueue `add_inventory_stock` here anymore!
      // Since it uses `FieldValue.increment` on Firestore, having multiple devices
      // enqueue the same delta will result in double-counting/duplication.
      // We rely solely on the originator device (the Dispenser) to sync the increment
      // to Firestore.

    } else {
      // ── Case (a): full item (new registration or full replacement) ──
      LocalStorageService.saveLocalInventoryItem(data);
      if (kDebugMode) {
        print('✅ INVENTORY ITEM saved via LAN → $medicineId');
      }

      // Enqueue Firestore sync for this registration (offline resilience)
      if (fullMessage['_serverPush'] != true && branchId.isNotEmpty) {
        await LocalStorageService.enqueueSync({
          'type':     'register_medicine',
          'branchId': branchId,
          'data':     data,
        });
        if (kDebugMode) print('[Router] Enqueued register_medicine for Firestore sync');
      }
    }
  }

  static Future<void> _handleDeleteStockItem(Map<String, dynamic> data) async {
    final medicineId = (data['id'] ?? data['medicineId'])?.toString().trim();
    if (medicineId != null && medicineId.isNotEmpty) {
      await LocalStorageService.deleteLocalStockItem(medicineId);
      if (kDebugMode) print('✅ STOCK ITEM DELETED via LAN → $medicineId');
    }
  }

  // ── Module Handlers for Local Hive Tier 1 Save ───────────────────────────

  static Future<void> _handleAttendanceEvent(String type, Map<String, dynamic> data) async {
    try {
      final box = await LocalStorageService.openBoxSafe('attendance_box');
      final id = data['id']?.toString() ?? data['punchId']?.toString() ?? 'att_${DateTime.now().microsecondsSinceEpoch}';
      await box.put(id, LocalStorageService.sanitize(data));
      if (kDebugMode) print('✅ ATTENDANCE EVENT saved via LAN → $type ($id)');
    } catch (e) {
      if (kDebugMode) print('❌ _handleAttendanceEvent error: $e');
    }
  }

  static Future<void> _handleMadrassaEvent(String type, Map<String, dynamic> data) async {
    try {
      final boxName = type == RealtimeEvents.saveMadrassaFee ? 'madrassa_fees' : 'madrassa_box';
      final box = await LocalStorageService.openBoxSafe(boxName);
      final id = data['id']?.toString() ?? data['receiptNo']?.toString() ?? data['admissionNo']?.toString() ?? 'mad_${DateTime.now().microsecondsSinceEpoch}';
      await box.put(id, LocalStorageService.sanitize(data));
      if (kDebugMode) print('✅ MADRASSA EVENT saved via LAN → $type ($id)');
    } catch (e) {
      if (kDebugMode) print('❌ _handleMadrassaEvent error: $e');
    }
  }

  static Future<void> _handleFinanceEvent(String type, Map<String, dynamic> data) async {
    try {
      String boxName = 'finance_entries';
      if (type == RealtimeEvents.saveExpense || type == RealtimeEvents.deleteExpense) {
        boxName = 'finance_expenses';
      } else if (type == RealtimeEvents.saveLoan || type == RealtimeEvents.deleteLoan) {
        boxName = 'finance_loans';
      }
      final box = await LocalStorageService.openBoxSafe(boxName);
      final id = data['id']?.toString() ?? 'fin_${DateTime.now().microsecondsSinceEpoch}';
      if (type == RealtimeEvents.deleteExpense || type == RealtimeEvents.deleteLoan) {
        await box.delete(id);
        if (kDebugMode) print('✅ FINANCE ITEM DELETED via LAN → $type ($id)');
      } else {
        await box.put(id, LocalStorageService.sanitize(data));
        if (kDebugMode) print('✅ FINANCE EVENT saved via LAN → $type ($id)');
      }
    } catch (e) {
      if (kDebugMode) print('❌ _handleFinanceEvent error: $e');
    }
  }

  static Future<void> _handleDonationEvent(String type, Map<String, dynamic> data) async {
    try {
      final box = await LocalStorageService.openBoxSafe('donations_box');
      final id = data['id']?.toString() ?? data['receiptNumber']?.toString() ?? 'don_${DateTime.now().microsecondsSinceEpoch}';
      await box.put(id, LocalStorageService.sanitize(data));
      if (kDebugMode) print('✅ DONATION EVENT saved via LAN → $type ($id)');
    } catch (e) {
      if (kDebugMode) print('❌ _handleDonationEvent error: $e');
    }
  }

  static Future<void> _handleDasterkhwanEvent(String type, Map<String, dynamic> data) async {
    try {
      final box = await LocalStorageService.openBoxSafe('dasterkhwaan_entries');
      final id = data['id']?.toString() ?? 'das_${DateTime.now().microsecondsSinceEpoch}';
      await box.put(id, LocalStorageService.sanitize(data));
      if (kDebugMode) print('✅ DASTERKHWAAN EVENT saved via LAN → $type ($id)');
    } catch (e) {
      if (kDebugMode) print('❌ _handleDasterkhwanEvent error: $e');
    }
  }

  static Future<void> _handleSupervisorEvent(String type, Map<String, dynamic> data) async {
    try {
      final box = await LocalStorageService.openBoxSafe('local_edit_requests');
      final id = data['requestId']?.toString() ?? data['id']?.toString() ?? 'sup_${DateTime.now().microsecondsSinceEpoch}';
      await box.put(id, LocalStorageService.sanitize(data));
      if (kDebugMode) print('✅ SUPERVISOR EVENT saved via LAN → $type ($id)');
    } catch (e) {
      if (kDebugMode) print('❌ _handleSupervisorEvent error: $e');
    }
  }

  static Future<void> _handleLibraryEvent(String type, Map<String, dynamic> data) async {
    try {
      final box = await LocalStorageService.openBoxSafe('library_box');
      final id = data['id']?.toString() ?? data['bookId']?.toString() ?? 'lib_${DateTime.now().microsecondsSinceEpoch}';
      if (type == RealtimeEvents.deleteLibraryBook) {
        await box.delete(id);
        if (kDebugMode) print('✅ LIBRARY BOOK DELETED via LAN → $id');
      } else {
        await box.put(id, LocalStorageService.sanitize(data));
        if (kDebugMode) print('✅ LIBRARY EVENT saved via LAN → $type ($id)');
      }
    } catch (e) {
      if (kDebugMode) print('❌ _handleLibraryEvent error: $e');
    }
  }

  static Future<void> _handleStaffEvent(String type, Map<String, dynamic> data) async {
    try {
      final box = await LocalStorageService.openBoxSafe(LocalStorageService.usersBox);
      final id = data['uid']?.toString() ?? data['id']?.toString() ?? 'usr_${DateTime.now().microsecondsSinceEpoch}';
      await box.put(id, LocalStorageService.sanitize(data));
      if (kDebugMode) print('✅ STAFF/FACULTY PROFILE saved via LAN → $type ($id)');
    } catch (e) {
      if (kDebugMode) print('❌ _handleStaffEvent error: $e');
    }
  }
}
