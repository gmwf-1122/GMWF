// lib/tools/legacy_data_migration_adapter.dart
//
// ONE-TIME MIGRATION ADAPTER (v1.3.7)
// Scans pre-existing Hive records across sync queue, patients, donations,
// submissions, and finance boxes. Backfills UUID v4 identifiers (syncId/recordId)
// and sets 'v1_3_7_migration_done' flag.
//
// HARD EXPIRY: Scheduled for complete removal in v1.4.0 (30 days post-rollout).

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/local_storage_service.dart';

class LegacyDataMigrationAdapter {
  static const _uuid = Uuid();
  static const String _flagKey = 'v1_3_7_legacy_data_migrated';

  /// Runs the one-time migration if not already completed on this node.
  static Future<void> runOnce() async {
    try {
      final flagsBox = Hive.box('app_flags');
      final isAlreadyMigrated = flagsBox.get(_flagKey, defaultValue: false) as bool;
      if (isAlreadyMigrated) {
        return;
      }

      debugPrint('[LegacyMigrationAdapter] 🚀 Starting one-time v1.3.7 UUID backfill migration...');
      int migratedCount = 0;

      // 1. Sync Queue Box
      if (Hive.isBoxOpen(LocalStorageService.syncBox)) {
        final syncBox = Hive.box(LocalStorageService.syncBox);
        final Map<dynamic, dynamic> queueMap = Map.from(syncBox.toMap());
        for (final entry in queueMap.entries) {
          final key = entry.key;
          final val = entry.value;
          if (val is Map) {
            final action = Map<String, dynamic>.from(val);
            bool updated = false;
            if (action['syncId'] == null || action['syncId'].toString().isEmpty) {
              action['syncId'] = _uuid.v4();
              updated = true;
            }
            if (action['entityId'] == null || action['entityId'].toString().isEmpty) {
              final payloadData = action['data'] is Map ? Map<String, dynamic>.from(action['data']) : null;
              final existingEntityId = action['localId'] ?? payloadData?['localId'] ?? payloadData?['id'] ?? action['id'];
              action['entityId'] = (existingEntityId != null && existingEntityId.toString().isNotEmpty)
                  ? existingEntityId.toString()
                  : _uuid.v4();
              updated = true;
            }
            action['legacyMigrated'] = true;
            if (updated) {
              await syncBox.put(key, action);
              migratedCount++;
            }
          }
        }
      }

      // 2. Patient Storage Box
      if (Hive.isBoxOpen(LocalStorageService.patientsBox)) {
        final patientsBox = Hive.box(LocalStorageService.patientsBox);
        final Map<dynamic, dynamic> patientMap = Map.from(patientsBox.toMap());
        for (final entry in patientMap.entries) {
          final key = entry.key;
          final val = entry.value;
          if (val is Map) {
            final p = Map<String, dynamic>.from(val);
            if (p['patientId'] == null || p['patientId'].toString().isEmpty) {
              p['patientId'] = _uuid.v4();
              p['legacyKey'] = key.toString();
              p['legacyMigrated'] = true;
              await patientsBox.put(key, p);
              migratedCount++;
            }
          }
        }
      }

      // 3. Donations Box
      if (Hive.isBoxOpen(LocalStorageService.donationsBox)) {
        final donationsBox = Hive.box(LocalStorageService.donationsBox);
        final Map<dynamic, dynamic> donationsMap = Map.from(donationsBox.toMap());
        for (final entry in donationsMap.entries) {
          final key = entry.key;
          final val = entry.value;
          if (val is Map) {
            final don = Map<String, dynamic>.from(val);
            if (don['donationId'] == null || don['donationId'].toString().isEmpty) {
              don['donationId'] = _uuid.v4();
              don['legacyKey'] = key.toString();
              don['legacyMigrated'] = true;
              await donationsBox.put(key, don);
              migratedCount++;
            }
          }
        }
      }

      // 4. Submissions Box
      if (Hive.isBoxOpen('submissions')) {
        final subBox = Hive.box('submissions');
        final Map<dynamic, dynamic> subMap = Map.from(subBox.toMap());
        for (final entry in subMap.entries) {
          final key = entry.key;
          final val = entry.value;
          if (val is Map) {
            final sub = Map<String, dynamic>.from(val);
            if (sub['submissionId'] == null || sub['submissionId'].toString().isEmpty) {
              sub['submissionId'] = _uuid.v4();
              sub['legacyKey'] = key.toString();
              sub['legacyMigrated'] = true;
              await subBox.put(key, sub);
              migratedCount++;
            }
          }
        }
      }

      await flagsBox.put(_flagKey, true);
      debugPrint('[LegacyMigrationAdapter] ✅ Migration complete. $migratedCount records upgraded to v2.0.0 UUID standard.');
    } catch (e) {
      debugPrint('[LegacyMigrationAdapter] ⚠️ Exception during legacy migration: $e');
    }
  }
}
