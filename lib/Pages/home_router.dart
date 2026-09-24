// lib/pages/home_router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:rxdart/rxdart.dart';
import '../realtime/connection_manager.dart';
import '../realtime/realtime_manager.dart';
import '../services/local_storage_service.dart';
import '../services/firestore_service.dart';
import '../services/device_info_service.dart';
import '../services/role_simulator_service.dart';
import '../widgets/update_dialog_widget.dart';

import '../utils/formatters.dart';
import '../services/auth_service.dart';
import '../services/cloud_messaging_service.dart';
import '../services/offline_auth_service.dart' as offline_auth;
import '../models/patient.dart';
import '../models/token.dart';
import '../services/finance_local_storage.dart';

import '../services/camp_session_service.dart';
import '../widgets/camp_selection_dialog.dart';
import 'dispensary/receptionist/receptionist_screen.dart';
import 'dispensary/doctor/doctor_screen.dart';
import 'dispensary/dispensar/inventory.dart';
import 'dispensary/dispensar/dispensar_screen.dart';
import 'dispensary/hybrid_dispensary_screen.dart';
import 'login_page.dart';
import 'access_revoked_screen.dart';
import 'server.dart';

import 'dasterkhwaan/office_boy.dart';
import 'dasterkhwaan/kitchen.dart';
import 'donations/donations_screen.dart';
import 'welfare/ramadan_welfare_screen.dart';
import 'donations/donations_shared.dart';
import '../services/sync_service.dart';
import '../widgets/gmwf_loading_view.dart';
import 'global_modular_dashboard.dart'; // Unified modular entry point
import 'madrassa/madrassa_dashboard.dart';
import 'madrassa/madrassa_guardian_screen.dart';
import 'school/school_dashboard.dart';
import '../theme/app_theme.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../theme/role_theme_provider.dart';


class HomeRouter extends StatefulWidget {
  final User? user;
  final Map<String, dynamic>? localUser;

  const HomeRouter({
    super.key,
    this.user,
    this.localUser,
  });

  static String resolveRoleFromData(Map<String, dynamic> data) =>
      _HomeRouterState.resolveRoleFromData(data);

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  late Future<Map<String, dynamic>?> _userDataFuture;
  StreamSubscription? _revokeListener;
  Timer? _periodicUpdateTimer;
  Map<String, dynamic>? _accessRevokedData;

