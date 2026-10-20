// lib/services/background_sync_service.dart
//
// Android background upload. Android runs a WorkManager job about every 15 minutes (the
// shortest period it allows) while the phone has a network, even when the app is closed.
//
// Hive must never be opened by two isolates at once: both would append to the same box files
// and corrupt them. So the job first asks the app's own isolate, if the app process is still
// alive, to run the upload pass and waits for it. Only when no app isolate exists (the app
// was closed or killed) does the job open the boxes itself, as the only isolate using them.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'donations_local_storage.dart';
import 'local_storage_service.dart';
import 'sync_service.dart';

class BackgroundSyncService {
  BackgroundSyncService._();

  static const String _taskName = 'gmwf_background_upload';
  static const String _mainIsolatePortName = 'gmwf_main_isolate_sync';
  static const String _jobOwnsHivePortName = 'gmwf_background_job_hive';
  // WorkManager stops a job after 10 minutes; finish well before that.
  static const Duration _passTimeout = Duration(minutes: 8);
  // When the job owns Hive (app closed), keep the pass short: an app started meanwhile waits
  // for it before opening its boxes.
  static const Duration _ownedPassTimeout = Duration(minutes: 2);

  static ReceivePort? _mainPort;

  /// Called once from main() on Android, after Firebase and Hive are ready. Registers this
  /// isolate as the one that owns Hive and schedules the periodic job.
  static Future<void> init(Function callbackDispatcher) async {
    if (kIsWeb || !Platform.isAndroid) return;
    _registerMainIsolate();
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('[BackgroundSync] scheduling failed: $e');
    }
  }

  /// The app isolate answers "run an upload pass" requests from the background job.
  static void _registerMainIsolate() {
    IsolateNameServer.removePortNameMapping(_mainIsolatePortName);
    _mainPort?.close();
    final port = ReceivePort();
    _mainPort = port;
    IsolateNameServer.registerPortWithName(port.sendPort, _mainIsolatePortName);
    port.listen((msg) async {
      if (msg is! SendPort) return;
      try {
        await SyncService().triggerUpload().timeout(_passTimeout);
      } catch (e) {
        debugPrint('[BackgroundSync] upload pass in app isolate failed: $e');
      }
      msg.send(true);
    });
  }

  /// Body of the WorkManager job (see backgroundSyncDispatcher in main.dart).
  static Future<bool> runJob({required void Function() registerHiveAdapters}) async {
    // 1. App process alive: let its isolate do the work (it already owns Hive).
    final appPort = IsolateNameServer.lookupPortByName(_mainIsolatePortName);
    if (appPort != null) {
      final reply = ReceivePort();
      try {
        appPort.send(reply.sendPort);
        await reply.first.timeout(_passTimeout + const Duration(seconds: 30));
        return true;
      } on TimeoutException {
        return true; // the app keeps going; the next job checks again
      } catch (e) {
        // A stale mapping from a killed process: fall through and upload here.
        debugPrint('[BackgroundSync] app isolate unreachable: $e');
        IsolateNameServer.removePortNameMapping(_mainIsolatePortName);
      } finally {
        reply.close();
      }
    }

    // 2. No app isolate: this isolate is the only Hive user. An app started meanwhile asks
    // here (waitForBackgroundJob) and is answered once the boxes are closed.
    final released = Completer<void>();
    final waiters = <SendPort>[];
    final ownerPort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_jobOwnsHivePortName);
    IsolateNameServer.registerPortWithName(ownerPort.sendPort, _jobOwnsHivePortName);
    ownerPort.listen((msg) {
      if (msg is! SendPort) return;
      if (released.isCompleted) {
        msg.send(true);
      } else {
        waiters.add(msg);
      }
    });
    try {
      return await _uploadOwningHive(registerHiveAdapters);
    } finally {
      IsolateNameServer.removePortNameMapping(_jobOwnsHivePortName);
      released.complete();
      for (final w in waiters) {
        w.send(true);
      }
      ownerPort.close();
    }
  }

  /// Called by the app on Android before it opens Hive: if a background job is uploading with
  /// its own Hive instance right now, wait (briefly) for it to close the boxes.
  static Future<void> waitForBackgroundJob() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final jobPort = IsolateNameServer.lookupPortByName(_jobOwnsHivePortName);
    if (jobPort == null) return;
    final reply = ReceivePort();
    try {
      jobPort.send(reply.sendPort);
      await reply.first.timeout(_ownedPassTimeout + const Duration(seconds: 15));
    } catch (_) {
      // Stale mapping or timeout: continue starting the app.
    } finally {
      reply.close();
    }
  }

  static Future<bool> _uploadOwningHive(void Function() registerHiveAdapters) async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (_) {
      // Already initialised in this process.
    }
    await Hive.initFlutter();
    registerHiveAdapters();

    // Only the boxes the uploader reads and writes; none of the app's start-up migrations,
    // purges or sweeps run here.
    for (final name in <String>{
      'app_settings',
      'app_flags',
      LocalStorageService.syncBox,
      LocalStorageService.deadLetterQueueBox,
      LocalStorageService.entriesBox,
      LocalStorageService.patientsBox,
      LocalStorageService.prescriptionsBox,
      LocalStorageService.dispensaryBox,
      LocalStorageService.stockBox,
      LocalStorageService.attendanceBox,
      LocalStorageService.usersBox,
      DonationsLocalStorage.donationsBox,
    }) {
      try {
        await LocalStorageService.openBoxSafe(name);
      } catch (e) {
        debugPrint('[BackgroundSync] could not open $name: $e');
      }
    }

    try {
      if (Hive.box(LocalStorageService.syncBox).isEmpty) return true;
      await SyncService().triggerUpload().timeout(_ownedPassTimeout);
      return true;
    } catch (e) {
      debugPrint('[BackgroundSync] background upload pass failed: $e');
      return false; // WorkManager retries with backoff
    } finally {
      // Flush and release the files before Android ends this process.
      try {
        await Hive.close();
      } catch (_) {}
    }
  }
}
