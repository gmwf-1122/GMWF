// lib/services/auth_service.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../realtime/realtime_manager.dart';
import '../realtime/lan_host_manager.dart';
import '../services/local_storage_service.dart';
import '../services/finance_local_storage.dart';
import '../services/device_info_service.dart';
import '../config/constants.dart';

class AuthService {
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
  }) async {
    try {
      final lowerUsername = username.trim().toLowerCase();
      final lowerEmail    = email.trim().toLowerCase();

      // Duplicate check uses the lowercase version
      final query = await _firestore
          .collection('users')
          .where('usernameLower', isEqualTo: lowerUsername)
          .get();
      if (query.docs.isNotEmpty) throw Exception('Username taken');

      final cred = await _auth.createUserWithEmailAndPassword(
        email: lowerEmail,
        password: password,
      );
      final user = cred.user;
      if (user == null) throw Exception('Sign up failed: User is null');

      final uid = user.uid;

      final userData = <String, dynamic>{
        'uid': uid,
        'username': username.trim(),        // original casing preserved
        'usernameLower': lowerUsername,      // for case-insensitive lookup
        'email': lowerEmail,
        'role': role.trim(),
        'branchId': branchId.trim(),
        'branchName': branchName.trim(),
        'name': name,
        'cnic': cnic,
        'studentIds': studentIds,
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

      await _firestore.collection('users').doc(uid).set(userData);

      const globalRoles = ['ceo', 'chairman', 'admin', 'hq manager'];
      if (!globalRoles.contains(role.toLowerCase())) {
        await _firestore
            .collection('branches')
            .doc(branchId)
            .collection('users')
            .doc(uid)
            .set(userData);
      }

      await _cacheUserDataLocally(userData);

      // Automatic Unified Employee Sync:
      // If user role is an employee/staff role, automatically create/sync Employee profile in Finance & HR
      final isStudentOrParent = role.toLowerCase().contains('student') || role.toLowerCase().contains('parent');
      if (!isStudentOrParent) {
        final cnicVal = (cnic.isNotEmpty ? cnic : (identification ?? '')).trim();
        await FinanceLocalStorage.createOrUpdateUnifiedEmployeeProfile(
          userId: uid,
          username: username,
          email: email,
          role: role,
          branchId: branchId,
          cnic: cnicVal,
          phone: phone,
          baseSalary: salary,
          bankName: bankName,
          bankAccount: bankAccount,
          profilePictureUrl: userData['profilePictureUrl']?.toString(),
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
      if (role == 'receptionist') {
        try {
          await LanHostManager.startHost(forceRefreshIp: true);
        } catch (e) {
          debugPrint('[AuthService] LanHostManager.startHost failed (non-fatal): $e');
        }
      } else if (role != 'admin' && role != 'chairman' && role != 'ceo' && role != 'hq manager' && role != 'server') {
        // Try to initialise realtime — but missing IP is NOT a fatal error.
        String? ip = serverIp?.trim();
        if (ip == null || ip.isEmpty) {
          final box = Hive.box('app_settings');
          ip = box.get('receptionist_server_ip') as String?;
        }

        if (ip != null && ip.isNotEmpty) {
          try {
            await RealtimeManager().initialize(
              role: role,
              branchId: branchId,
              serverIp: ip,
              port: AppNetwork.websocketPort,
            );
          } catch (e) {
            debugPrint('[AuthService] RealtimeManager.initialize failed (non-fatal): $e');
          }
        } else {
          // No server IP yet — ConnectionManager's auto-discovery will handle it.
          debugPrint('[AuthService] No server IP found — realtime will connect via auto-discovery');
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
      final user = _auth.currentUser;
      if (user != null) {
        final uid = user.uid;
        await _firestore.collection('users').doc(uid).set({
          'isOnline': false,
          'lastLogoutAt': FieldValue.serverTimestamp(),
          'lastOnlineAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await DeviceInfoService.markUserOffline(userId: uid);

        try {
          final box = Hive.box('app_settings');
          final userData = box.get('user_data') ?? box.get('currentUser');
          if (userData != null && userData is Map) {
            userData['isOnline'] = false;
            await box.put('user_data', userData);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AuthService] Reset isOnline error (ignored): $e');
    }

    try { await FirebaseAuth.instance.signOut(); }
    catch (e) { debugPrint('[AuthService] Firebase signOut error (ignored): $e'); }

    try { await LanHostManager.stopHost(); }
    catch (e) { debugPrint('[AuthService] LanHostManager.stopHost error (ignored): $e'); }

    try { await RealtimeManager().dispose(); }
    catch (e) { debugPrint('[AuthService] RealtimeManager.dispose error (ignored): $e'); }

    try {
      final box = Hive.box('app_settings');
      await box.clear();
    } catch (e) { debugPrint('[AuthService] Hive clear error (ignored): $e'); }

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

  // ── Username → email lookup ───────────────────────────────────────────────
  Future<Map<String, dynamic>?> _findUserByUsername(String username) async {
    final lower = username.trim().toLowerCase();

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
}
