import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gmwf/services/local_storage_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Hardcoded admin (predetermined)
  final Map<String, String> _hardcodedAdmins = {
    "admin@gmd.com": "Admin@123",
  };

  /// Sign up user (prevents registering the hardcoded admin)
  Future<User?> signUp(
      String email, String password, String role, String branchId) async {
    email = email.trim().toLowerCase();

    if (_hardcodedAdmins.containsKey(email)) {
      // ensure admin exists locally
      await LocalStorageService.seedLocalAdmins();
      return null;
    }

    await _auth.signOut();

    UserCredential result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    User? user = result.user;

    if (user != null) {
      final userData = {
        "uid": user.uid,
        "email": email,
        "role": role.toLowerCase(),
        "branchId": branchId,
        "passwordHash": LocalStorageService.hashPassword(password),
        "createdAt": DateTime.now().toIso8601String(),
      };

      try {
        await _firestore.collection("users").doc(user.uid).set(userData);
      } catch (_) {
        await LocalStorageService.enqueueSync({
          'type': 'save_user',
          'uid': user.uid,
          'data': userData,
        });
      }

      await LocalStorageService.saveLocalUser(userData);
    }

    return user;
  }

  /// Login user (null-safe)
  Future<Map<String, dynamic>?> login(String email, String password) async {
    email = email.trim().toLowerCase();

    // Hardcoded admin check
    if (_hardcodedAdmins.containsKey(email)) {
      if (_hardcodedAdmins[email] == password) {
        // ensure local admin exists so local lookups won't fail later
        await LocalStorageService.seedLocalAdmins();
        return {
          "uid": "hardcoded_admin",
          "email": email,
          "role": "admin",
          "branchId": "",
          "branchName": "HQ",
        };
      } else {
        throw Exception("❌ Wrong admin credentials");
      }
    }

    // Try Firebase login
    try {
      // sign out any previous session to force fresh session
      await _auth.signOut();

      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user != null) {
        final userDoc =
            await _firestore.collection("users").doc(user.uid).get();
        final data = userDoc.data() ?? {};

        // normalize createdAt (Timestamp -> ISO)
        final createdAtRaw = data['createdAt'];
        final createdAtIso = (createdAtRaw is Timestamp)
            ? createdAtRaw.toDate().toIso8601String()
            : (createdAtRaw is DateTime)
                ? createdAtRaw.toIso8601String()
                : (createdAtRaw?.toString() ??
                    DateTime.now().toIso8601String());

        final role = (data['role']?.toString() ?? 'user').toLowerCase();
        final branchId = data['branchId']?.toString() ?? '';

        final userData = {
          "uid": user.uid,
          "email": email,
          "role": role,
          "branchId": branchId,
          "passwordHash": LocalStorageService.hashPassword(password),
          "createdAt": createdAtIso,
        };

        await LocalStorageService.saveLocalUser(userData);
        return userData;
      }
    } catch (e) {
      // Firebase failed → try offline/local fallback
      final local = LocalStorageService.getLocalUserByEmail(email);
      final localHash = local?['passwordHash'] as String?;
      if (local != null &&
          localHash != null &&
          LocalStorageService.verifyPassword(password, localHash)) {
        return {
          "uid": local['uid'] ?? "local_user",
          "email": email,
          "role": (local['role'] ?? "user").toString().toLowerCase(),
          "branchId": local['branchId'] ?? "",
        };
      }
      rethrow;
    }

    return null;
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
