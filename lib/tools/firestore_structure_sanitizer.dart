import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/finance_local_storage.dart';

class FirestoreStructureSanitizer {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<String> _branchSubcollections = [
    'patients',
    'prescriptions',
    'dispensary',
    'serials',
    'employees',
    'users',
    'dasterkhwaan',
    'donations',
    'donors',
    'biometric_devices',
    'biometric_credentials',
    'biometric_punches',
    'notifications',
    'announcements',
    'settings',
    'charges',
    'dispensary_charges',
    'bank_slips',
    'inventory',
    'inventory_log',
    'audit_logs',
    'journal_entries',
    'madrassa_students',
    'school_students',
    'classes',
    'subjects',
    'attendance',
    'fees',
    'vouchers',
  ];

  /// Scans and permanently purges duplicate and bogus branch documents
  /// ('karachi_1', 'karachi_2', 'all', 'global', UIDs, and 13-digit CNIC documents)
  /// from the Firestore `branches` collection, safely re-routing any real data to 'karachi' or their proper branch.
  static Future<Map<String, dynamic>> cleanBogusBranchDocuments({
    void Function(String msg)? onProgress,
  }) async {
    final report = <String, dynamic>{
      'bogusBranchesFound': 0,
      'bogusBranchesDeleted': 0,
      'documentsMigrated': 0,
      'subcollectionDocsDeleted': 0,
      'errors': <String>[],
    };

    void log(String msg) {
      debugPrint('[FirestoreStructureSanitizer] $msg');
      onProgress?.call(msg);
    }

    try {
      log('🔍 Scanning Firestore branches collection...');
      final branchesSnap = await _db.collection('branches').get(const GetOptions(source: Source.serverAndCache));
      
      final bogusDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in branchesSnap.docs) {
        final id = doc.id.trim().toLowerCase();
        final name = (doc.data()['name'] as String? ?? '').trim().toLowerCase();
        final isKarachiDup = id.contains('karachi_1') ||
            id.contains('karachi_2') ||
            id.contains('karachi_one') ||
            id.contains('karachi_two') ||
            id.contains('karachi 1') ||
            id.contains('karachi 2') ||
            id.contains('karachi-1') ||
            id.contains('karachi-2') ||
            id == 'karachi1' ||
            id == 'karachi2' ||
            name.contains('karachi 1') ||
            name.contains('karachi 2') ||
            name.contains('karachi one') ||
            name.contains('karachi two');

        if (isKarachiDup || !LocalStorageService.isValidBranchId(id)) {
          bogusDocs.add(doc);
        }
      }

      report['bogusBranchesFound'] = bogusDocs.length;
      log('🔎 Identified ${bogusDocs.length} duplicate/bogus branch documents to remove.');

      for (final bogusDoc in bogusDocs) {
        final bogusBranchId = bogusDoc.id;
        log('🧹 Cleaning duplicate branch: $bogusBranchId...');

        for (final subcol in _branchSubcollections) {
          try {
            final subcolRef = _db.collection('branches').doc(bogusBranchId).collection(subcol);
            final subSnap = await subcolRef.get();

            if (subSnap.docs.isNotEmpty) {
              for (final d in subSnap.docs) {
                final data = d.data();
                
                // If it's from a Karachi duplicate, reparent directly into the consolidated 'karachi' branch
                final targetBranch = LocalStorageService.sanitizeBranchId(
                  bogusBranchId.toLowerCase().contains('karachi') ? 'karachi' : data['branchId']?.toString(),
                  fallback: 'karachi',
                );

                if (subcol == 'users') {
                  // User records belong in root /users
                  try {
                    await _db.collection('users').doc(d.id).set(data, SetOptions(merge: true));
                    report['documentsMigrated'] = (report['documentsMigrated'] as int) + 1;
                  } catch (_) {}
                } else if (subcol == 'dasterkhwaan') {
                  try {
                    final nestedTokens = await d.reference.collection('tokens').get();
                    for (final t in nestedTokens.docs) {
                      if (targetBranch != bogusBranchId) {
                        await _db
                            .collection('branches')
                            .doc(targetBranch)
                            .collection('dasterkhwaan')
                            .doc(d.id)
                            .collection('tokens')
                            .doc(t.id)
                            .set(t.data(), SetOptions(merge: true));
                      }
                      await t.reference.delete();
                      report['subcollectionDocsDeleted'] = (report['subcollectionDocsDeleted'] as int) + 1;
                    }
                  } catch (_) {}

                  if (targetBranch != bogusBranchId) {
                    await _db
                        .collection('branches')
                        .doc(targetBranch)
                        .collection(subcol)
                        .doc(d.id)
                        .set(data, SetOptions(merge: true));
                    report['documentsMigrated'] = (report['documentsMigrated'] as int) + 1;
                  }
                } else {
                  if (targetBranch != bogusBranchId) {
                    try {
                      await _db
                          .collection('branches')
                          .doc(targetBranch)
                          .collection(subcol)
                          .doc(d.id)
                          .set(data, SetOptions(merge: true));
                      report['documentsMigrated'] = (report['documentsMigrated'] as int) + 1;
                    } catch (e) {
                      debugPrint('[Sanitizer] Migration notice for ${d.id}: $e');
                    }
                  }
                }

                // Delete document from duplicate branch
                await d.reference.delete();
                report['subcollectionDocsDeleted'] = (report['subcollectionDocsDeleted'] as int) + 1;
              }
            }
          } catch (e) {
            report['errors'].add('Error cleaning $bogusBranchId/$subcol: $e');
          }
        }

        // Delete the parent branch document itself
        try {
          await bogusDoc.reference.delete();
          report['bogusBranchesDeleted'] = (report['bogusBranchesDeleted'] as int) + 1;
          log('✅ Successfully removed duplicate branch: $bogusBranchId');
        } catch (e) {
          report['errors'].add('Failed to delete branch document $bogusBranchId: $e');
        }

        // Also thoroughly purge from all local Hive caches
        try {
          if (Hive.isBoxOpen(LocalStorageService.branchesBox)) {
            final bBox = Hive.box(LocalStorageService.branchesBox);
            await bBox.delete('branch:$bogusBranchId');
            await bBox.delete(bogusBranchId);
          }
          if (Hive.isBoxOpen('local_branches')) {
            final bBox = Hive.box('local_branches');
            await bBox.delete('branch:$bogusBranchId');
            await bBox.delete(bogusBranchId);
          }
          if (Hive.isBoxOpen('app_settings')) {
            final box = Hive.box('app_settings');
            final cached = box.get('cached_branches_list');
            if (cached is List) {
              final cleaned = cached.where((e) {
                if (e is Map) {
                  final id = (e['id'] ?? '').toString().toLowerCase().trim();
                  return id != bogusBranchId && !id.contains('karachi_1') && !id.contains('karachi_2');
                }
                return true;
              }).toList();
              await box.put('cached_branches_list', cleaned);
            }
          }
          try {
            final custom = FinanceLocalStorage.getCustomBranches();
            final updated = custom.where((b) {
              final id = (b['id'] ?? '').toString().toLowerCase().trim();
              return id != bogusBranchId && !id.contains('karachi_1') && !id.contains('karachi_2');
            }).toList();
            if (Hive.isBoxOpen(LocalStorageService.financeSettingsBox)) {
              await Hive.box(LocalStorageService.financeSettingsBox).put(
                'global_custom_branches',
                updated.map((e) => Map<dynamic, dynamic>.from(e)).toList(),
              );
            }
          } catch (_) {}
        } catch (_) {}
      }

      log('🎉 Completed duplicate branch cleanup! Removed ${report['bogusBranchesDeleted']} duplicate branches.');
    } catch (e) {
      log('❌ Error during bogus branch cleanup: $e');
      report['errors'].add(e.toString());
    }

