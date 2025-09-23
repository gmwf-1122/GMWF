import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gmwf/services/local_storage_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, String> _hardcodedAdmins = {
    "admin@gmd.com": "Admin@123",
  };

  /// Sign up new user → store uid, role, branchId, branchName
  Future<User?> signUp(
    String email,
    String password,
    String role,
    String branchId,
    String branchName,
  ) async {
    email = email.trim().toLowerCase();
    branchId = branchId.trim().toLowerCase();

    if (_hardcodedAdmins.containsKey(email)) {
      await LocalStorageService.seedLocalAdmins();
      return null;
    }

    User? user;

    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      user = result.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        user = result.user;
      } else {
        rethrow;
      }
    }

    if (user != null) {
      final firestoreUserData = {
        "uid": user.uid,
        "email": email,
        "role": role.toLowerCase(),
        "branchId": branchId,
        "branchName": branchName,
        "passwordHash": LocalStorageService.hashPassword(password),
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      };

      // ✅ Save to global users collection
      await _firestore.collection("users").doc(user.uid).set(
            firestoreUserData,
            SetOptions(merge: true),
          );

      // ✅ Save inside branch subcollection
      await _firestore
          .collection("branches")
          .doc(branchId)
          .collection("users")
          .doc(user.uid)
          .set(firestoreUserData, SetOptions(merge: true));

      // ✅ Ensure branch doc exists
      await _firestore.collection("branches").doc(branchId).set({
        "id": branchId,
        "name": branchName,
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ✅ Mirror to Hive (offline cache)
      final hiveUserData = Map<String, dynamic>.from(firestoreUserData);
      hiveUserData["createdAt"] = DateTime.now();
      hiveUserData["updatedAt"] = DateTime.now();

      await LocalStorageService.saveLocalUser(hiveUserData);
    }

    return user;
  }

  /// Login
  Future<Map<String, dynamic>?> login(String email, String password) async {
    email = email.trim().toLowerCase();

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

    try {
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
        final branchName = data['branchName']?.toString() ?? '';

        final userData = {
          "uid": user.uid,
          "email": email,
          "role": role,
          "branchId": branchId,
          "branchName": branchName,
          "passwordHash": LocalStorageService.hashPassword(password),
          "createdAt": data['createdAt'] ?? DateTime.now(),
        };

        await LocalStorageService.saveLocalUser(userData);
        return userData;
      }
    } catch (e) {
      // 🔄 Offline fallback
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