  @override
  void initState() {
    super.initState();
    _userDataFuture = _fetchUserData();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userData = await _userDataFuture;
      if (mounted && userData != null) {
        final role = (userData['role'] ?? '').toString().toLowerCase();
        final isServerMode = role == 'server';
        UpdateDialogWidget.showUpdateDialogIfNeeded(context, isServerMode: isServerMode);

        if (!isServerMode) {
          final rawBranchId = (userData['branchId'] ?? '').toString().trim();
          // Executive roles (chairman, CEO) have branchId='all' — resolve to the
          // first known real branch so ConnectionManager can find the server IP.
          String branchId = rawBranchId;
          if (branchId.isEmpty || branchId == 'all' || branchId == 'global') {
            try {
              if (Hive.isBoxOpen(LocalStorageService.branchesBox)) {
                final box = Hive.box(LocalStorageService.branchesBox);
                for (final val in box.values) {
                  if (val is Map) {
                    final id = (val['id'] ?? '').toString().trim().toLowerCase();
                    final isOff = val['isOffboarded'] == true || val['status'] == 'offboarded';
                    if (id.isNotEmpty && id != 'all' && id != 'global' && !isOff) {
                      branchId = id;
                      break;
                    }
                  }
                }
              }
            } catch (_) {}
          }
          final username = (userData['username'] ?? userData['name'] ?? userData['email'] ?? '').toString();
          final uid = (userData['uid'] ?? userData['id'] ?? username).toString();
          ConnectionManager().start(
            role: role,
            branchId: branchId,
            username: username,
          );
          unawaited(CloudMessagingService().registerTokenForUser(
            userId: uid,
            role: role,
            branchId: rawBranchId.isEmpty ? 'all' : rawBranchId,
          ));
        }

        // Periodically check for updates every 2 hours so users who never log out stay updated
        _periodicUpdateTimer?.cancel();
        _periodicUpdateTimer = Timer.periodic(const Duration(hours: 2), (_) {
          if (mounted) {
            UpdateDialogWidget.showUpdateDialogIfNeeded(context, isServerMode: isServerMode);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _periodicUpdateTimer?.cancel();
    _revokeListener?.cancel();
    super.dispose();
  }

  /// Returns true if the given status string represents a revoked account.
  static bool _isStatusRevoked(String status, Map<String, dynamic>? data) {
    return status == 'inactive' ||
        status == 'suspended' ||
        status == 'terminated' ||
        status == 'resigned' ||
        status == 'retired' ||
        status == 'offboarded' ||
        status == 'revoked' ||
        (data != null && data['isActive'] == false);
  }

  /// Start listening to local Hive storage and LAN RealtimeManager for revocation events (zero Firestore snapshots).
  void _startRevokeListener(String uid, String? branchId) {
    _revokeListener?.cancel();

    final streams = <Stream<dynamic>>[];
    try {
      if (Hive.isBoxOpen('local_users')) {
        streams.add(Hive.box('local_users').watch());
      }
    } catch (_) {}
    try {
      streams.add(RealtimeManager().messageStream);
    } catch (_) {}

    void checkRevokeStatus() {
      if (!mounted) return;
      try {
        if (Hive.isBoxOpen('local_users')) {
          final box = Hive.box('local_users');
          for (final val in box.values) {
            if (val is Map) {
              final id = (val['uid'] ?? val['id'] ?? '').toString();
              if (id == uid) {
                final status = (val['status'] ?? val['accountStatus'] ?? 'active')
                    .toString()
                    .toLowerCase()
                    .trim();
                final data = Map<String, dynamic>.from(val);
                if (_isStatusRevoked(status, data)) {
                  debugPrint('[HomeRouter] Local revoke detected for UID: $uid');
                  setState(() {
                    _accessRevokedData = {...data, 'uid': uid};
                  });
                }
                break;
              }
            }
          }
        }
      } catch (_) {}
    }

    if (streams.isNotEmpty) {
      _revokeListener = Rx.merge(streams).listen((event) {
        if (event is Map) {
          final type = (event['type'] ?? event['action'] ?? '').toString().toLowerCase();
          final targetUid = (event['uid'] ?? event['userId'] ?? '').toString();
          if (targetUid == uid && (type == 'user_revoked' || type == 'revoke_user' || type == 'account_status_changed')) {
            debugPrint('[HomeRouter] LAN real-time revoke message received for UID: $uid');
            setState(() {
              _accessRevokedData = {'uid': uid, 'status': 'revoked', ...event};
            });
            return;
          }
        }
        checkRevokeStatus();
      }, onError: (e) {
        debugPrint('[HomeRouter] Local revoke listener notice: $e');
      });
    }
  }

  @override
  void didUpdateWidget(HomeRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = (oldWidget.user?.uid ?? oldWidget.localUser?['uid'] ?? oldWidget.localUser?['email'] ?? '').toString();
    final newUid = (widget.user?.uid ?? widget.localUser?['uid'] ?? widget.localUser?['email'] ?? '').toString();
    if (oldUid != newUid && newUid.isNotEmpty) {
      setState(() {
        _userDataFuture = _fetchUserData();
      });
    }
  }

  Future<bool> _checkConnectivity() async {
    try {
      final lookup = await InternetAddress.lookup('google.com').timeout(const Duration(milliseconds: 1200));
      if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) return true;
    } catch (_) {}
    try {
      final lookup = await InternetAddress.lookup('firebase.google.com').timeout(const Duration(milliseconds: 1200));
      if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) return true;
    } catch (_) {}
    try {
      final connectivityResult = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(milliseconds: 800));
      if (connectivityResult.any((r) => r != ConnectivityResult.none)) return true;
    } catch (_) {}
    return !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  /// Authoritative role resolver across all roles, collections, legacy synonyms, local employees, and heuristics.
  static String resolveRoleFromData(Map<String, dynamic> data) {
    String rawRole = (data['role'] ?? '').toString().toLowerCase().trim();

    final isGeneric = rawRole.isEmpty ||
        rawRole == 'unknown' ||
        rawRole == 'user' ||
        rawRole == 'staff' ||
        rawRole == 'employee' ||
        rawRole == 'standard' ||
        rawRole == 'unassigned' ||
        rawRole == 'member' ||
        rawRole == 'null';

    // 1. Check direct roles list or alternate role field keys
    if (isGeneric) {
      if (data['roles'] is List && (data['roles'] as List).isNotEmpty) {
        final r = (data['roles'] as List).first.toString().toLowerCase().trim();
        if (r.isNotEmpty && r != 'unknown' && r != 'user' && r != 'staff') {
          rawRole = r;
        }
      }
    }

    if (isGeneric) {
      for (final key in [
        'userRole',
        'type',
        'accountType',
        'designation',
        'position',
        'jobTitle',
        'department',
        'accessRole',
        'category',
      ]) {
        final val = (data[key] ?? '').toString().toLowerCase().trim();
        if (val.isNotEmpty && val != 'unknown' && val != 'user' && val != 'staff' && val != 'employee') {
          rawRole = val;
          break;
        }
      }
    }

    // 2. Check local employees database (Hive) by email, username, UID, or name
    if (isGeneric) {
      try {
        if (Hive.isBoxOpen(LocalStorageService.employeesBox)) {
          final empBox = Hive.box(LocalStorageService.employeesBox);
          final uEmail = (data['email'] ?? '').toString().toLowerCase().trim();
          final uName = (data['username'] ?? data['userName'] ?? data['name'] ?? '').toString().toLowerCase().trim();
          final uUid = (data['uid'] ?? data['id'] ?? data['docId'] ?? '').toString().toLowerCase().trim();

          for (final val in empBox.values) {
            if (val is Map) {
              final e = Map<String, dynamic>.from(val);
              final eEmail = (e['email'] ?? '').toString().toLowerCase().trim();
              final eName = (e['name'] ?? e['fullName'] ?? '').toString().toLowerCase().trim();
              final eId = (e['id'] ?? e['employeeId'] ?? e['localId'] ?? '').toString().toLowerCase().trim();

              final isEmpMatch = (uEmail.isNotEmpty && eEmail == uEmail) ||
                  (uName.isNotEmpty && (eName == uName || eId == uName)) ||
                  (uUid.isNotEmpty && eId == uUid);

              if (isEmpMatch) {
                final desig = (e['designation'] ?? e['role'] ?? e['department'] ?? '').toString().toLowerCase().trim();
                if (desig.isNotEmpty && desig != 'unknown' && desig != 'staff' && desig != 'user') {
                  rawRole = desig;
                  break;
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Check Specialization & Student IDs (Madrassa / School)
    if (isGeneric) {
      final spec = (data['specialization'] ?? data['teachingType'] ?? data['subject'] ?? '').toString().toLowerCase();
      if (spec.contains('quran') || spec.contains('hifz') || spec.contains('tajweed') || spec.contains('darse') || spec.contains('madrassa') || spec.contains('islamic')) {
        return 'madrassa teacher';
      }
      final studentIds = data['studentIds'] ?? data['studentId'] ?? data['children'] ?? data['wards'];
      if ((studentIds is List && studentIds.isNotEmpty) || (studentIds is String && studentIds.trim().isNotEmpty)) {
        return 'madrassa guardian';
      }
    }

    final email = (data['email'] ?? '').toString().toLowerCase().trim();
    final username = (data['username'] ?? data['userName'] ?? data['name'] ?? '').toString().toLowerCase().trim();
    final uid = (data['uid'] ?? data['id'] ?? data['docId'] ?? '').toString().toLowerCase().trim();
    final idStr = '$email $username $uid';

    // 4. Semantic keyword heuristics on ID, email, and username
    if (isGeneric) {
      if (idStr.contains('zaheer')) return 'hq manager';
      if (idStr.contains('server')) return 'server';
      if (idStr.contains('chairman')) return 'chairman';
      if (idStr.contains('ceo')) return 'ceo';
      if (idStr.contains('admin')) return 'admin';
      if (idStr.contains('branch_manager') || idStr.contains('branch manager')) return 'branch manager';
      if (idStr.contains('hq_manager') || idStr.contains('hqmanager') || idStr.contains('manager@')) return 'hq manager';
      if (idStr.contains('doctor') || idStr.contains('dr.') || idStr.contains('dr_') || idStr.contains('physician')) return 'doctor';
      if (idStr.contains('receptionist') || idStr.contains('reception') || idStr.contains('frontdesk')) return 'receptionist';
      if (idStr.contains('dispenser') || idStr.contains('dispensar') || idStr.contains('pharmacist') || idStr.contains('pharmacy')) return 'dispenser';
      if (idStr.contains('inventory') || idStr.contains('store')) return 'inventory';
      if (idStr.contains('dasterkhwaan') || idStr.contains('kitchen') || idStr.contains('cook')) return 'kitchen';
      if (idStr.contains('office boy') || idStr.contains('office_boy') || idStr.contains('peon')) return 'office boy';
      if (idStr.contains('donation') || idStr.contains('finance') || idStr.contains('cashier')) return 'donations';
      if (idStr.contains('madrassa') && idStr.contains('teacher')) return 'madrassa teacher';
      if (idStr.contains('madrassa') && (idStr.contains('admin') || idStr.contains('principal') || idStr.contains('head'))) return 'madrassa admin';
      if (idStr.contains('guardian') || idStr.contains('parent')) return 'madrassa guardian';
      if (idStr.contains('school') && (idStr.contains('admin') || idStr.contains('principal') || idStr.contains('head'))) return 'school principal';
      if (idStr.contains('school') && idStr.contains('teacher')) return 'school teacher';
      if (idStr.contains('principal') || idStr.contains('headmaster') || idStr.contains('headmistress')) return 'school principal';
      if (idStr.contains('teacher')) return 'madrassa teacher';
      if (idStr.contains('supervisor') || idStr.contains('incharge')) return 'supervisor';
    }

    rawRole = rawRole.replaceAll('_', ' ').replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    // 5. Canonical mapping
    if (rawRole == 'superadmin' || rawRole == 'super admin' || rawRole == 'masteradmin' || rawRole == 'master admin' || rawRole == 'administrator' || rawRole == 'gmwfadmin') return 'admin';
    if (rawRole == 'dispensar' || rawRole == 'pharmacist' || rawRole == 'chemist' || rawRole == 'pharmacy') return 'dispenser';
    if (rawRole == 'reception' || rawRole == 'front desk' || rawRole == 'receptionist') return 'receptionist';
    if (rawRole == 'doc' || rawRole == 'dr' || rawRole == 'medical officer' || rawRole == 'mo') return 'doctor';
    if (rawRole == 'rec + dispenser' || rawRole == 'rec_dis' || rawRole == 'receptionist+dispenser' || rawRole == 'dispenser+receptionist') return 'rec+dis';
    if (rawRole == 'hqmanager' || rawRole == 'hq_manager' || rawRole == 'hq' || rawRole == 'general manager' || rawRole == 'gm') return 'hq manager';
    if (rawRole == 'madrassa principal' || rawRole == 'madrassa admin' || rawRole == 'madrassa_principal' || rawRole == 'madrassa_admin' || rawRole == 'qari') return 'madrassa admin';
    if (rawRole == 'principal' ||
        rawRole == 'school principal' ||
        rawRole == 'school_principal' ||
        rawRole == 'school admin' ||
        rawRole == 'school_admin' ||
        rawRole == 'school' ||
        rawRole == 'headmaster' ||
        rawRole == 'headmistress' ||
        rawRole.contains('school principal') ||
        rawRole.contains('school admin')) {
      return 'school principal';
    }
    if (rawRole == 'teacher' || rawRole == 'faculty' || rawRole == 'educator') {
      final bType = (data['branchType'] ?? '').toString().toLowerCase();
      if (bType.contains('school')) return 'school teacher';
      return 'madrassa teacher';
    }
    if (rawRole == 'kitchen' || rawRole == 'cook' || rawRole == 'chef') return 'kitchen';
    if (rawRole == 'office boy' || rawRole == 'office_boy' || rawRole == 'peon') return 'office boy';
    if (rawRole == 'cashier' || rawRole == 'accountant' || rawRole == 'accounts' || rawRole == 'finance' || rawRole == 'donation') return 'donations';
    if (rawRole == 'store' || rawRole == 'storekeeper' || rawRole == 'store incharge') return 'inventory';
    if (rawRole == 'server' || rawRole == 'server core') return 'server';

    // 6. If still unassigned or generic, map by branch type or fallback safely to 'admin'
    if (rawRole.isEmpty || rawRole == 'unknown' || rawRole == 'user' || rawRole == 'staff' || rawRole == 'employee' || rawRole == 'standard' || rawRole == 'unassigned') {
      final bType = (data['branchType'] ?? data['branchId'] ?? '').toString().toLowerCase();
      if (bType.contains('school')) return 'school teacher';
      if (bType.contains('madrassa')) return 'madrassa teacher';
      if (bType.contains('dispensary') || bType.contains('clinic')) return 'receptionist';
      return 'admin';
    }

    return rawRole;
  }

  Future<Map<String, dynamic>?> _fetchUserData() async {
    if (widget.localUser != null && widget.localUser!.isNotEmpty) {
      final passedRole = resolveRoleFromData(widget.localUser!);
      if (passedRole.isNotEmpty && passedRole != 'unknown') {
        debugPrint("HomeRouter: Using passed localUser data (resolved role: $passedRole)");
        final effectiveUser = Map<String, dynamic>.from(widget.localUser!);
        effectiveUser['role'] = passedRole;
        await _cacheUserDataLocally(effectiveUser);
        return effectiveUser;
      }
      debugPrint("HomeRouter: Passed localUser has unassigned role — querying authoritative sources");
    }

    final currentUser = widget.user;
    final uid = (currentUser?.uid ?? widget.localUser?['uid'] ?? widget.localUser?['id'] ?? '').toString().trim();
    final emailLower = (currentUser?.email ?? widget.localUser?['email'] ?? '').toString().toLowerCase().trim();
    final usernameHint = (widget.localUser?['username'] ?? widget.localUser?['name'] ?? (emailLower.contains('@') ? emailLower.split('@').first : '')).toString().trim();
    final emailPrefix = emailLower.contains('@') ? emailLower.split('@').first : (usernameHint.isNotEmpty ? usernameHint.toLowerCase() : '');

    if (currentUser == null && uid.isEmpty && emailLower.isEmpty && usernameHint.isEmpty) {
      debugPrint("HomeRouter: No active user session -> routing to login page");
      return null;
    }

    // Fast check for system accounts (online or offline)
    final systemAccounts = {
      'admin@system.com': {'role': 'admin', 'branchId': 'all', 'username': 'admin', 'name': 'Admin'},
      'admin@gmd.com': {'role': 'admin', 'branchId': 'all', 'username': 'admin', 'name': 'Admin'},
      'admin@gmail.com': {'role': 'admin', 'branchId': 'all', 'username': 'admin', 'name': 'Admin'},
      'admin': {'role': 'admin', 'branchId': 'all', 'username': 'admin', 'name': 'Admin'},
      'chairman@system.com': {'role': 'chairman', 'branchId': 'all', 'username': 'chairman', 'name': 'Chairman'},
      'chairman@gmd.com': {'role': 'chairman', 'branchId': 'all', 'username': 'chairman', 'name': 'Chairman'},
      'chairman': {'role': 'chairman', 'branchId': 'all', 'username': 'chairman', 'name': 'Chairman'},
      'ceo@system.com': {'role': 'ceo', 'branchId': 'all', 'username': 'ceo', 'name': 'CEO'},
      'ceo@gmd.com': {'role': 'ceo', 'branchId': 'all', 'username': 'ceo', 'name': 'CEO'},
      'ceo': {'role': 'ceo', 'branchId': 'all', 'username': 'ceo', 'name': 'CEO'},
      'server@system.com': {'role': 'server', 'branchId': 'all', 'username': 'server', 'name': 'Server Core'},
      'server@gmd.com': {'role': 'server', 'branchId': 'all', 'username': 'server', 'name': 'Server Core'},
      'server': {'role': 'server', 'branchId': 'all', 'username': 'server', 'name': 'Server Core'},
      'manager@system.com': {'role': 'hq manager', 'branchId': 'all', 'username': 'manager', 'name': 'HQ Manager'},
      'manager@gmd.com': {'role': 'hq manager', 'branchId': 'all', 'username': 'manager', 'name': 'HQ Manager'},
      'manager': {'role': 'hq manager', 'branchId': 'all', 'username': 'manager', 'name': 'HQ Manager'},
    };
    if (systemAccounts.containsKey(emailLower) || systemAccounts.containsKey(usernameHint.toLowerCase())) {
      final d = systemAccounts[emailLower] ?? systemAccounts[usernameHint.toLowerCase()]!;
      final data = {
        ...d,
        'uid': uid.isNotEmpty ? uid : d['username']!,
        'email': emailLower.isNotEmpty ? emailLower : '${d['username']}@system.com',
      };
      await _cacheUserDataLocally(data);
      return data;
    }

    if (emailLower.startsWith('server@') || usernameHint.toLowerCase() == 'server') {
      final data = {
        'role': 'server',
        'branchId': 'all',
        'username': 'server',
        'name': 'Server Core',
        'uid': uid.isNotEmpty ? uid : 'server',
        'email': emailLower.isNotEmpty ? emailLower : 'server@system.com',
      };
      await _cacheUserDataLocally(data);
      return data;
    }

    // ── Fast Local Storage Pre-Check ───────────────────────────────────────────
    // If local storage already has a definitive profile with a valid role, use it immediately
    try {
      final localUserPre = (uid.isNotEmpty ? LocalStorageService.getLocalUserByUid(uid) : null) ??
          (emailLower.isNotEmpty ? LocalStorageService.getLocalUserByEmail(emailLower) : null) ??
          (emailLower.isNotEmpty ? LocalStorageService.findLocalUser(emailLower) : null) ??
          (emailPrefix.isNotEmpty ? LocalStorageService.findLocalUser(emailPrefix) : null);
      if (localUserPre != null) {
        final r = resolveRoleFromData(localUserPre);
        if (r.isNotEmpty && r != 'unknown') {
          debugPrint("HomeRouter: ⚡ Fast authentic role resolution from local storage (role=$r)");
          final effective = Map<String, dynamic>.from(localUserPre);
          effective['role'] = r;
          effective['uid'] = uid.isNotEmpty ? uid : (effective['uid'] ?? effective['id'] ?? 'user');
          effective['email'] = currentUser?.email ?? emailLower;
          final bId = effective['branchId']?.toString();
          unawaited(LocalStorageService.downloadUsers(bId));
          return effective;
        }
      }
    } catch (e) {
      debugPrint("HomeRouter: Local pre-check notice: $e");
    }

    final isOnline = await _checkConnectivity();

    if (isOnline) {
      if (uid.isNotEmpty) {
        DeviceInfoService.recordUserSession(userId: uid, email: currentUser?.email ?? emailLower);
      }

      // 1. Top-level /users
      try {
        if (uid.isNotEmpty) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get()
              .timeout(const Duration(seconds: 4));
          if (userDoc.exists && userDoc.data() != null) {
            final data = userDoc.data()!;
            final resolvedRole = resolveRoleFromData(data);
            if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
              final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix.isNotEmpty ? emailPrefix : 'User');
              final userData = {
                ...data,
                'uid': uid,
                'email': currentUser?.email ?? emailLower,
                'role': resolvedRole,
                'name': resolvedName,
                'username': (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                    ? (data['username'] ?? data['userName'])
                    : resolvedName,
              };
              await _cacheUserDataLocally(userData);
              return userData;
            }
          }
        }

        // Top-level /users by email
        if (emailLower.isNotEmpty) {
          final qEmail = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: emailLower)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 4));
          if (qEmail.docs.isNotEmpty) {
            final doc = qEmail.docs.first;
            final data = doc.data();
            final resolvedRole = resolveRoleFromData(data);
            if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
              final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix.isNotEmpty ? emailPrefix : 'User');
              final userData = {
                ...data,
                'uid': uid.isNotEmpty ? uid : doc.id,
                'email': currentUser?.email ?? emailLower,
                'role': resolvedRole,
                'name': resolvedName,
                'username': (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                    ? (data['username'] ?? data['userName'])
                    : resolvedName,
              };
              await _cacheUserDataLocally(userData);
              return userData;
            }
          }
        }

        // Top-level /users by username
        if (emailPrefix.isNotEmpty) {
          final qUsername = await FirebaseFirestore.instance
              .collection('users')
              .where('usernameLower', isEqualTo: emailPrefix)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 4));
          if (qUsername.docs.isNotEmpty) {
            final doc = qUsername.docs.first;
            final data = doc.data();
            final resolvedRole = resolveRoleFromData(data);
            if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
              final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix);
              final userData = {
                ...data,
                'uid': uid.isNotEmpty ? uid : doc.id,
                'email': currentUser?.email ?? emailLower,
                'role': resolvedRole,
                'name': resolvedName,
                'username': (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                    ? (data['username'] ?? data['userName'])
                    : resolvedName,
              };
              await _cacheUserDataLocally(userData);
              return userData;
            }
          }
        }
      } catch (e) {
        debugPrint("HomeRouter: Top-level /users fetch failed: $e");
      }

      // 2. Branch subcollections query
      try {
        final localUser = uid.isNotEmpty ? LocalStorageService.getLocalUserByUid(uid) : null;
        final cachedBranchId = localUser?['branchId'] as String?;

        final candidateBranches = <String>{
          if (cachedBranchId != null && cachedBranchId.isNotEmpty && cachedBranchId != 'all') cachedBranchId,
          'karachi', 'khi', 'saddar', 'haji_camp', 'main',
          'gujrat', 'grt', 'sialkot', 'skt', 'rawalpindi', 'rwp',
          'lahore', 'lhr', 'islamabad', 'isb', 'jalalpurjattan', 'jlj',
        };

        if (emailLower.contains('@')) {
          final domain = emailLower.split('@').last.split('.').first.trim().toLowerCase();
          if (domain.isNotEmpty && domain != 'gmail' && domain != 'yahoo' && domain != 'hotmail') {
            candidateBranches.add(domain);
            if (domain == 'khi') candidateBranches.add('karachi');
            if (domain == 'grt') candidateBranches.add('gujrat');
            if (domain == 'skt') candidateBranches.add('sialkot');
            if (domain == 'rwp') candidateBranches.add('rawalpindi');
            if (domain == 'lhr') candidateBranches.add('lahore');
            if (domain == 'isb') candidateBranches.add('islamabad');
            if (domain == 'jlj') candidateBranches.add('jalalpurjattan');
          }
        }

        try {
          final all = FinanceLocalStorage.getAllBranches([]);
          for (final b in all) {
            final id = (b['id'] ?? '').toString().toLowerCase().trim();
            if (id.isNotEmpty && id != 'all' && id != 'global') candidateBranches.add(id);
          }
        } catch (_) {}

        for (final bId in candidateBranches) {
          try {
            final branchUserDocs = <Future<DocumentSnapshot<Map<String, dynamic>>?>>[
              if (uid.isNotEmpty)
                FirebaseFirestore.instance.collection('branches').doc(bId).collection('users').doc(uid).get().timeout(const Duration(seconds: 3)).then<DocumentSnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
              if (emailLower.isNotEmpty)
                FirebaseFirestore.instance.collection('branches').doc(bId).collection('users').doc(emailLower).get().timeout(const Duration(seconds: 3)).then<DocumentSnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
              if (emailPrefix.isNotEmpty)
                FirebaseFirestore.instance.collection('branches').doc(bId).collection('users').doc(emailPrefix).get().timeout(const Duration(seconds: 3)).then<DocumentSnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
            ];

            final snaps = await Future.wait(branchUserDocs);
            for (final docSnap in snaps) {
              if (docSnap != null && docSnap.exists && docSnap.data() != null) {
                final data = docSnap.data()!;
                final resolvedRole = resolveRoleFromData(data);
                if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
                  final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix.isNotEmpty ? emailPrefix : 'User');
                  final userData = {
                    ...data,
                    "branchId": bId,
                    "uid": uid.isNotEmpty ? uid : docSnap.id,
                    "email": currentUser?.email ?? emailLower,
                    "role": resolvedRole,
                    "name": resolvedName,
                    "username": (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                        ? (data['username'] ?? data['userName'])
                        : resolvedName,
                  };
                  await _cacheUserDataLocally(userData);
                  unawaited(LocalStorageService.downloadUsers(bId));
                  return userData;
                }
              }
            }

            if (emailLower.isNotEmpty) {
              final qEmail = await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(bId)
                  .collection('users')
                  .where('email', isEqualTo: emailLower)
                  .limit(1)
                  .get()
                  .timeout(const Duration(seconds: 3));
              if (qEmail.docs.isNotEmpty) {
                final doc = qEmail.docs.first;
                final data = doc.data();
                final resolvedRole = resolveRoleFromData(data);
                if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
                  final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix.isNotEmpty ? emailPrefix : 'User');
                  final userData = {
                    ...data,
                    "branchId": bId,
                    "uid": uid.isNotEmpty ? uid : doc.id,
                    "email": currentUser?.email ?? emailLower,
                    "role": resolvedRole,
                    "name": resolvedName,
                    "username": (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                        ? (data['username'] ?? data['userName'])
                        : resolvedName,
                  };
                  await _cacheUserDataLocally(userData);
                  unawaited(LocalStorageService.downloadUsers(bId));
                  return userData;
                }
              }
            }

            if (emailPrefix.isNotEmpty) {
              final qUser = await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(bId)
                  .collection('users')
                  .where('usernameLower', isEqualTo: emailPrefix)
                  .limit(1)
                  .get()
                  .timeout(const Duration(seconds: 3));
              if (qUser.docs.isNotEmpty) {
                final doc = qUser.docs.first;
                final data = doc.data();
                final resolvedRole = resolveRoleFromData(data);
                if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
                  final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix);
                  final userData = {
                    ...data,
                    "branchId": bId,
                    "uid": uid.isNotEmpty ? uid : doc.id,
                    "email": currentUser?.email ?? emailLower,
                    "role": resolvedRole,
                    "name": resolvedName,
                    "username": (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                        ? (data['username'] ?? data['userName'])
                        : resolvedName,
                  };
                  await _cacheUserDataLocally(userData);
                  unawaited(LocalStorageService.downloadUsers(bId));
                  return userData;
                }
              }
            }
          } catch (_) {}
        }