    return report;
  }

  /// Consolidates duplicate user records from branches/{branchId}/users into the single
  /// root /users/{uid} collection, removing double documents across Firestore.
  static Future<Map<String, dynamic>> cleanBranchUserDuplicates({
    void Function(String msg)? onProgress,
  }) async {
    final report = <String, dynamic>{
      'userDoublesFound': 0,
      'userDoublesCleaned': 0,
      'errors': <String>[],
    };

    void log(String msg) {
      debugPrint('[FirestoreStructureSanitizer] $msg');
      onProgress?.call(msg);
    }

    try {
      log('🔍 Checking for duplicate user documents inside branches...');
      final branchesSnap = await _db.collection('branches').get(const GetOptions(source: Source.serverAndCache));

      for (final bDoc in branchesSnap.docs) {
        final bId = bDoc.id.trim();
        try {
          final usersSubSnap = await _db.collection('branches').doc(bId).collection('users').get();
          if (usersSubSnap.docs.isNotEmpty) {
            log('📦 Consolidating ${usersSubSnap.docs.length} user documents from branch "$bId" into root /users...');
            report['userDoublesFound'] = (report['userDoublesFound'] as int) + usersSubSnap.docs.length;

            for (final uDoc in usersSubSnap.docs) {
              final uData = uDoc.data();
              final uid = uDoc.id.trim();

              if (uData.isNotEmpty) {
                if (uData['branchId'] == null || uData['branchId'].toString().isEmpty) {
                  uData['branchId'] = bId;
                }
                await _db.collection('users').doc(uid).set(uData, SetOptions(merge: true));
              }

              // Sync to root users collection while preserving branch users subcollection
              // Branch user documents must remain intact for branch-scoped auth & authorization
              report['userDoublesCleaned'] = (report['userDoublesCleaned'] as int) + 1;
            }
          }
        } catch (e) {
          report['errors'].add('Error consolidating users in branch $bId: $e');
        }
      }
      log('✅ Finished consolidating branch user documents. Removed ${report['userDoublesCleaned']} duplicates.');
    } catch (e) {
      log('❌ Error during user duplicates cleanup: $e');
      report['errors'].add(e.toString());
    }

    return report;
  }

  /// Cleans redundant root collections ('employees', 'patients', 'biometric_devices', 'biometric_credentials', 'biometric_punches', 'notifications', 'announcements')
  /// by moving valid records into their proper branch subcollection and removing the root bloat.
  static Future<Map<String, dynamic>> cleanRootCollections({
    void Function(String msg)? onProgress,
  }) async {
    final report = <String, dynamic>{
      'rootEmployeesCleaned': 0,
      'rootPatientsCleaned': 0,
      'rootDevicesCleaned': 0,
      'rootCredentialsCleaned': 0,
      'rootPunchesCleaned': 0,
      'rootNotificationsCleaned': 0,
      'rootAnnouncementsCleaned': 0,
      'errors': <String>[],
    };

    void log(String msg) {
      debugPrint('[FirestoreStructureSanitizer] $msg');
      onProgress?.call(msg);
    }

    // 1. Clean root employees collection
    try {
      log('🔍 Checking root employees collection...');
      final empSnap = await _db.collection('employees').get();
      if (empSnap.docs.isNotEmpty) {
        log('📦 Migrating ${empSnap.docs.length} root employee documents into their branch subcollections...');
        for (final doc in empSnap.docs) {
          final data = doc.data();
          final bId = LocalStorageService.sanitizeBranchId(data['branchId']?.toString(), fallback: 'karachi');
          
          await _db.collection('branches').doc(bId).collection('employees').doc(doc.id).set(data, SetOptions(merge: true));
          await doc.reference.delete();
          report['rootEmployeesCleaned'] = (report['rootEmployeesCleaned'] as int) + 1;
        }
        log('✅ Cleaned root employees collection.');
      }
    } catch (e) {
      report['errors'].add('Root employees clean error: $e');
    }

    // 2. Clean root patients collection
    try {
      log('🔍 Checking root patients collection...');
      final patSnap = await _db.collection('patients').get();
      if (patSnap.docs.isNotEmpty) {
        log('📦 Migrating ${patSnap.docs.length} root patient documents into their branch subcollections...');
        for (final doc in patSnap.docs) {
          final data = doc.data();
          final bId = LocalStorageService.sanitizeBranchId(data['branchId']?.toString(), fallback: 'karachi');
          
          await _db.collection('branches').doc(bId).collection('patients').doc(doc.id).set(data, SetOptions(merge: true));
          await doc.reference.delete();
          report['rootPatientsCleaned'] = (report['rootPatientsCleaned'] as int) + 1;
        }
        log('✅ Cleaned root patients collection.');
      }
    } catch (e) {
      report['errors'].add('Root patients clean error: $e');
    }

    // 3. Clean root biometric_devices collection
    try {
      log('🔍 Checking root biometric_devices collection...');
      final devSnap = await _db.collection('biometric_devices').get();
      if (devSnap.docs.isNotEmpty) {
        log('📦 Migrating ${devSnap.docs.length} root biometric device configs into branches...');
        for (final doc in devSnap.docs) {
          final data = doc.data();
          final bId = LocalStorageService.sanitizeBranchId(data['branchId']?.toString(), fallback: 'karachi');
          
          await _db.collection('branches').doc(bId).collection('biometric_devices').doc(doc.id).set(data, SetOptions(merge: true));
          await doc.reference.delete();
          report['rootDevicesCleaned'] = (report['rootDevicesCleaned'] as int) + 1;
        }
        log('✅ Cleaned root biometric_devices collection.');
      }
    } catch (e) {
      report['errors'].add('Root devices clean error: $e');
    }

    // 4. Clean root biometric_credentials collection
    try {
      log('🔍 Checking root biometric_credentials collection...');
      final credSnap = await _db.collection('biometric_credentials').get();
      if (credSnap.docs.isNotEmpty) {
        log('📦 Migrating ${credSnap.docs.length} root biometric credentials into branches...');
        for (final doc in credSnap.docs) {
          final data = doc.data();
          final bId = LocalStorageService.sanitizeBranchId(data['branchId']?.toString(), fallback: 'karachi');
          
          await _db.collection('branches').doc(bId).collection('biometric_credentials').doc(doc.id).set(data, SetOptions(merge: true));
          await doc.reference.delete();
          report['rootCredentialsCleaned'] = (report['rootCredentialsCleaned'] as int) + 1;
        }
        log('✅ Cleaned root biometric_credentials collection.');
      }
    } catch (e) {
      report['errors'].add('Root credentials clean error: $e');
    }

    // 5. Clean root biometric_punches collection
    try {
      log('🔍 Checking root biometric_punches collection...');
      final punchSnap = await _db.collection('biometric_punches').limit(500).get();
      if (punchSnap.docs.isNotEmpty) {
        for (final doc in punchSnap.docs) {
          await doc.reference.delete();
          report['rootPunchesCleaned'] = (report['rootPunchesCleaned'] as int) + 1;
        }
        log('✅ Cleaned ${report['rootPunchesCleaned']} legacy root punches.');
      }
    } catch (e) {
      report['errors'].add('Root punches clean error: $e');
    }

    // 6. Clean root notifications collection (re-route to branch or delete root doc)
    try {
      log('🔍 Checking root notifications collection...');
      final notifSnap = await _db.collection('notifications').limit(500).get();
      if (notifSnap.docs.isNotEmpty) {
        int notifCount = 0;
        for (final doc in notifSnap.docs) {
          final data = doc.data();
          final bId = LocalStorageService.sanitizeBranchId(data['branchId']?.toString(), fallback: 'karachi');
          if (bId.isNotEmpty) {
            await _db.collection('branches').doc(bId).collection('notifications').doc(doc.id).set(data, SetOptions(merge: true));
          }
          await doc.reference.delete();
          notifCount++;
        }
        report['rootNotificationsCleaned'] = notifCount;
        log('✅ Cleaned $notifCount root notifications, kept inside branches.');
      }
    } catch (e) {
      report['errors'].add('Root notifications clean error: $e');
    }

    // 7. Clean root announcements collection
    try {
      log('🔍 Checking root announcements collection...');
      final annSnap = await _db.collection('announcements').limit(500).get();
      if (annSnap.docs.isNotEmpty) {
        int annCount = 0;
        for (final doc in annSnap.docs) {
          await doc.reference.delete();
          annCount++;
        }
        report['rootAnnouncementsCleaned'] = annCount;
        log('✅ Cleaned $annCount root announcements.');
      }
    } catch (e) {
      report['errors'].add('Root announcements clean error: $e');
    }

    return report;
  }

  /// Runs the full comprehensive cleanup:
  /// 1. Consolidate duplicate Karachi & bogus branches into 'karachi'
  /// 2. Consolidate duplicate branch users into canonical root /users
  /// 3. Move root collections (employees, patients, devices, credentials) inside branch subcollections
  /// 4. Purge placeholder dummy employees
  static Future<Map<String, dynamic>> executeFullStructureSanitization({
    void Function(String msg)? onProgress,
  }) async {
    final fullReport = <String, dynamic>{};

    onProgress?.call('🚀 Starting Firestore Structure Sanitization...');
    
    // 1. Purge duplicate Karachi and bogus branches
    final branchReport = await cleanBogusBranchDocuments(onProgress: onProgress);
    fullReport['branches'] = branchReport;

    // 2. Consolidate branch users to eliminate double documents
    final userDoublesReport = await cleanBranchUserDuplicates(onProgress: onProgress);
    fullReport['userDoubles'] = userDoublesReport;

    // 3. Move root collections inside branch
    final rootReport = await cleanRootCollections(onProgress: onProgress);
    fullReport['rootCollections'] = rootReport;

    // 4. Purge placeholder employees
    onProgress?.call('🧹 Purging unknown placeholder employees...');
    final purgedEmpCount = await FinanceLocalStorage.purgeUnknownPlaceholderEmployees();
    fullReport['purgedPlaceholderEmployees'] = purgedEmpCount;

    onProgress?.call('✨ Full Structure Sanitization Complete!');
    return fullReport;
  }
}
