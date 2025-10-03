import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gmwf/services/local_storage_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, String> _hardcodedAdmins = {
    "admin": "Admin@123", // ✅ Now username instead of email
  };

  /// Sign up new user → store uid, username, role, branchId, branchName, phone
  Future<User?> signUp(
    String email, // Firebase still needs email for auth
    String password,
    String username, // ✅ New param
    String role,
    String branchId,
    String branchName, {
    String? phone,
  }) async {
    email = email.trim().toLowerCase();
    branchId = branchId.trim().toLowerCase();
    username = username.trim();

    if (_hardcodedAdmins.containsKey(username)) {
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
        "username": username, // ✅ Store username
        "email": email, // still stored internally
        "role": role.toLowerCase(),
        "branchId": branchId,
        "branchName": branchName,
        "phone": phone ?? "",
        "passwordHash": LocalStorageService.hashPassword(password),
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      };

      // ✅ Save inside branch subcollection
      await _firestore
          .collection("branches")
          .doc(branchId)
          .collection("users")
          .doc(user.uid)
          .set(firestoreUserData, SetOptions(merge: true));

      // ✅ Ensure branch doc exists
      await _firestore.collection("branches").doc(branchId).set({
        "branchId": branchId,
        "branchName": branchName,
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

  /// Login by username
  Future<Map<String, dynamic>?> login(String username, String password) async {
    username = username.trim().toLowerCase();

    // ✅ Hardcoded admin check
    if (_hardcodedAdmins.containsKey(username)) {
      if (_hardcodedAdmins[username] == password) {
        await LocalStorageService.seedLocalAdmins();
        return {
          "uid": "hardcoded_admin",
          "username": username,
          "role": "admin",
          "branchId": "",
          "branchName": "HQ",
          "phone": "",
        };
      } else {
        throw Exception("❌ Wrong admin credentials");
      }
    }

    try {
      // 🔎 Step 1: find user’s email by username
      final branches = await _firestore.collection("branches").get();
      String? foundEmail;
      Map<String, dynamic>? userData;

      for (var branch in branches.docs) {
        final usersRef = branch.reference.collection("users");
        final q = await usersRef.where("username", isEqualTo: username).get();

        if (q.docs.isNotEmpty) {
          final data = q.docs.first.data();
          foundEmail = data["email"];
          userData = data;
          break;
        }
      }

      if (foundEmail == null) {
        throw Exception("❌ Username not found");
      }

      // 🔎 Step 2: sign in with email & password
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: foundEmail,
        password: password,
      );

      final user = result.user;
      if (user != null && userData != null) {
        final finalUserData = {
          "uid": user.uid,
          "username": userData["username"],
          "email": foundEmail,
          "role": (userData['role'] ?? 'user').toString().toLowerCase(),
          "branchId": userData['branchId'] ?? "",
          "branchName": userData['branchName'] ?? "",
          "phone": userData['phone'] ?? "",
          "passwordHash": LocalStorageService.hashPassword(password),
          "createdAt": userData['createdAt'] ?? DateTime.now(),
        };

        await LocalStorageService.saveLocalUser(finalUserData);
        return finalUserData;
      }
    } catch (e) {
      // 🔄 Offline fallback
      final local = LocalStorageService.getLocalUserByEmail(username);
      final localHash = local?['passwordHash'] as String?;
      if (local != null &&
          localHash != null &&
          LocalStorageService.verifyPassword(password, localHash)) {
        return {
          "uid": local['uid'] ?? "local_user",
          "username": local['username'] ?? username,
          "role": (local['role'] ?? "user").toString().toLowerCase(),
          "branchId": local['branchId'] ?? "",
          "branchName": local['branchName'] ?? "",
          "phone": local['phone'] ?? "",
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
