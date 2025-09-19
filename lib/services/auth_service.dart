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

    // Always sign out first to clear stale session
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
        "createdAt": FieldValue.serverTimestamp(),
      };

      if (role.toLowerCase() == "doctor") {
        userData["doctorId"] = user.uid;
      }

      try {
        await _firestore.collection("users").doc(user.uid).set(userData);

        // ✅ Ensure branch exists
        await _firestore.collection("branches").doc(branchId).set({
          "name": branchId[0].toUpperCase() + branchId.substring(1),
          "createdAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Fallback for offline → enqueue for sync
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

    // ✅ Hardcoded admin check
    if (_hardcodedAdmins.containsKey(email)) {
      if (_hardcodedAdmins[email] == password) {
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

    // ✅ Try Firebase login
    try {
      await _auth.signOut(); // force clean session
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user != null) {
        final userDoc =
            await _firestore.collection("users").doc(user.uid).get();
        final data = userDoc.data() ?? {};

        final role = (data['role']?.toString() ?? 'user').toLowerCase();
        final branchId = data['branchId']?.toString() ?? '';

        final userData = {
          "uid": user.uid,
          "email": email,
          "role": role,
          "branchId": branchId,
          "branchName": data['branchName'] ?? "",
          "passwordHash": LocalStorageService.hashPassword(password),
          "createdAt": data['createdAt'] ?? FieldValue.serverTimestamp(),
        };

        await LocalStorageService.saveLocalUser(userData);
        return userData;
      }
    } catch (e) {
      // ✅ Offline/local fallback
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
          "branchName": local['branchName'] ?? "",
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
