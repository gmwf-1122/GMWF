import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/navigator_key.dart';
import '../widgets/app_feedback.dart';
import '../widgets/queue_doctor_dialog.dart';
import 'local_storage_service.dart';
import 'python_runner_service.dart';
import 'sync_service.dart';
import 'quota_service.dart';

class HiddenForceUploader {
  HiddenForceUploader._();
  static final HiddenForceUploader instance = HiddenForceUploader._();

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  void _notify(void Function(BuildContext ctx) callback) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      callback(ctx);
    }
  }

  /// Triggered via Ctrl+Shift+U or Auto-Heal & Flush.
  /// Exports all pending records, runs the fast Python Firestore Admin SDK uploader,
  /// displays real-time start and completion notifications, and updates local cache.
  Future<void> runSilentForceUpload() async {
    if (_isUploading) {
      _notify((ctx) {
        AppFeedback.showWarning(
          ctx,
          'Force Upload in Progress',
          subtitle: 'Cloud sync is actively committing batches. Please wait...',
          duration: const Duration(seconds: 3),
        );
      });
      return;
    }
    _isUploading = true;

    try {
      QuotaService.resetState();
      try {
        await SyncService().sweepAllPendingLocalData(force: true);
      } catch (e) {
        debugPrint('[HiddenForceUploader] Pre-upload sweep notice: $e');
      }
      try {
        await LocalStorageService.purgePhantomUnknownTokens();
        await LocalStorageService.purgeBloatedSyncQueue();
      } catch (e) {
        debugPrint('[HiddenForceUploader] Pre-upload purge notice: $e');
      }

      if (!Hive.isBoxOpen(LocalStorageService.syncBox)) {
        await Hive.openBox(LocalStorageService.syncBox);
      }
      final queueBox = Hive.box(LocalStorageService.syncBox);
      final totalPending = queueBox.length;

      // If the queue is already empty
      if (totalPending == 0) {
        _notify((ctx) {
          AppFeedback.showSuccess(
            ctx,
            'Sync Queue Clean',
            subtitle: '0 pending items in local queue. All data is synchronized.',
            duration: const Duration(seconds: 3),
          );
        });
        unawaited(SyncService().triggerUpload(force: true));
        return;
      }

      // On mobile devices (Android / iOS), run native Dart Firestore high-speed forced upload
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        _notify((ctx) {
          AppFeedback.showInfo(
            ctx,
            'Mobile Force Upload Started',
            subtitle: 'Uploading $totalPending records directly to Cloud Firestore...',
            duration: const Duration(seconds: 4),
          );
        });
        await SyncService().sweepAllPendingLocalData(force: true);
        await SyncService().triggerUpload(force: true);
        final remaining = Hive.isBoxOpen(LocalStorageService.syncBox)
            ? Hive.box(LocalStorageService.syncBox).length
            : 0;
        _notify((ctx) {
          if (remaining == 0) {
            AppFeedback.showSuccess(
              ctx,
              'All Data Synchronized',
              subtitle: 'Local queue successfully uploaded to Cloud Firestore.',
              duration: const Duration(seconds: 3),
            );
          } else {
            AppFeedback.showInfo(
              ctx,
              'Sync Pass Finished',
              subtitle: '$remaining item(s) remain in offline queue.',
              duration: const Duration(seconds: 3),
              actionLabel: 'Details',
              onAction: () => QueueDoctorDialog.show(ctx),
            );
          }
        });
        return;
      }

      // 1. Initial Notification: Let user know Ctrl+Shift+U was received and started!
      _notify((ctx) {
        AppFeedback.showInfo(
          ctx,
          'Force Upload Started (Ctrl+Shift+U)',
          subtitle: 'Exporting $totalPending records to high-speed cloud engine...',
          duration: const Duration(seconds: 4),
        );
      });

      // 2. Export pending items into temporary JSON
      final items = <Map<String, dynamic>>[];
      for (final key in queueBox.keys) {
        final val = queueBox.get(key);
        if (val is Map) {
          final itemMap = Map<String, dynamic>.from(val);
          itemMap['_queueKey'] = key.toString();
          if (itemMap['data'] is Map) {
            itemMap['data'] = Map<String, dynamic>.from(itemMap['data'] as Map);
          }
          items.add(itemMap);
        }
      }

      final appDir = await getApplicationSupportDirectory();
      final exportFile = File(p.join(appDir.path, '.hidden_queue_export.json'));
      final syncedKeysFile = File(p.join(appDir.path, '.hidden_synced_keys.json'));

      if (await syncedKeysFile.exists()) {
        try {
          await syncedKeysFile.delete();
        } catch (_) {}
      }

      await exportFile.writeAsString(jsonEncode(items), flush: true);

      // 3. Discover Python interpreter & scripts
      final scriptsDir = await PythonRunnerService.instance.resolveScriptsDirectory();

      final scriptCandidates = [
        r'E:\GMWF\gmwf\scripts\hidden_cloud_sync.py',
        p.join(scriptsDir, 'hidden_cloud_sync.py'),
        p.join(Directory.current.path, 'scripts', 'hidden_cloud_sync.py'),
      ];

      String? targetScript;
      for (final cand in scriptCandidates) {
        if (await File(cand).exists()) {
          targetScript = cand;
          break;
        }
      }

      final credsCandidates = [
        r'E:\GMWF\gmwf\scripts\serviceAccountKey.json',
        p.join(scriptsDir, 'serviceAccountKey.json'),
        p.join(Directory.current.path, 'scripts', 'serviceAccountKey.json'),
      ];

      String? targetCreds;
      for (final cand in credsCandidates) {
        if (await File(cand).exists()) {
          targetCreds = cand;
          break;
        }
      }

      // Check python candidates that actually have firebase_admin installed
      final candidatePythons = <String>[
        r'E:\GMWF\gmwf\Installer\python-3.12.10-embed-amd64\python.exe',
        p.join(Directory.current.path, 'Installer', 'python-3.12.10-embed-amd64', 'python.exe'),
        p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Python', 'bin', 'python.exe'),
      ];
      final detectedPy = await PythonRunnerService.instance.resolvePythonExecutable();
      if (detectedPy != null) candidatePythons.add(detectedPy);

      String? pythonExe;
      for (final py in candidatePythons) {
        if (await File(py).exists()) {
          try {
            final test = await Process.run(py, ['-c', 'import firebase_admin']).timeout(const Duration(seconds: 2));
            if (test.exitCode == 0) {
              pythonExe = py;
              break;
            }
          } catch (_) {}
        }
      }

      if (pythonExe == null || targetScript == null || targetCreds == null) {
        debugPrint('[HiddenForceUploader] Python firebase_admin engine unavailable. Running native Dart cloud sync.');
        _notify((ctx) {
          AppFeedback.showInfo(
            ctx,
            'Syncing via Native Engine',
            subtitle: 'Processing $totalPending records directly to Cloud Firestore...',
            duration: const Duration(seconds: 4),
          );
        });
        await SyncService().triggerUpload(force: true);
        return;
      }

      // 4. Run Python process
      final result = await Process.run(
        pythonExe,
        [
          targetScript,
          '--export',
          exportFile.path,
          '--creds',
          targetCreds,
          '--out',
          syncedKeysFile.path,
        ],
      );

      debugPrint('[HiddenForceUploader] Python exit code: ${result.exitCode}');

      // 5. Parse result and purge synced items from sync_queue Hive box
      int committedCount = 0;
      Map<String, dynamic> breakdown = {};
      double durationSec = 0.0;

      if (await syncedKeysFile.exists()) {
        try {
          final content = await syncedKeysFile.readAsString();
          final parsed = jsonDecode(content);
          List<dynamic> keysToDelete = [];

          if (parsed is List) {
            keysToDelete = parsed;
            committedCount = parsed.length;
          } else if (parsed is Map) {
            keysToDelete = (parsed['syncedKeys'] as List<dynamic>?) ?? [];
            committedCount = (parsed['totalCommitted'] as int?) ?? keysToDelete.length;
            breakdown = (parsed['breakdown'] as Map<String, dynamic>?) ?? {};
            durationSec = (parsed['durationSeconds'] as num?)?.toDouble() ?? 0.0;
          }

          final eBox = Hive.isBoxOpen(LocalStorageService.entriesBox)
              ? Hive.box(LocalStorageService.entriesBox)
              : null;

          for (final k in keysToDelete) {
            final val = queueBox.get(k) ?? (int.tryParse(k.toString()) != null ? queueBox.get(int.parse(k.toString())) : null);
            if (val is Map && eBox != null) {
              final type = val['type']?.toString();
              if (type == 'save_entry' || type == 'save_prescription') {
                final b = (val['branchId'] ?? val['data']?['branchId'] ?? '').toString().toLowerCase().trim();
                final s = (val['serial'] ?? val['data']?['serial'] ?? '').toString().toUpperCase().trim();
                final localKey = '$b-$s';
                final existing = eBox.get(localKey) ?? eBox.get(s);
                if (existing is Map) {
                  final upd = Map<String, dynamic>.from(existing);
                  upd['synced'] = true;
                  upd['syncStatus'] = 'synced';
                  upd['pendingSync'] = false;
                  await eBox.put(localKey, upd);
                }
              }
            }
            await queueBox.delete(k);
            if (int.tryParse(k.toString()) != null) {
              await queueBox.delete(int.parse(k.toString()));
            }
          }
          await queueBox.flush();
          if (eBox != null) await eBox.flush();
        } catch (e) {
          debugPrint('[HiddenForceUploader] Key purge error: $e');
        }
      }

      // Cleanup temp files
      try {
        if (await exportFile.exists()) await exportFile.delete();
        if (await syncedKeysFile.exists()) await syncedKeysFile.delete();
      } catch (_) {}

      // 6. Display Completion Summary Toast
      final remaining = queueBox.length;

      if (committedCount > 0) {
        final pCount = breakdown['patients'] ?? 0;
        final dCount = (breakdown['patient_deletes'] ?? 0) + (breakdown['dispensary_deletes'] ?? 0) + (breakdown['prescription_deletes'] ?? 0);
        final mCount = breakdown['madrassa'] ?? 0;
        final aCount = breakdown['attendance'] ?? 0;

        final summaryParts = <String>[];
        if (pCount > 0) summaryParts.add('Patients: $pCount');
        if (dCount > 0) summaryParts.add('Deletions: $dCount');
        if (mCount > 0) summaryParts.add('Madrassa: $mCount');
        if (aCount > 0) summaryParts.add('Attendance: $aCount');
        if (summaryParts.isEmpty) summaryParts.add('Records: $committedCount');
        if (durationSec > 0) summaryParts.add('${durationSec}s');

        _notify((ctx) {
          AppFeedback.showSuccess(
            ctx,
            'Force Upload Complete ($committedCount items uploaded)',
            subtitle: '${summaryParts.join(' • ')} • Remaining: $remaining',
            duration: const Duration(seconds: 6),
            actionLabel: 'Details',
            onAction: () => QueueDoctorDialog.show(ctx),
          );
        });
      } else if (result.exitCode != 0) {
        final errText = result.stderr.toString().isNotEmpty
            ? result.stderr.toString().trim().split('\n').last
            : 'Exit code ${result.exitCode}';
        debugPrint('[HiddenForceUploader] Python notice: $errText. Seamlessly uploading via native Dart engine.');
        _notify((ctx) {
          AppFeedback.showInfo(
            ctx,
            'Syncing via Native Engine',
            subtitle: 'Uploading records directly via native cloud engine...',
            duration: const Duration(seconds: 3),
          );
        });
        await SyncService().triggerUpload(force: true);
        final remaining = Hive.isBoxOpen(LocalStorageService.syncBox)
            ? Hive.box(LocalStorageService.syncBox).length
            : 0;
        _notify((ctx) {
          if (remaining == 0) {
            AppFeedback.showSuccess(
              ctx,
              'All Data Synchronized',
              subtitle: 'Records successfully uploaded to Cloud Firestore.',
              duration: const Duration(seconds: 4),
            );
          } else {
            AppFeedback.showInfo(
              ctx,
              'Sync Pass Finished',
              subtitle: '$remaining item(s) remain in offline queue.',
              duration: const Duration(seconds: 3),
              actionLabel: 'Details',
              onAction: () => QueueDoctorDialog.show(ctx),
            );
          }
        });
        return;
      } else {
        _notify((ctx) {
          AppFeedback.showInfo(
            ctx,
            'Force Upload Finished',
            subtitle: 'Queue remaining: $remaining items.',
            duration: const Duration(seconds: 4),
            actionLabel: 'Doctor',
            onAction: () => QueueDoctorDialog.show(ctx),
          );
        });
      }

      // 7. Trigger Dart sync pass to refresh local markers
      unawaited(SyncService().triggerUpload(force: true));
    } catch (e) {
      debugPrint('[HiddenForceUploader] Exception: $e');
      _notify((ctx) {
        AppFeedback.showError(
          ctx,
          'Force Upload Error',
          subtitle: e.toString(),
          duration: const Duration(seconds: 5),
          actionLabel: 'Doctor',
          onAction: () => QueueDoctorDialog.show(ctx),
        );
      });
      unawaited(SyncService().triggerUpload(force: true));
    } finally {
      _isUploading = false;
    }
  }
}
