// lib/services/auth_service.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../realtime/realtime_manager.dart';
import '../realtime/connection_manager.dart';
import '../realtime/lan_host_manager.dart';
import '../services/local_storage_service.dart';
import '../services/finance_local_storage.dart';
import '../services/device_info_service.dart';
import '../services/offline_auth_service.dart';
import '../services/camp_session_service.dart';
import '../services/role_simulator_service.dart';

class AuthService {
  static void Function()? onSignOutCallback;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> _cacheUserDataLocally(Map<String, dynamic> userData) async {
    try {
      await LocalStorageService.saveLocalUser(userData);
    } catch (e) {
      debugPrint('[AuthService] Failed to cache user data: $e');
    }
  }

  // ── Sign Up ───────────────────────────────────────────────────────────────
  Future<String> signUp({
    required String email,
    required String password,
    required String username,
    required String role,
    required String branchId,
    required String branchName,
    String? phone,
    String? identification,
    String? address,
    String? bankName,
    String? bankAccount,
    String? degree,
    double? salary,
    XFile? profileImageXFile,
    Uint8List? profileImageBytes,
    PlatformFile? identificationFile,
    PlatformFile? degreeFile,
    String? profilePictureBase64,
    String? identificationBase64,
    String? degreeBase64,
    String? studentId, 
    List<String> studentIds = const [], // NEW — default empty
    String name = '',        // NEW
    String cnic = '',        // NEW
    String? dispensaryId,    // Sub-location dispensary identifier (legacy)
    List<String> dispensaryIds = const [], // Sub-location dispensary identifiers
    List<Map<String, String>> campSchedule = const [], // Time-based camp schedule
    String? session,         // Madrassa/Office operational session ('morning', 'evening', 'night')
    List<String> sessions = const [], // Operational sessions
    String? biometricPin,
    String? linkedEmployeeId,
  }) async {
    try {
      final lowerUsername = username.trim().toLowerCase();
      final lowerEmail    = email.trim().toLowerCase();

      // Duplicate check uses the lowercase version
      try {
        final query = await _firestore
            .collection('users')
            .where('usernameLower', isEqualTo: lowerUsername)
            .get()
            .timeout(const Duration(seconds: 10));
        final activeDocs = query.docs.where((d) {
          final data = d.data();
          final status = (data['status'] ?? data['accountStatus'] ?? '').toString().toLowerCase();
          return data['isDeleted'] != true && status != 'deleted';
        }).toList();
        if (activeDocs.isNotEmpty) throw Exception('Username taken');
      } catch (e) {
        if (e.toString().contains('Username taken')) rethrow;
        debugPrint('[AuthService] Remote username check skipped/notice: $e');
      }

      final currentAdminUser = _auth.currentUser;
      String uid = '';
      try {
        if (currentAdminUser != null) {
          FirebaseApp secondaryApp;
          try {
            secondaryApp = Firebase.app('SecondaryRegistrationApp');
          } catch (_) {
            secondaryApp = await Firebase.initializeApp(
              name: 'SecondaryRegistrationApp',
              options: Firebase.app().options,
            );
          }
          final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
          final cred = await secondaryAuth.createUserWithEmailAndPassword(
            email: lowerEmail,
            password: password,
          ).timeout(const Duration(seconds: 7));
          final user = cred.user;
          if (user != null) uid = user.uid;
          await secondaryAuth.signOut().timeout(const Duration(seconds: 3)).catchError((_) {});
        } else {
          final cred = await _auth.createUserWithEmailAndPassword(
            email: lowerEmail,
            password: password,
          ).timeout(const Duration(seconds: 7));
          final user = cred.user;
          if (user != null) uid = user.uid;
        }
      } catch (authErr) {
        debugPrint('[AuthService] Cloud Auth notice: $authErr');
        uid = 'local-${lowerEmail.replaceAll('@', '_').replaceAll('.', '_')}';
      }

      if (uid.isEmpty) {
        uid = 'local-${lowerEmail.replaceAll('@', '_').replaceAll('.', '_')}';
      }

      String creatorEmail = currentAdminUser?.email ?? '';
      String creatorUid   = currentAdminUser?.uid ?? '';
      String creatorName  = '';
      String creatorRole  = '';

      try {
        if (Hive.isBoxOpen('app_settings')) {
          final uData = Hive.box('app_settings').get('user_data') ?? Hive.box('app_settings').get('currentUser');
          if (uData is Map) {
            creatorName = (uData['username'] ?? uData['name'] ?? '').toString();
            creatorRole = (uData['role'] ?? '').toString();
            if (creatorEmail.isEmpty) creatorEmail = (uData['email'] ?? '').toString();
            if (creatorUid.isEmpty) creatorUid = (uData['uid'] ?? '').toString();
          }
        }
      } catch (_) {}

      final effectiveName = name.trim().isNotEmpty ? name.trim() : username.trim();
      final userData = <String, dynamic>{
        'uid': uid,
        'id': uid,
        'username': username.trim(),        // original casing preserved
        'usernameLower': lowerUsername,      // for case-insensitive lookup
        'email': lowerEmail,
        'role': role.trim(),
        'branchId': branchId.trim(),
        'branchName': branchName.trim(),
        'name': effectiveName,
        'cnic': cnic.isNotEmpty ? cnic : (identification?.trim() ?? ''),
        'status': 'active',
        'accountStatus': 'active',
        'isActive': true,
        'isRevoked': false,
        'accessRevoked': false,
        'studentIds': studentIds,
        'dispensaryIds': dispensaryIds.map((d) => d.trim().toLowerCase()).toList(),
        'campSchedule': campSchedule,
        if (session != null && session.trim().isNotEmpty) 'session': session.trim().toLowerCase(),
        if (sessions.isNotEmpty) 'sessions': sessions.map((s) => s.trim().toLowerCase()).toList(),
        if (biometricPin != null && biometricPin.trim().isNotEmpty) 'biometricPin': biometricPin.trim(),
        'createdBy': creatorEmail.isNotEmpty ? creatorEmail : (creatorName.isNotEmpty ? creatorName : 'Direct Registration'),
        'createdByName': creatorName.isNotEmpty ? creatorName : (creatorEmail.isNotEmpty ? creatorEmail : 'Admin'),
        'createdById': creatorUid,
        'createdByRole': creatorRole,
        'createdAtLocal': DateTime.now().toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (phone?.isNotEmpty ?? false)          userData['phone']          = phone!.trim();
      if (identification?.isNotEmpty ?? false) userData['identification']  = identification!.trim();
      if (address?.isNotEmpty ?? false)        userData['address']         = address!.trim();
      if (bankName?.isNotEmpty ?? false)       userData['bankName']        = bankName!.trim();
      if (bankAccount?.isNotEmpty ?? false)    userData['bankAccount']     = bankAccount!.trim();
      if (degree?.isNotEmpty ?? false)         userData['degree']          = degree!.trim();
      if (salary != null)                      userData['baseSalary']      = salary;
      if (studentId?.isNotEmpty ?? false)      userData['studentId']       = studentId!.trim();
      if (dispensaryId?.isNotEmpty ?? false)   userData['dispensaryId']    = dispensaryId!.trim().toLowerCase();

      // Base64 strings (offline & storage-free) with storage upload fallback
      if (profilePictureBase64 != null && profilePictureBase64.isNotEmpty) {
        userData['profilePictureUrl'] = profilePictureBase64;
      } else if (profileImageXFile != null || profileImageBytes != null) {
        final url = await _uploadFile(
            folder: 'profile', uid: uid,
            xFile: profileImageXFile, webBytes: profileImageBytes);
        if (url != null) userData['profilePictureUrl'] = url;
      }

      if (identificationBase64 != null && identificationBase64.isNotEmpty) {
        userData['identificationUrl'] = identificationBase64;
      } else if (identificationFile != null) {
        final url = await _uploadFile(
            folder: 'identification', uid: uid, platformFile: identificationFile);
        if (url != null) userData['identificationUrl'] = url;
      }

      if (degreeBase64 != null && degreeBase64.isNotEmpty) {
        userData['degreeCertificateUrl'] = degreeBase64;
      } else if (role.toLowerCase() == 'doctor' && degreeFile != null) {
        final url = await _uploadFile(
            folder: 'degree', uid: uid, platformFile: degreeFile);
        if (url != null) userData['degreeCertificateUrl'] = url;
      }

      try {
        await _firestore.collection('users').doc(uid).set(userData).timeout(const Duration(seconds: 15));
      } catch (cloudErr) {
        debugPrint('[AuthService] Cloud user document write notice (enqueued for sync): $cloudErr');
      }

      // Build a Hive-safe copy by replacing FieldValue sentinels with local timestamps.
      // FieldValue.serverTimestamp() cannot be serialized by Hive and causes silent failures.
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final hiveUserData = <String, dynamic>{};
      userData.forEach((key, value) {
        if (value != null && value.runtimeType.toString().contains('FieldValue')) {
          hiveUserData[key] = nowIso; // Replace sentinel with local ISO timestamp
        } else {
          hiveUserData[key] = value;
        }
      });
      hiveUserData['password'] = password; // Ensure local offline fallback authentication works immediately

      // Use the proper multi-key save that sanitizes Timestamps, deduplicates, and flushes.
      await LocalStorageService.saveUserOffline(
        uid: uid,
        branchId: branchId,
        userData: hiveUserData,
      );

      // Also enqueue for cloud sync (without plain password in cloud payload)
      final syncData = Map<String, dynamic>.from(hiveUserData)..remove('password');
      await LocalStorageService.enqueueSync({
        'type': 'save_user',
        'branchId': branchId,
        'uid': uid,
        'data': syncData,
      });

      // Always cache locally (for both admin-initiated and direct registrations)
      await _cacheUserDataLocally(hiveUserData);

      // Save credentials for offline authentication under both email and username
      await OfflineAuthService.saveCredentials(
        usernameOrEmail: lowerEmail,
        password: password,
        userData: hiveUserData,
        setAsLastLoggedIn: currentAdminUser == null,
      );
      if (lowerUsername.isNotEmpty && lowerUsername != lowerEmail) {
        await OfflineAuthService.saveCredentials(
          usernameOrEmail: lowerUsername,
          password: password,
          userData: hiveUserData,
          setAsLastLoggedIn: false,
        );
      }

      // Explicit Employee Link:
      if (linkedEmployeeId != null && linkedEmployeeId.isNotEmpty) {
        await FinanceLocalStorage.linkUserToEmployee(
          userId: uid,
          employeeId: linkedEmployeeId,
        );
      }
      return uid;
    } catch (e) {
      debugPrint('[AuthService] signUp failed: $e');
      rethrow;
    }
  }

  // ── Sign In ───────────────────────────────────────────────────────────────
  /// Signs the user in with Firebase.
  ///
  /// Key fix: if the server IP is missing or the realtime initialisation fails
  /// we log a warning but do NOT throw — the user still gets their session and
  /// the app continues.  The realtime connection will be re-attempted later
  /// by ConnectionManager's auto-discovery.
  Future<User?> signIn({
    required String input,
    required String password,
    String? serverIp,
  }) async {
    try {
      String loginEmail = input.trim().toLowerCase();

      if (!loginEmail.contains('@')) {
        final found = await _findUserByUsername(input);
        if (found == null) throw Exception('User not found');
        loginEmail = found['email'] as String;
      }

      debugPrint('[AuthService] signIn → $loginEmail');
      final cred = await _auth.signInWithEmailAndPassword(
        email: loginEmail,
        password: password,
      );
      final user = cred.user;
      if (user == null) return null;

      final emailLower = loginEmail;

      // Special system accounts
      final systemAccounts = {
        'chairman@system.com': {'role': 'chairman', 'username': 'chairman', 'branchId': 'all'},
        'ceo@system.com':      {'role': 'ceo',      'username': 'ceo',      'branchId': 'all'},
        'server@gmd.com':      {'role': 'server',   'username': 'server',   'branchId': 'sialkot'},
      };
      if (systemAccounts.containsKey(emailLower)) {
        final d = systemAccounts[emailLower]!;
        await _cacheUserDataLocally({...d, 'uid': user.uid, 'email': user.email});
        return user;
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw Exception('User data not found in Firestore');

      final data  = userDoc.data()!;
      final role  = (data['role'] as String?)?.toLowerCase() ?? 'unknown';
      final branchId = data['branchId'] as String? ?? '';

      await _cacheUserDataLocally({...data, 'uid': user.uid, 'email': user.email});

      // ── Role-specific setup ────────────────────────────────────────────────
      // IMPORTANT: none of these throw — failures are logged and swallowed so
      // the caller always gets a valid User back.
      if (role == 'server') {
        try {
          debugPrint('[AuthService] Dedicated Branch Server detected for role=server');
          // ZkTeco biometric listener is started on the server machine
          // (ZkTecoNetworkService.startServer() imported where needed)
        } catch (e) {
          debugPrint('[AuthService] Server engine start notice: $e');
        }
      } else {
        // All client roles (receptionist, doctor, dispenser, supervisor, finance, donations, teacher, madrassa, school, etc.)
        // connect silently to the central Branch Server via ConnectionManager & RealtimeManager.
        try {
          final username = user.displayName ?? user.email?.split('@').first ?? role;
          // Executive roles (chairman, CEO) may have branchId='all'. Resolve to
          // the first known real branch for server discovery.
          String connBranchId = branchId;
          if (connBranchId.isEmpty || connBranchId == 'all' || connBranchId == 'global') {
            try {
              if (Hive.isBoxOpen(LocalStorageService.branchesBox)) {
                final box = Hive.box(LocalStorageService.branchesBox);
                for (final val in box.values) {
                  if (val is Map) {
                    final id = (val['id'] ?? '').toString().trim().toLowerCase();
                    final isOff = val['isOffboarded'] == true || val['status'] == 'offboarded';
                    if (id.isNotEmpty && id != 'all' && id != 'global' && !isOff) {
                      connBranchId = id;
                      break;
                    }
                  }
                }
              }
            } catch (_) {}
          }
          ConnectionManager().start(
            role: role,
            branchId: connBranchId,
            username: username,
          );
        } catch (e) {
          debugPrint('[AuthService] ConnectionManager.start failed (non-fatal): $e');
        }
      }

      // Record device & browser session info
      try {
        await DeviceInfoService.recordUserSession(userId: user.uid, email: user.email);
      } catch (e) {
        debugPrint('[AuthService] Non-fatal device info logging failed: $e');
      }

      return user;
    } catch (e) {
      debugPrint('[AuthService] signIn error: $e');
      rethrow;
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  /// Each step is independently try/caught so a failure in one cannot block
  /// the others.
  Future<void> signOut() async {
    debugPrint('[AuthService] Starting sign out');

    try {
      onSignOutCallback?.call();
    } catch (_) {}

    try {
      RoleSimulatorService.reset();
    } catch (_) {}

    // 1. Instantly clear user session from Hive to prevent auto-login loops
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        await box.delete('user_data');
        await box.delete('currentUser');
        await box.delete('user');
        await box.delete('role');
        await box.delete('auth_token');
        await box.delete('server_authenticated');
        await box.flush();
      }
    } catch (e) {
      debugPrint('[AuthService] Hive app_settings clear error: $e');
    }

    try {
      await OfflineAuthService.clearCachedUserData();
    } catch (e) {
      debugPrint('[AuthService] OfflineAuthService clear error: $e');
    }

    try {
      await CampSessionService.clearActiveCamp();
    } catch (_) {}

    // 2. Sign out from Firebase Auth
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[AuthService] Firebase signOut error: $e');
    }

    // 3. Fire-and-forget background cleanup tasks
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final uid = user.uid;
        _firestore.collection('users').doc(uid).set({
          'isOnline': false,
          'lastLogoutAt': FieldValue.serverTimestamp(),
          'lastOnlineAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});

        DeviceInfoService.markUserOffline(userId: uid).catchError((_) {});
      }
    } catch (_) {}

    try { LanHostManager.stopHost().catchError((_) {}); } catch (_) {}
    try { RealtimeManager().dispose().catchError((_) {}); } catch (_) {}

    debugPrint('[AuthService] Sign out complete');
  }

  User? getCurrentUser() => _auth.currentUser;

  Future<Map<String, dynamic>?> getUserByUid(String uid) async {
    try {
      // 1. Check root collection (Legacy/Admin)
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) return doc.data();

      // 2. Check all branches via collection group
      final querySnap = await _firestore
          .collectionGroup('users')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (querySnap.docs.isNotEmpty) {
        final doc = querySnap.docs.first;
        final data = doc.data();
        final pathParts = doc.reference.path.split('/');
        final branchId = pathParts.length >= 2 ? pathParts[1] : 'unknown';
        return {
          ...data,
          'branchId': branchId,
        };
      }
    } catch (e) {
      debugPrint('[AuthService] getUserByUid failed: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findUserByUsername(String username) async {
    final lower = username.trim().toLowerCase();

    // 1. Check local users cache first to avoid unnecessary network & Firestore reads
    try {
      final cached = LocalStorageService.findLocalUser(lower);
      if (cached != null) {
        final email = cached['email'] as String?;
        if (email != null && email.isNotEmpty) {
          return {
            'email': email,
            'username': cached['username'] ?? lower,
            'role': cached['role'] ?? 'unknown',
            'branchId': cached['branchId'] ?? 'all',
            'uid': cached['uid'] ?? cached['id'] ?? '',
          };
        }
      }
    } catch (_) {}

    try {
      final q = await _firestore
          .collection('users')
          .where('usernameLower', isEqualTo: lower)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final d = q.docs.first;
        return {'email': d['email'], 'username': d['username'],
                'role': d['role'], 'branchId': d['branchId'] ?? 'all', 'uid': d.id};
      }
    } catch (_) {}

    try {
      final querySnap = await _firestore
          .collectionGroup('users')
          .where('usernameLower', isEqualTo: lower)
          .limit(1)
          .get();
      if (querySnap.docs.isNotEmpty) {
        final doc = querySnap.docs.first;
        final d = doc.data();
        final pathParts = doc.reference.path.split('/');
        final branchId = pathParts.length >= 2 ? pathParts[1] : 'unknown';
        return {
          'email': d['email'],
          'username': d['username'],
          'role': d['role'],
          'branchId': branchId,
          'uid': doc.id
        };
      }
    } catch (e) {
      debugPrint('[AuthService] _findUserByUsername branch search failed via collectionGroup: $e');
    }
    return null;
  }

  // ── File upload helper ────────────────────────────────────────────────────
  Future<String?> _uploadFile({
    required String folder,
    required String uid,
    XFile? xFile,
    Uint8List? webBytes,
    PlatformFile? platformFile,
  }) async {
    try {
      Uint8List? bytes;
      String? fileName;

      if (xFile != null) {
        bytes    = webBytes ?? await xFile.readAsBytes();
        fileName = '${DateTime.now().millisecondsSinceEpoch}_${xFile.name}';
      } else if (platformFile != null) {
        bytes = kIsWeb
            ? platformFile.bytes
            : (platformFile.path != null ? await File(platformFile.path!).readAsBytes() : null);
        fileName = '${DateTime.now().millisecondsSinceEpoch}_${platformFile.name}';
      }

      if (bytes == null || fileName == null) return null;

      final ref      = _storage.ref().child('users/$uid/$folder/$fileName');
      final snapshot = kIsWeb
          ? await ref.putData(bytes)
          : await ref.putFile(File(xFile?.path ?? platformFile!.path!));
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('[AuthService] _uploadFile failed: $e');
      return null;
    }
  }

  // ── Profile & Credentials Update Helper (Offline First) ───────────────────
  Future<void> updateUserProfileAndCredentials({
    required String uid,
    String? newName,
    String? currentPassword,
    String? newPassword,
    String? branchId,
  }) async {
    final currentUser = _auth.currentUser;
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': DateTime.now().toIso8601String(),
    };

    if (newName != null && newName.trim().isNotEmpty) {
      final cleanName = newName.trim();
      updates['name'] = cleanName;
      updates['displayName'] = cleanName;

      // Update Firebase Auth user display name if online and self
      if (currentUser != null && (currentUser.uid == uid || currentUser.displayName != cleanName)) {
        try {
          await currentUser.updateDisplayName(cleanName);
        } catch (e) {
          debugPrint('[AuthService] updateDisplayName skipped/offline: $e');
        }
      }
    }

    if (newPassword != null && newPassword.trim().isNotEmpty) {
      final cleanNewPw = newPassword.trim();
      updates['password'] = cleanNewPw;
      updates['passwordHash'] = LocalStorageService.hashPassword(cleanNewPw);

      // Re-authenticate and update Firebase Auth password if currentPassword provided
      if (currentUser != null && (currentUser.uid == uid || currentUser.email != null)) {
        if (currentPassword != null && currentPassword.trim().isNotEmpty) {
          try {
            final cred = EmailAuthProvider.credential(
              email: currentUser.email!,
              password: currentPassword.trim(),
            );
            await currentUser.reauthenticateWithCredential(cred).timeout(const Duration(seconds: 4));
          } catch (reauthErr) {
            debugPrint('[AuthService] Online reauth check failed: $reauthErr');
            // If offline, check against cached hash or OfflineAuthService
            if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
              final box = Hive.box(LocalStorageService.usersBox);
              final u = box.get(uid) ?? box.get('user:$uid') ?? box.get('user:${currentUser.email}');
              if (u is Map) {
                final curHash = LocalStorageService.hashPassword(currentPassword.trim());
                if (u['passwordHash'] != null && u['passwordHash'] != curHash && u['password'] != currentPassword.trim()) {
                  throw Exception('Incorrect current password.');
                }
              }
            }
          }
        }

        try {
          await currentUser.updatePassword(cleanNewPw).timeout(const Duration(seconds: 4));
        } catch (pwErr) {
          debugPrint('[AuthService] Firebase updatePassword error/offline: $pwErr');
        }
      }

      // Update offline auth secure storage password immediately
      if (currentUser?.email != null) {
        await OfflineAuthService.updateCachedPassword(cleanNewPw, usernameOrEmail: currentUser!.email!);
      }
      await OfflineAuthService.updateCachedPassword(cleanNewPw, usernameOrEmail: uid);
    }