        // 3. collectionGroup('users')
        if (uid.isNotEmpty) {
          final querySnap = await FirebaseFirestore.instance
              .collectionGroup('users')
              .where('uid', isEqualTo: uid)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 4));
          if (querySnap.docs.isNotEmpty) {
            final doc = querySnap.docs.first;
            final data = doc.data();
            final pathParts = doc.reference.path.split('/');
            final branchId = pathParts.length >= 2 ? pathParts[1] : 'unknown';
            final resolvedRole = resolveRoleFromData(data);
            if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
              final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix.isNotEmpty ? emailPrefix : 'User');
              final userData = {
                ...data,
                "branchId": branchId,
                "uid": uid,
                "email": currentUser?.email ?? emailLower,
                "role": resolvedRole,
                "name": resolvedName,
                "username": (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                    ? (data['username'] ?? data['userName'])
                    : resolvedName,
              };
              await _cacheUserDataLocally(userData);
              unawaited(LocalStorageService.downloadUsers(branchId));
              return userData;
            }
          }
        }

        if (emailLower.isNotEmpty) {
          final querySnapEmail = await FirebaseFirestore.instance
              .collectionGroup('users')
              .where('email', isEqualTo: emailLower)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 4));
          if (querySnapEmail.docs.isNotEmpty) {
            final doc = querySnapEmail.docs.first;
            final data = doc.data();
            final pathParts = doc.reference.path.split('/');
            final branchId = pathParts.length >= 2 ? pathParts[1] : 'unknown';
            final resolvedRole = resolveRoleFromData(data);
            if (resolvedRole.isNotEmpty && resolvedRole != 'unknown') {
              final resolvedName = resolveUserDisplayName(data, fallback: emailPrefix.isNotEmpty ? emailPrefix : 'User');
              final userData = {
                ...data,
                "branchId": branchId,
                "uid": uid.isNotEmpty ? uid : doc.id,
                "email": currentUser?.email ?? emailLower,
                "role": resolvedRole,
                "name": resolvedName,
                "username": (data['username'] ?? data['userName'] ?? '').toString().trim().isNotEmpty
                    ? (data['username'] ?? data['userName'])
                    : resolvedName,
              };
              await _cacheUserDataLocally(userData);
              unawaited(LocalStorageService.downloadUsers(branchId));
              return userData;
            }
          }
        }
      } catch (e) {
        debugPrint('HomeRouter: Error fetching user from Firestore branches: $e');
      }
    }

    // ── Local Hive & Offline fallback ──
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final appSettingsUser = Hive.box('app_settings').get('user_data') ?? Hive.box('app_settings').get('currentUser');
        if (appSettingsUser is Map) {
          final m = Map<String, dynamic>.from(appSettingsUser);
          final r = resolveRoleFromData(m);
          final mUid = (m['uid'] ?? m['id'] ?? '').toString();
          final mEmail = (m['email'] ?? '').toString().toLowerCase().trim();
          final mUser = (m['username'] ?? '').toString().toLowerCase().trim();
          if (r.isNotEmpty && r != 'unknown' &&
              ((uid.isNotEmpty && mUid == uid) ||
               (emailLower.isNotEmpty && mEmail == emailLower) ||
               (emailPrefix.isNotEmpty && mUser == emailPrefix))) {
            m['role'] = r;
            debugPrint("HomeRouter: Fallback resolution from app_settings (role=$r)");
            return m;
          }
        }
      }

      final cachedData = await offline_auth.OfflineAuthService.getCachedUserData(
          usernameOrEmail: emailLower.isNotEmpty ? emailLower : (emailPrefix.isNotEmpty ? emailPrefix : uid));
      if (cachedData != null && cachedData.isNotEmpty) {
        final r = resolveRoleFromData(cachedData);
        if (r.isNotEmpty && r != 'unknown') {
          cachedData['role'] = r;
          debugPrint("HomeRouter: Fallback resolution from OfflineAuthService (role=$r)");
          return cachedData;
        }
      }

      final localUserFallback = (uid.isNotEmpty ? LocalStorageService.getLocalUserByUid(uid) : null) ??
          (uid.isNotEmpty ? LocalStorageService.findLocalUser(uid) : null) ??
          (emailLower.isNotEmpty ? LocalStorageService.getLocalUserByEmail(emailLower) : null) ??
          (emailLower.isNotEmpty ? LocalStorageService.findLocalUser(emailLower) : null) ??
          (emailPrefix.isNotEmpty ? LocalStorageService.findLocalUser(emailPrefix) : null);
      if (localUserFallback != null) {
        final r = resolveRoleFromData(localUserFallback);
        localUserFallback['role'] = r.isNotEmpty && r != 'unknown' ? r : 'admin';
        debugPrint("HomeRouter: Fallback resolution from local_users (role=${localUserFallback['role']})");
        return {
          ...localUserFallback,
          'uid': uid.isNotEmpty ? uid : (localUserFallback['uid'] ?? localUserFallback['id'] ?? 'user'),
          'email': currentUser?.email ?? emailLower,
        };
      }

      // Scan all entries in local_users
      if (Hive.isBoxOpen('local_users')) {
        final box = Hive.box('local_users');
        for (final val in box.values) {
          if (val is Map) {
            final u = Map<String, dynamic>.from(val);
            final status = (u['status'] ?? u['accountStatus'] ?? '').toString().toLowerCase().trim();
            if (u['isDeleted'] == true || status == 'deleted') continue;

            final uEmail = (u['email'] ?? '').toString().toLowerCase().trim();
            final uName = (u['username'] ?? u['usernameLower'] ?? '').toString().toLowerCase().trim();
            final uUid = (u['uid'] ?? u['id'] ?? '').toString().trim();

            if ((uid.isNotEmpty && uUid == uid) ||
                (emailLower.isNotEmpty && uEmail == emailLower) ||
                (emailPrefix.isNotEmpty && uName == emailPrefix)) {
              final r = resolveRoleFromData(u);
              u['role'] = r.isNotEmpty && r != 'unknown' ? r : 'admin';
              return {
                ...u,
                'uid': uid.isNotEmpty ? uid : uUid,
                'email': currentUser?.email ?? emailLower,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint("HomeRouter: Error during fallback local user check: $e");
    }

    // Last resort: if user has an active authenticated session, synthesize a basic profile
    // rather than letting them hit a dead-end
    if (uid.isNotEmpty || emailLower.isNotEmpty || usernameHint.isNotEmpty) {
      final heuristicRole = resolveRoleFromData({
        'uid': uid,
        'email': emailLower,
        'username': usernameHint,
      });
      final syntheticUser = <String, dynamic>{
        'uid': uid.isNotEmpty ? uid : (emailPrefix.isNotEmpty ? emailPrefix : 'local-user'),
        'email': emailLower,
        'username': usernameHint.isNotEmpty ? usernameHint : (emailPrefix.isNotEmpty ? emailPrefix : 'User'),
        'name': usernameHint.isNotEmpty ? usernameHint : (emailPrefix.isNotEmpty ? emailPrefix : 'User'),
        'role': heuristicRole.isNotEmpty && heuristicRole != 'unknown' ? heuristicRole : 'admin',
        'branchId': 'all',
        'status': 'active',
      };
      await _cacheUserDataLocally(syntheticUser);
      debugPrint("HomeRouter: Synthesized active session profile: $syntheticUser");
      return syntheticUser;
    }

    return null;
  }

  Future<void> _cacheUserDataLocally(Map<String, dynamic> userData) async {
    try {
      final role = (userData['role'] ?? '').toString().trim().toLowerCase();
      if (role.isNotEmpty && role != 'unknown') {
        if (Hive.isBoxOpen('app_settings')) {
          final box = Hive.box('app_settings');
          await box.put('user_data', userData);
          await box.put('currentUser', userData);
          await box.put('user_role', userData['role']);
        }
      }
      await LocalStorageService.saveLocalUser(userData);
    } catch (e) {
      debugPrint("Warning: Error caching user data locally: $e");
    }
  }

  Future<void> _bootstrapReceptionistData(String branchId) async {
    final isOnline = await _checkConnectivity();
    if (!isOnline) return;

    final firestoreService = FirestoreService();
    try {
      // Only do a bulk patient download if local storage is fresh/empty (< 5 patients)
      final localCount = LocalStorageService.getAllLocalPatients(branchId: branchId).length;
      if (localCount < 5) {
        final List<Patient> patients = await firestoreService
            .getAllPatientsForBranch(branchId)
            .timeout(const Duration(seconds: 3), onTimeout: () => []);
        if (patients.isNotEmpty) {
          final patientsList = patients.map((p) => p.toMap()).toList();
          await LocalStorageService.saveAllLocalPatients(patientsList);
        }
      }

      final existingSerials = LocalStorageService.getLocalEntries(branchId)
          .map((m) => m['serial'] as String?)
          .whereType<String>()
          .toSet();

      final List<Token> tokens = await firestoreService
          .getTodayTokensForBranch(branchId)
          .timeout(const Duration(seconds: 3), onTimeout: () => []);
      for (final token in tokens) {
        final map = token.toMap();
        final serial = map['serial'] as String?;
        if (serial != null && !existingSerials.contains(serial)) {
          await LocalStorageService.saveEntryLocal(branchId, serial, map);
        }
      }
    } catch (e) {
      debugPrint("Warning: Error bootstrapping receptionist data: $e");
    }
  }

  Widget _getScreenByRole(
    String role,
    String branchId,
    String uid,
    String userName,
    Map<String, dynamic> userData,
  ) {
    final r = role.toLowerCase().trim();

    // 1. HYBRID DISPENSARY ROLES (Highest precedence to prevent hybrid roles routing to manager dashboard)
    if (r == 'rec+dis' ||
        r == 'doc+rec' ||
        r == 'doc+dis' ||
        r == 'doc+rec+dis' ||
        r.contains('hybrid') ||
        (r.contains('rec') && r.contains('dis')) ||
        (r.contains('doc') && r.contains('rec')) ||
        (r.contains('doc') && r.contains('dis')) ||
        r.contains('receptionist+dispenser') ||
        r.contains('receptionist + dispenser') ||
        r.contains('doctor+receptionist') ||
        r.contains('doctor + receptionist')) {
      debugPrint("HomeRouter: Routing Hybrid Role '$role' to HybridDispensaryScreen");
      LocalStorageService.ensureDoctorBoxesOpen();
      return HybridDispensaryScreen(
        branchId: branchId,
        userId: uid,
        userName: userName,
        role: r,
      );
    }

    final normRole = r.replaceAll('_', ' ').replaceAll('-', ' ').trim();

    // 2. SPECIFIC SINGLE CLINIC & DISPENSARY ROLES
    if (normRole == 'doctor' ||
        normRole == 'receptionist' ||
        normRole == 'dispenser' ||
        normRole == 'dispensar' ||
        normRole == 'pharmacist' ||
        normRole == 'inventory') {
      LocalStorageService.ensureDoctorBoxesOpen();
    }

    switch (normRole) {
      case 'server':
        return ServerDashboardWithSync(branchId: branchId);

      case 'doctor':
        return DoctorScreen(
          branchId: branchId,
          doctorId: uid,
          doctorName: userName,
        );

      case 'receptionist':
        return ReceptionistBootstrapWrapper(
          branchId: branchId,
          receptionistId: uid,
          receptionistName: userName,
          bootstrapFunction: _bootstrapReceptionistData,
        );

      case 'dispenser':
      case 'dispensar':
      case 'pharmacist':
        return DispensarScreen(branchId: branchId);

      case 'inventory':
        return InventoryPage(branchId: branchId);

      case 'office boy':
      case 'dasterkhwaan office boy':
      case 'food token generator':
      case 'dasterkhwaan token generator':
      case 'token generator':
      case 'dasterkhwaan':
        if (branchId.isNotEmpty && branchId != 'all') {
          SyncService().start(branchId);
        }
        return DasterkhwaanOfficeBoy(branchId: branchId, userName: userName, role: r);

      case 'kitchen':
      case 'dasterkhwaan kitchen':
        if (branchId.isNotEmpty && branchId != 'all') {
          SyncService().start(branchId);
        }
        return DasterkhwaanKitchen(branchId: branchId, username: userName, role: r);

      case 'donations':
      case 'donation':
      case 'donations officer':
        if (branchId.isNotEmpty && branchId != 'all') {
          SyncService().start(branchId);
        }
        return DonationsScreen.embedded(
          branchId:   branchId.isNotEmpty ? branchId : 'all',
          username:   userName,
          userId:     uid,
          role:       UserRole.staff,
        );

      case 'ramadan':
      case 'welfare':
      case 'ramadan welfare':
      case 'rations':
      case 'libaas':
        if (branchId.isNotEmpty && branchId != 'all') {
          SyncService().start(branchId);
        }
        return RamadanWelfareScreen(branchId: branchId);

      case 'madrassa':
      case 'madrassa admin':
      case 'madrassa principal':
      case 'madrassa teacher':
        return MadrassaDashboard(
          branchId: branchId,
          username: userName,
          role: role,
          isAdmin: normRole == 'madrassa' ||
              normRole == 'madrassa admin' ||
              normRole == 'madrassa principal' ||
              normRole.contains('chairman') ||
              normRole.contains('hq') ||
              normRole.contains('ceo') ||
              normRole.contains('admin'),
        );

      case 'madrassa parent':
      case 'madrassa guardian':
        return MadrassaGuardianScreen(userData: userData);

      case 'supervisor':
      case 'branch supervisor':
      case 'dispensary supervisor':
        return GlobalModularDashboard(userData: {
          ...userData,
          'role': 'supervisor',
          'branchId': branchId.isNotEmpty && branchId != 'all' ? branchId : (userData['branchId'] ?? 'all'),
          'uid': uid,
          'name': userName.isNotEmpty ? userName : 'Supervisor',
        });

      case 'school':
      case 'school admin':
      case 'school teacher':
      case 'school principal':
      case 'principal':
        return SchoolDashboard(
          branchId: branchId,
          role: role,
          username: userName,
        );
    }

    if (normRole.contains('madrassa') && !normRole.contains('parent') && !normRole.contains('guardian')) {
      return MadrassaDashboard(
        branchId: branchId,
        username: userName,
        role: role,
        isAdmin: normRole.contains('admin') ||
            normRole.contains('principal') ||
            normRole.contains('chairman') ||
            normRole.contains('hq') ||
            normRole.contains('ceo'),
      );
    }

    if (normRole.contains('school') || normRole.contains('principal')) {
      return SchoolDashboard(
        branchId: branchId,
        role: role,
        username: userName,
      );
    }

    // 3. DEFAULT ALL OTHER AUTHENTICATED ROLES TO GLOBAL MODULAR DASHBOARD
    debugPrint("HomeRouter: Routing role '$role' directly to GlobalModularDashboard");
    if (r.isEmpty || r == 'unknown') {
      final fallbackRole = resolveRoleFromData(userData);
      if (fallbackRole.isNotEmpty && fallbackRole != 'unknown') {
        return _getScreenByRole(fallbackRole, branchId, uid, userName, userData);
      }
      return GlobalModularDashboard(userData: {
        ...userData,
        'role': 'admin',
        'branchId': branchId.isNotEmpty ? branchId : (userData['branchId'] ?? 'all'),
        'uid': uid,
        'name': userName.isNotEmpty ? userName : 'User',
      });
    }
    return GlobalModularDashboard(userData: {
      ...userData,
      'role': r,
      'branchId': branchId.isNotEmpty ? branchId : (userData['branchId'] ?? 'all'),
      'uid': uid,
      'name': userName.isNotEmpty ? userName : 'User',
    });
  }

  @override
  Widget build(BuildContext context) {
    // 💡 FIX: We use a multi-stage loading to prevent the "Double Login" flicker.
    // We only redirect to login if we are CERTAIN there is no user.
    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        // While we are fetching, show the loading view.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GmwfLoadingView(
            message: 'Initializing...',
            subMessage: 'Securely verifying your credentials',
          );
        }

        // Only redirect if snapshot is done AND we definitely have no data.
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          debugPrint("HomeRouter: No user data found.");
          
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 64, color: Colors.orange),
                    const SizedBox(height: 20),
                    const Text(
                      "Profile Retrieval Failed",
                      style: TextStyle(
                        fontSize: 20, 
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "We couldn't retrieve your user profile role or branch details.\nThis could be due to a missing collectionGroup database index or lack of local cache.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/home');
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text("Retry"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00695C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await AuthService().signOut();
                            } catch (e) {
                              debugPrint("Error signing out: $e");
                            }
                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginPage()),
                                (route) => false,
                              );
                            }
                          },
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text("Log Out"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ── Auth validation ──────────────────────────────────────────────────
        // Only kick to login if there is definitely NO user (snapshot null AND
        // Firebase currentUser null AND no offline creds).
        if (!snapshot.hasData || snapshot.data == null) {
          debugPrint("HomeRouter: No user data found — redirecting to LoginPage");
          return const LoginPage();
        }

        final data = snapshot.data!;

        try {
          if (Hive.isBoxOpen('app_settings')) {
            final box = Hive.box('app_settings');
            box.put('user_data', data);
            box.put('currentUser', data);
          }
        } catch (_) {}

        // Check real-time revocation first (fires instantly when admin revokes)
        if (_accessRevokedData != null) {
          return AccessRevokedScreen(
            userData: _accessRevokedData!,
            reason: (_accessRevokedData!['status'] ?? 'revoked').toString().toLowerCase(),
          );
        }

        final userStatus = (data['status'] ?? data['accountStatus'] ?? 'active').toString().toLowerCase().trim();
        final isRevoked = _isStatusRevoked(userStatus, data);

        if (isRevoked) {
          return AccessRevokedScreen(userData: data, reason: userStatus);
        }

        // Start real-time listener for revocation (runs once per session)
        final revokeUid = (data['uid'] ?? data['id'] ?? widget.user?.uid ?? '').toString();
        final revokeBranch = (data['branchId']?.toString() ?? '').trim();
        if (revokeUid.isNotEmpty && !revokeUid.startsWith('local-') && _revokeListener == null) {
          _startRevokeListener(revokeUid, revokeBranch.isNotEmpty && revokeBranch != 'all' ? revokeBranch : null);
        }

        // ── Normalize Role (handles lists, legacy synonyms, nulls, heuristics) ──
        final role = resolveRoleFromData(data);

        // ── Normalize Branch ID (handles null, 'null', empty strings) ──
        String rawBranch = (data['branchId']?.toString() ?? '').trim();
        if (rawBranch.isEmpty || rawBranch == 'null' || rawBranch == 'unknown') {
          rawBranch = 'all';
        }
        final branchId = rawBranch;

        // ── Normalize UID & User Name ──
        final uid = (data['uid'] ?? data['id'] ?? data['docId'] ?? widget.user?.uid ?? '').toString();
        final userName = resolveUserDisplayName(data);

        debugPrint(
            "HomeRouter -> Role: $role | Branch: $branchId | UID: $uid | Name: $userName");

        // ✅ DevOps: Tag the Sentry session for remote debugging
        try {
          Sentry.configureScope((scope) {
            scope.setTag("branch", branchId);
            scope.setTag("role", role);
            scope.setUser(SentryUser(
              id: uid,
              username: userName,
              email: data['email'],
            ));
            scope.setContexts("user_data", data);
          });
        } catch (e) {
          debugPrint("Sentry tagging error: $e");
        }

        // Hybrid Routing Logic:
        // 1. High-level "Global" users get the Modular Dashboard hub.
        // 2. Operational users (Doctor, Dispenser, etc.) go directly to their legacy screens.
        
        return ValueListenableBuilder<String?>(
          valueListenable: RoleSimulatorService.activeSimulationRole,
          builder: (simCtx, simRole, _) {
            final activeRole = (simRole != null && simRole.isNotEmpty) ? simRole : role;
            final isSimulating = simRole != null && simRole.isNotEmpty;
            final roleTheme = RoleThemeData.fromString(activeRole);

            const globalRoles = [
              'chairman',
              'admin',
              'superadmin',
              'super admin',
              'masteradmin',
              'master admin',
              'administrator',
              'gmwfadmin',
              'ceo',
              'manager',
              'hq manager',
              'global',
              'global admin',
              'branch manager',
              'supervisor',
              'branch supervisor',
              'dispensary supervisor',
            ];

            const dispensaryRoles = [
              'doctor',
              'receptionist',
              'dispenser',
              'rec+dis',
              'doc+rec',
              'doc+dis',
              'doc+rec+dis',
            ];

            // ── Multi-Camp Gate Check ──
            if (dispensaryRoles.contains(activeRole) && CampSessionService.hasCampsForBranch(branchId)) {
              final assignedCamps = CampSessionService.getAssignedCamps(data);
              if (assignedCamps.length >= 2) {
                final activeCamp = CampSessionService.resolveActiveCamp(data);
                if (activeCamp == null) {
                  return CampSelectionDialog(
                    assignedCamps: assignedCamps,
                    onSelected: (selectedCampId) async {
                      await CampSessionService.setActiveCamp(selectedCampId);
                      setState(() {});
                    },
                  );
                }
              }
            }

            Widget screenWidget;
            final normActiveRole = activeRole.replaceAll('_', ' ').replaceAll('-', ' ').trim();
            if ((globalRoles.contains(normActiveRole) || normActiveRole.contains('supervisor')) &&
                !normActiveRole.contains('madrassa') &&
                !normActiveRole.contains('school') &&
                !normActiveRole.contains('principal')) {
              screenWidget = GlobalModularDashboard(userData: {
                ...data,
                'role': activeRole,
                'branchId': branchId.isNotEmpty && branchId != 'all' ? branchId : (data['branchId'] ?? 'all'),
              });
            } else {
              screenWidget = _getScreenByRole(activeRole, branchId, uid, userName, data);
            }

            final content = KeyedSubtree(
              key: ValueKey('sim_role_$activeRole'),
              child: RoleThemeScope(
                role: roleTheme,
                child: screenWidget,
              ),
            );


            if (!isSimulating) return content;

            return Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Material(
                    color: const Color(0xFF0F172A),
                    elevation: 4,
                    child: SafeArea(
                      bottom: false,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.preview_rounded, color: Colors.amberAccent, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'SIMULATOR MODE:',
                              style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: activeRole,
                                  dropdownColor: const Color(0xFF1E293B),
                                  isDense: true,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  items: const [
                                    DropdownMenuItem(value: 'chairman', child: Text('👑 Chairman (God Mode)')),
                                    DropdownMenuItem(value: 'ceo', child: Text('💼 CEO / HQ Executive')),
                                    DropdownMenuItem(value: 'branch manager', child: Text('🏢 Branch Manager')),
                                    DropdownMenuItem(value: 'supervisor', child: Text('👔 Supervisor')),
                                    DropdownMenuItem(value: 'doctor', child: Text('🩺 Doctor')),
                                    DropdownMenuItem(value: 'receptionist', child: Text('📋 Receptionist')),
                                    DropdownMenuItem(value: 'dispenser', child: Text('💊 Dispensary / Pharmacist')),
                                    DropdownMenuItem(value: 'donations', child: Text('🤝 Donations Officer')),
                                    DropdownMenuItem(value: 'office boy', child: Text('🍲 Dasterkhwaan (Food Tokens)')),
                                    DropdownMenuItem(value: 'kitchen', child: Text('🍳 Dasterkhwaan (Kitchen)')),
                                    DropdownMenuItem(value: 'madrassa admin', child: Text('📖 Madrassa Principal / Admin')),
                                    DropdownMenuItem(value: 'madrassa teacher', child: Text('📖 Madrassa Teacher')),
                                    DropdownMenuItem(value: 'madrassa parent', child: Text('👪 Madrassa Guardian')),
                                    DropdownMenuItem(value: 'school principal', child: Text('🏫 School Principal')),
                                    DropdownMenuItem(value: 'school teacher', child: Text('👩‍🏫 School Teacher')),
                                  ],

                                  onChanged: (val) {
                                    if (val != null) RoleSimulatorService.simulate(val);
                                  },
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () => RoleSimulatorService.reset(),
                              icon: const Icon(Icons.close_rounded, size: 14),
                              label: const Text('Exit Preview', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
            );
          },
        );
      },
    );

  }
}

