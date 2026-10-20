// lib/services/cloud/lan_firestore_gate.dart
//
// On a dispensary desk (doctor, dispenser, receptionist, ...) that is connected to the clinic's
// LAN server, only the server talks to Firestore. The desk sends everything to the server over
// the LAN and gets its data from the server.
//
// Screens have many direct Firestore calls (lookups, listeners, the odd write). Instead of
// relying on each of them checking the LAN state, this gate takes the Firestore SDK offline
// while the desk has a live server link: SDK reads and listeners answer from the local cache
// only (no reads billed, no traffic), and CloudDb (our REST writer) refuses writes. When the
// link drops for real, the SDK goes back online so the desk can work alone.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../realtime/lan_host_manager.dart';
import '../../realtime/lan_server.dart';
import '../../realtime/realtime_manager.dart';
import '../offline_auth_service.dart';
import 'cloud_db.dart';
import 'sync_log.dart';

class LanFirestoreGate {
  LanFirestoreGate._();

  /// True while this desk must not talk to Firestore (the LAN server does it).
  static bool get active => _active;
  static bool _active = false;

  static Timer? _timer;
  static DateTime? _linkSince;
  static String? _cachedRole;

  /// The link must hold this long before the SDK goes offline, so a flapping connection does
  /// not toggle it every few seconds. Going back online happens at once.
  static const Duration settle = Duration(seconds: 5);

  static void start() {
    if (_timer != null) return;
    unawaited(_loadRole());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(evaluate()));
    unawaited(evaluate());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    if (_active) unawaited(_setActive(false));
  }

  static Future<void> _loadRole() async {
    try {
      final user = await OfflineAuthService.getCachedUserData();
      _cachedRole = user?['role']?.toString();
    } catch (_) {}
  }

  /// Desk roles that only work on dispensary data. Admins, HQ, supervisors and the like keep
  /// their cloud views even on the LAN. (LocalStorageService.isDispensaryRole matches loose
  /// substrings such as 'rec' and 'doc', which would also catch 'director'.)
  @visibleForTesting
  static bool isDispensaryDeskRole(String? role) {
    final r = (role ?? '').toLowerCase().trim();
    if (r.isEmpty) return false;
    const exclude = ['admin', 'hq', 'supervisor', 'chairman', 'director', 'ceo', 'manager', 'owner', 'auditor'];
    if (exclude.any(r.contains)) return false;
    // Hybrid desks are routed by combined codes: rec+dis, doc+rec, doc+dis, doc+rec+dis.
    if (r.contains('+')) {
      final parts = r.split('+').map((p) => p.trim()).where((p) => p.isNotEmpty);
      if (parts.isNotEmpty && parts.every((p) => const {'rec', 'doc', 'dis'}.contains(p))) return true;
    }
    const desk = ['doctor', 'dispens', 'receptionist', 'pharmacist', 'nurse', 'physio', 'hybrid', 'clinic'];
    return desk.any(r.contains);
  }

  /// This PC is a dispensary desk with a live link to the LAN server, right now. Call sites
  /// check this before any Firestore read or write (no settle delay, unlike [active], so the
  /// calls made just after connecting are covered too).
  static bool get isLanDesk {
    if (LanServer.isRunning || LanHostManager.isHostRunning) return false;
    final rm = RealtimeManager();
    return rm.hasServerLink && isDispensaryDeskRole(rm.role ?? _cachedRole);
  }

  /// LAN event that carries a desk's Firestore write to the LAN server, which uploads it.
  static const String relayEvent = 'relay_cloud_write';

  /// Hands a write to the LAN server instead of Firestore (for writes that have no LAN event
  /// of their own: notifications, user preferences, ...). [docPath] is the full document path
  /// ('branches/karachi/notifications/abc'). FieldValue.serverTimestamp() values are sent as
  /// field names and set to the server's time on upload; other FieldValues (increments) are
  /// not supported here. Returns false when there is no server link to carry it.
  static bool relayWrite(String docPath, Map<String, dynamic> data, {bool merge = true, bool delete = false, String? branchId}) {
    final rm = RealtimeManager();
    if (!rm.hasServerLink) return false;
    final plain = <String, dynamic>{};
    final serverTimeKeys = <String>[];
    data.forEach((k, v) {
      if (v is FieldValue) {
        serverTimeKeys.add(k);
      } else if (v is Timestamp) {
        plain[k] = v.toDate().toIso8601String();
      } else if (v is DateTime) {
        plain[k] = v.toIso8601String();
      } else {
        plain[k] = v;
      }
    });
    final b = branchId ?? (docPath.startsWith('branches/') ? docPath.split('/')[1] : '');
    rm.sendMessage({
      'event_type': relayEvent,
      'branchId': b,
      'data': {
        'id': docPath, // stable id: repeated relays of one document collapse in the queue
        'path': docPath,
        'merge': merge,
        'delete': delete,
        'serverTimeKeys': serverTimeKeys,
        'fields': plain,
        'relayedAt': DateTime.now().toIso8601String(),
      },
    });
    return true;
  }

  /// Merges [data] into the document at [docPath]: through the LAN server on a dispensary desk,
  /// else straight to Firestore over REST (no hidden SDK queue). Errors are logged, not thrown:
  /// callers use it for background profile/preference syncs.
  static Future<void> mergeDoc(String docPath, Map<String, dynamic> data) async {
    try {
      if (isLanDesk && relayWrite(docPath, data)) return;
      await CloudDb.instance.doc(docPath).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[LanFirestoreGate] mergeDoc($docPath) skipped: $e');
    }
  }

  /// Fire-and-forget document write (merge set, or delete): through the LAN server on a
  /// dispensary desk, else to Firestore over REST.
  static void writeDoc(String docPath, Map<String, dynamic> data, {bool delete = false}) {
    if (isLanDesk && relayWrite(docPath, data, delete: delete)) return;
    final ref = CloudDb.instance.doc(docPath);
    unawaited((delete ? ref.delete() : ref.set(data, SetOptions(merge: true)))
        .catchError((Object e) => debugPrint('[LanFirestoreGate] writeDoc($docPath) skipped: $e')));
  }

  static Future<void> evaluate() async {
    final link = isLanDesk;

    if (!link) {
      _linkSince = null;
      if (_active) await _setActive(false);
      return;
    }
    _linkSince ??= DateTime.now();
    if (!_active && DateTime.now().difference(_linkSince!) >= settle) {
      await _setActive(true);
    }
  }

  static Future<void> _setActive(bool value) async {
    _active = value;
    try {
      if (value) {
        await FirebaseFirestore.instance.disableNetwork();
      } else {
        await FirebaseFirestore.instance.enableNetwork();
      }
      SyncLog.write(value
          ? 'LAN server link up: this desk stops talking to Firestore (the server uploads)'
          : 'No LAN server link: this desk uses Firestore directly again');
    } catch (e) {
      debugPrint('[LanFirestoreGate] ${value ? 'disable' : 'enable'}Network failed: $e');
    }
  }
}
