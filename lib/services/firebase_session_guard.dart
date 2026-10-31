// lib/services/firebase_session_guard.dart
//
// Firestore rules require request.auth != null, so every upload (madrassa logs,
// food tokens, donations, ...) is rejected while the app has no Firebase session.
// A session can be missing even though the user is "logged in": local-first,
// offline and Firestore-document logins open the app first and sign in to
// Firebase in the background, once. If that one attempt fails (phone offline at
// the time, slow app verification on Android), nothing tried again and the
// queue never uploaded. This guard restores the session whenever the device is
// online, then kicks the upload queue.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'offline_auth_service.dart';
import 'sync_service.dart';

class FirebaseSessionGuard {
  FirebaseSessionGuard._();

  static Timer? _timer;
  static StreamSubscription<List<ConnectivityResult>>? _connSub;
  static bool _running = false;
  static DateTime? _lastAttempt;

  /// Starts watching. Safe to call more than once.
  static void start() {
    if (_timer != null) return;
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(ensureSession(reason: 'network up'));
      }
    });
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(ensureSession(reason: 'periodic')));
    unawaited(ensureSession(reason: 'start'));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _connSub?.cancel();
    _connSub = null;
  }

  /// Signs back in with the cached credentials of the logged-in user (anonymous
  /// as a last resort) when there is no Firebase session. Returns true when a
  /// session exists afterwards.
  static Future<bool> ensureSession({String reason = ''}) async {
    if (Firebase.apps.isEmpty) return false; // Firebase never initialised
    if (FirebaseAuth.instance.currentUser != null) return true;
    if (_running) return false;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 45)) return false;
    _running = true;
    _lastAttempt = DateTime.now();
    try {
      // Logout deletes app_settings.user_data; never sign back in after that.
      if (!Hive.isBoxOpen('app_settings') || Hive.box('app_settings').get('user_data') == null) return false;
      final user = await OfflineAuthService.getCachedUserData();
      if (user == null) return false; // nobody logged in on this device

      final email = (user['email'] ?? '').toString().trim().toLowerCase();
      if (email.contains('@')) {
        String? password;
        for (final alias in [email, user['uid'], user['username'], user['usernameLower']]) {
          final a = (alias ?? '').toString().trim();
          if (a.isEmpty) continue;
          password = await OfflineAuthService.getStoredPassword(a);
          if (password != null && password.isNotEmpty) break;
        }
        if (password != null && password.isNotEmpty) {
          try {
            await FirebaseAuth.instance
                .signInWithEmailAndPassword(email: email, password: password)
                .timeout(const Duration(seconds: 30));
          } catch (e) {
            debugPrint('[FirebaseSessionGuard] email sign-in failed ($reason): $e');
          }
        }
      }

      if (FirebaseAuth.instance.currentUser == null) {
        try {
          await FirebaseAuth.instance.signInAnonymously().timeout(const Duration(seconds: 20));
        } catch (e) {
          debugPrint('[FirebaseSessionGuard] anonymous sign-in failed ($reason): $e');
        }
      }

      final ok = FirebaseAuth.instance.currentUser != null;
      if (ok) {
        debugPrint('[FirebaseSessionGuard] Firebase session restored ($reason) — uploading queue');
        unawaited(SyncService().triggerUpload());
      }
      return ok;
    } catch (e) {
      debugPrint('[FirebaseSessionGuard] ensureSession error: $e');
      return false;
    } finally {
      _running = false;
    }
  }
}