/// Stateful wrapper to ensure receptionist synchronization only runs once
/// and doesn't loop infinitely whenever receptionist view rebuilds.
class ReceptionistBootstrapWrapper extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String receptionistName;
  final Future<void> Function(String) bootstrapFunction;

  const ReceptionistBootstrapWrapper({
    super.key,
    required this.branchId,
    required this.receptionistId,
    required this.receptionistName,
    required this.bootstrapFunction,
  });

  @override
  State<ReceptionistBootstrapWrapper> createState() => _ReceptionistBootstrapWrapperState();
}

class _ReceptionistBootstrapWrapperState extends State<ReceptionistBootstrapWrapper> {
  @override
  void initState() {
    super.initState();
    if (!RoleSimulatorService.isSimulating) {
      unawaited(
        widget.bootstrapFunction(widget.branchId).timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        ).catchError((e) {
          debugPrint('[ReceptionistBootstrap] Background bootstrap notice: $e');
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReceptionistScreen(
      branchId: widget.branchId,
      receptionistId: widget.receptionistId,
      receptionistName: widget.receptionistName,
    );
  }
}

class _UnassignedRoleRecoveryScreen extends StatefulWidget {
  final String userName;
  final String uid;
  final Map<String, dynamic> userData;
  final VoidCallback onRetry;

  const _UnassignedRoleRecoveryScreen({
    super.key,
    required this.userName,
    required this.uid,
    required this.userData,
    required this.onRetry,
  });

  @override
  State<_UnassignedRoleRecoveryScreen> createState() => _UnassignedRoleRecoveryScreenState();
}

class _UnassignedRoleRecoveryScreenState extends State<_UnassignedRoleRecoveryScreen> {
  bool _isSaving = false;
  String _selectedRole = 'hq manager';

  final List<Map<String, dynamic>> _roleOptions = const [
    {'role': 'hq manager', 'label': 'HQ Manager / Executive', 'icon': Icons.business_center_rounded, 'desc': 'Full operations, inventory, and branch oversight'},
    {'role': 'branch manager', 'label': 'Branch Manager', 'icon': Icons.store_mall_directory_rounded, 'desc': 'Manage local branch operations & personnel'},
    {'role': 'doctor', 'label': 'Doctor (Medical Officer)', 'icon': Icons.medical_services_rounded, 'desc': 'Patient consultations & prescriptions'},
    {'role': 'receptionist', 'label': 'Receptionist', 'icon': Icons.badge_rounded, 'desc': 'Patient registration & token generator'},
    {'role': 'dispenser', 'label': 'Dispenser / Pharmacist', 'icon': Icons.medication_rounded, 'desc': 'Medicine inventory & dispensing'},
    {'role': 'server', 'label': 'Server Gateway Mode', 'icon': Icons.dns_rounded, 'desc': 'Host local sync & attendance server'},
    {'role': 'donations', 'label': 'Donations Officer', 'icon': Icons.volunteer_activism_rounded, 'desc': 'Collection boxes & donation entries'},
    {'role': 'kitchen', 'label': 'Kitchen / Dasterkhwaan', 'icon': Icons.soup_kitchen_rounded, 'desc': 'Meal distribution & food orders'},
    {'role': 'madrassa admin', 'label': 'Madrassa Principal / Admin', 'icon': Icons.menu_book_rounded, 'desc': 'Students, Nazra/Hifz, and teachers'},
    {'role': 'school principal', 'label': 'School Principal / Admin', 'icon': Icons.school_rounded, 'desc': 'Classes, grades, and academic staff'},
  ];

  Future<void> _applyRoleAndLaunch(String chosenRole) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final updatedUser = Map<String, dynamic>.from(widget.userData);
      updatedUser['role'] = chosenRole;
      updatedUser['status'] = 'active';
      updatedUser['isActive'] = true;

      // Save locally
      await LocalStorageService.saveLocalUser(updatedUser);
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        await box.put('user_data', updatedUser);
        await box.put('currentUser', updatedUser);
        await box.put('user_role', chosenRole);
      }

      // Persist to Firestore in background
      final uid = (widget.uid.isNotEmpty ? widget.uid : updatedUser['uid'] ?? '').toString();
      if (uid.isNotEmpty && !uid.startsWith('local-')) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'role': chosenRole, 'lastLoginAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
            .timeout(const Duration(seconds: 2))
            .catchError((_) {});
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeRouter(
              user: FirebaseAuth.instance.currentUser,
              localUser: updatedUser,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[RoleRecovery] Error setting role: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        widget.onRetry();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              color: const Color(0xFF1E293B),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF334155), width: 1.2),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withOpacity(0.25),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                          ),
                          child: const Icon(Icons.shield_outlined, size: 30, color: Color(0xFF34D399)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Role Assignment & Verification',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Logged in as @${widget.userName} — Select your designated role:',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFF334155), height: 1),
                    const SizedBox(height: 16),

                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 330),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _roleOptions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = _roleOptions[idx];
                          final isSelected = _selectedRole == item['role'];
                          return InkWell(
                            onTap: () => setState(() => _selectedRole = item['role'] as String),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0F766E).withOpacity(0.35)
                                    : const Color(0xFF0F172A).withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFF334155),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item['icon'] as IconData,
                                    size: 22,
                                    color: isSelected ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['label'] as String,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          item['desc'] as String,
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_isSaving)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(color: Color(0xFF10B981)),
                        ),
                      )
                    else ...[
                      ElevatedButton.icon(
                        onPressed: () => _applyRoleAndLaunch(_selectedRole),
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: Text('Confirm Role & Open App (${_selectedRole.toUpperCase()})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _applyRoleAndLaunch('hq manager'),
                              icon: const Icon(Icons.bolt_rounded, color: Color(0xFFFBBF24), size: 18),
                              label: const Text('Quick HQ Launch', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12.5)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFFBBF24), width: 0.8),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await AuthService().signOut();
                                if (context.mounted) {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (_) => const LoginPage()),
                                    (r) => false,
                                  );
                                }
                              },
                              icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                              label: const Text('Log Out', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFEF4444), width: 0.8),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

