// lib/realtime/realtime_router.dart
// CRITICAL FIXES:
// 1. Save ALL received messages to Hive IMMEDIATELY (before any processing)
// 2. Proper key generation for cross-device consistency
// 3. No blocking Firestore calls

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/local_storage_service.dart';
import 'realtime_events.dart';

class RealtimeRouter {
  static final Set<String> _processedMessageIds = {};
  static DateTime _lastCleanup = DateTime.now();

  static Future<void> routeMessage(Map<String, dynamic> message) async {
    // Periodic cleanup
    if (DateTime.now().difference(_lastCleanup).inMinutes > 5) {
      _processedMessageIds.clear();
      _lastCleanup = DateTime.now();
    }

    // Generate fallback ID if missing
    String messageId = message['_messageId']?.toString() ??
        '${message['_clientId'] ?? 'unknown'}_${message['_timestamp'] ?? DateTime.now().millisecondsSinceEpoch}';

    if (_processedMessageIds.contains(messageId)) {
      if (kDebugMode) print('⚠️ Duplicate message ignored: $messageId');
      return;
    }

    _processedMessageIds.add(messageId);

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
        await _handleDispenseCompleted(data);
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
static Future<void> _handleSaveEntry(Map<String, dynamic> data, Map<String, dynamic> fullMessage) async {
  // CRITICAL: Extract branchId correctly from EITHER location
  final branchId = (fullMessage['branchId']?.toString() ?? 
                   data['branchId']?.toString() ?? 
                   '').toLowerCase().trim();
  
  final serial = data['serial']?.toString()?.trim();

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
  
  // Build complete entry data - merge everything
  final entryData = <String, dynamic>{
    'serial': serial,
    'branchId': branchId,
    'queueType': data['queueType'] ?? 'zakat',
    'patientId': data['patientId'] ?? '',
    'patientName': data['patientName'] ?? 'Unknown',
    'patientCnic': data['patientCnic'] ?? data['cnic'] ?? '',
    'guardianCnic': data['guardianCnic'],
    'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
    'status': data['status'] ?? 'waiting',
    'vitals': data['vitals'] ?? {},
    'createdBy': data['createdBy'] ?? '',
    'createdByName': data['createdByName'] ?? '',
    'dateKey': data['dateKey'] ?? serial.split('-')[0],
  };
  
  // Add any additional fields from data that aren't already included
  data.forEach((key, value) {
    if (!entryData.containsKey(key) && value != null) {
      entryData[key] = value;
    }
  });

  // CRITICAL: Save to Hive IMMEDIATELY
  final box = Hive.box(LocalStorageService.entriesBox);
  await box.put(uniqueKey, entryData);
  
  // Debug output
}
  static Future<void> _handleDeleteEntry(Map<String, dynamic> data) async {
    final branchId = data['branchId']?.toString()?.toLowerCase()?.trim();
    final serial = data['serial']?.toString()?.trim();
    
    if (branchId == null || branchId.isEmpty || serial == null || serial.isEmpty) {
      if (kDebugMode) print('❌ delete_entry missing branchId or serial');
      return;
    }
    
    final key = '$branchId-$serial';
    await Hive.box(LocalStorageService.entriesBox).delete(key);
    if (kDebugMode) print('✅ ENTRY DELETED → $key');
  }

static Future<void> _handleSavePrescription(Map<String, dynamic> data, Map<String, dynamic> fullMessage) async {
  final serial = data['serial']?.toString()?.trim();
  final branchId = (fullMessage['branchId']?.toString() ?? 
                   data['branchId']?.toString() ?? 
                   '').toLowerCase().trim();
  
  if (serial == null || serial.isEmpty) {
    if (kDebugMode) print('❌ save_prescription missing serial');
    return;
  }

  // CRITICAL: Save prescription to its own box IMMEDIATELY
  await LocalStorageService.saveLocalPrescription(data);
  
  // CRITICAL: Also update the entry status if we have branchId
  if (branchId.isNotEmpty) {
    final entryKey = '$branchId-$serial';
    final box = Hive.box(LocalStorageService.entriesBox);
    final entry = box.get(entryKey);
    
    if (entry != null) {
      final updated = Map<String, dynamic>.from(entry);
      updated['status'] = 'completed';
      updated['prescription'] = data;
      updated['prescriptionId'] = data['id'] ?? serial;
      updated['completedAt'] = data['completedAt'] ?? DateTime.now().toIso8601String();
      
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
}
  static Future<void> _handleDeletePrescription(Map<String, dynamic> data) async {
    final id = data['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await LocalStorageService.deleteLocalPrescription(id);
      if (kDebugMode) print('✅ PRESCRIPTION DELETED → $id');
    }
  }

  static Future<void> _handleDispenseCompleted(Map<String, dynamic> data) async {
    final branchId = (data['branchId']?.toString() ?? '').toLowerCase().trim();
    final serial = data['serial']?.toString()?.trim();

    if (branchId.isEmpty || serial == null || serial.isEmpty) {
      if (kDebugMode) print('❌ dispense_completed missing branchId or serial');
      return;
    }

    final key = '$branchId-$serial';
    final box = Hive.box(LocalStorageService.entriesBox);
    final existing = box.get(key);

    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing);
      updated['dispenseStatus'] = 'dispensed';
      updated['dispensedAt'] = data['dispensedAt'] ?? DateTime.now().toIso8601String();
      updated['dispensedBy'] = data['dispensedBy'];
      
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
  }
}