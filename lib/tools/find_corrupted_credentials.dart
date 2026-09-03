// lib/tools/find_corrupted_credentials.dart
//
// One-off diagnostic utility to detect BiometricCredential entries
// where entityId was incorrectly set to the biometric PIN (instead of
// the real employee/student ID). These entries cause attendance lookup
// mismatches and need to be manually re-linked.

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/biometric_credential.dart';
import '../services/local_storage_service.dart';

class FindCorruptedCredentials {
  /// Scans all BiometricCredential entries in Hive and returns a list of
  /// credentials whose [entityId] does NOT match any known employee or
  /// student key in the system.
  ///
  /// Each result map contains:
  /// - `credentialId`: the credential's id
  /// - `biometricPin`: the PIN assigned on the ZKTeco device
  /// - `entityId`: the stored entityId (likely the PIN itself if corrupted)
  /// - `entityName`: the name stored on the credential
  /// - `entityType`: employee / madrassa_student / school_student / etc.
  /// - `branchId`: branch the credential belongs to
  /// - `reason`: human-readable explanation of why it's flagged
  static List<Map<String, dynamic>> findCorruptedEntries() {
    final results = <Map<String, dynamic>>[];

    try {
      if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) {
        debugPrint('[FindCorruptedCredentials] biometricCredentialsBox is not open.');
        return results;
      }

      final credBox = Hive.box(LocalStorageService.biometricCredentialsBox);

      // Build lookup sets for valid employee/student IDs
      final validEmployeeIds = <String>{};
      if (Hive.isBoxOpen(LocalStorageService.employeesBox)) {
        final empBox = Hive.box(LocalStorageService.employeesBox);
        for (final k in empBox.keys) {
          validEmployeeIds.add(k.toString());
          final emp = empBox.get(k);
          if (emp is Map) {
            final localId = emp['localId']?.toString() ?? '';
            final id = emp['id']?.toString() ?? '';
            if (localId.isNotEmpty) validEmployeeIds.add(localId);
            if (id.isNotEmpty) validEmployeeIds.add(id);
          }
        }
      }

      final validStudentIds = <String>{};
      // Madrassa students
      if (Hive.isBoxOpen(LocalStorageService.madrassaStudentsBox)) {
        final box = Hive.box(LocalStorageService.madrassaStudentsBox);
        for (final k in box.keys) {
          validStudentIds.add(k.toString());
          final st = box.get(k);
          if (st is Map) {
            final localId = st['localId']?.toString() ?? '';
            final id = st['id']?.toString() ?? '';
            if (localId.isNotEmpty) validStudentIds.add(localId);
            if (id.isNotEmpty) validStudentIds.add(id);
          }
        }
      }
      // School students
      if (Hive.isBoxOpen(LocalStorageService.schoolStudentsBox)) {
        final box = Hive.box(LocalStorageService.schoolStudentsBox);
        for (final k in box.keys) {
          validStudentIds.add(k.toString());
          final st = box.get(k);
          if (st is Map) {
            final localId = st['localId']?.toString() ?? '';
            final id = st['id']?.toString() ?? '';
            if (localId.isNotEmpty) validStudentIds.add(localId);
            if (id.isNotEmpty) validStudentIds.add(id);
          }
        }
      }

      // Scan all credentials
      for (final key in credBox.keys) {
        final raw = credBox.get(key);
        if (raw is! Map) continue;

        final cred = BiometricCredential.fromMap(raw);
        if (!cred.active) continue;

        final entityId = cred.entityId.trim();
        final pin = cred.biometricPin.trim();

        // Heuristic 1: entityId equals the PIN (the exact bug scenario)
        final isPinAsEntityId = entityId == pin;

        // Heuristic 2: entityId is purely numeric and short (looks like a PIN, not a real ID)
        final looksLikePin = entityId.isNotEmpty &&
            int.tryParse(entityId) != null &&
            entityId.length <= 5;

        // Heuristic 3: entityId not found in any known employee/student box
        final type = cred.entityType.toLowerCase();
        bool foundInSystem = false;

        if (type.contains('student') || type.contains('madrassa') || type.contains('school')) {
          foundInSystem = validStudentIds.contains(entityId);
        } else {
          foundInSystem = validEmployeeIds.contains(entityId);
        }
        // Also try across both in case of cross-type linkage
        if (!foundInSystem) {
          foundInSystem = validEmployeeIds.contains(entityId) || validStudentIds.contains(entityId);
        }

        // Flag if entityId matches PIN or is not found in the system
        if (isPinAsEntityId || (!foundInSystem && looksLikePin) || !foundInSystem) {
          String reason;
          if (isPinAsEntityId) {
            reason = 'entityId "$entityId" is identical to biometricPin — was likely set by the PIN fallback bug';
          } else if (!foundInSystem && looksLikePin) {
            reason = 'entityId "$entityId" looks like a PIN (short numeric) and was not found in employees/students boxes';
          } else {
            reason = 'entityId "$entityId" was not found in any employees or students Hive box';
          }

          results.add({
            'credentialId': cred.id,
            'biometricPin': cred.biometricPin,
            'entityId': cred.entityId,
            'entityName': cred.entityName,
            'entityType': cred.entityType,
            'branchId': cred.branchId,
            'reason': reason,
          });
        }
      }

      debugPrint('[FindCorruptedCredentials] Scan complete. Found ${results.length} potentially corrupted credential(s).');
      for (final r in results) {
        debugPrint('  ⚠️ PIN=${r['biometricPin']} | entityId=${r['entityId']} | name=${r['entityName']} | reason=${r['reason']}');
      }
    } catch (e, st) {
      debugPrint('[FindCorruptedCredentials] Error scanning credentials: $e\n$st');
    }

    return results;
  }
}