    // 1. Update local Hive users box immediately (Offline-First)
    try {
      if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
        final box = Hive.box(LocalStorageService.usersBox);
        for (final k in box.keys) {
          final val = box.get(k);
          if (val is Map) {
            final uId = (val['uid'] ?? val['id'])?.toString();
            if (uId == uid || k == uid || k == 'user:$uid' || (currentUser?.email != null && k == 'user:${currentUser!.email}')) {
              final merged = Map<String, dynamic>.from(val)..addAll(updates);
              await box.put(k, merged);
            }
          }
        }
      }

      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final currentMap = box.get('user_data') ?? box.get('currentUser');
        if (currentMap is Map && (currentMap['uid'] == uid || currentMap['id'] == uid)) {
          final updated = Map<String, dynamic>.from(currentMap)..addAll(updates);
          await box.put('user_data', updated);
          await box.put('currentUser', updated);
        }
      }
    } catch (e) {
      debugPrint('[AuthService] Hive local update notice: $e');
    }

    // 2. Update Firestore & Enqueue Sync
    try {
      await _firestore.collection('users').doc(uid).set(updates, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (cloudErr) {
      debugPrint('[AuthService] Firestore update deferred to sync queue: $cloudErr');
      await LocalStorageService.enqueueSync({
        'type': 'save_user',
        'uid': uid,
        if (branchId != null) 'branchId': branchId,
        'data': updates,
      });
    }
  }
}

