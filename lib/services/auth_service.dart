import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'local_storage_service.dart';

/// Authentication service with offline-first fallback
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Set<String> _adminEmails = {"admin@gmd.com", "supervisor@gmd.com"};

  /// ✅ Sign up new user (remote + local)
  Future<User?> signUp(
      String email, String password, String role, String branchId) async {
    email = email.trim().toLowerCase();

    // Admins are predefined locally
    if (_adminEmails.contains(email)) {
      await LocalStorageService.seedLocalAdmins();
      return null;
    }

    // Create Firebase user
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
        "passwordHash":
            LocalStorageService.hashPassword(password), // cache for offline
        "createdAt": DateTime.now().toIso8601String(),
      };

      try {
        // Save to Firestore in users collection
        await _firestore.collection("users").doc(user.uid).set(userData);
      } catch (_) {
        // Queue for sync if offline/failure
        await LocalStorageService.enqueueSync({
          'type': 'save_user',
          'uid': user.uid,
          'data': userData,
        });
      }

      // Always cache locally
      await LocalStorageService.saveLocalUser(userData);
    }

    return user;
  }

  /// ✅ Login user (offline-first, admin always works)
  Future<User?> login(String email, String password) async {
    email = email.trim().toLowerCase();

    // 🔑 Admin shortcut
    if (_adminEmails.contains(email)) {
      final local = LocalStorageService.getLocalUserByEmail(email);
      if (local != null &&
          LocalStorageService.verifyPassword(password, local['passwordHash'])) {
        print("⚠️ Offline login used for $email (admin)");
        return null; // Admin logged in locally
      } else {
        throw Exception("⚠️ Wrong admin credentials");
      }
    }

    try {
      // Firebase online login
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
          "passwordHash": LocalStorageService.hashPassword(password),
          "createdAt": data['createdAt'] ?? DateTime.now().toIso8601String(),
        };

        // Save user locally for offline login
        await LocalStorageService.saveLocalUser(userData);
      }

      return user;
    } catch (_) {
      // 🔄 Fallback to offline login
      final local = LocalStorageService.getLocalUserByEmail(email);
      if (local != null &&
          LocalStorageService.verifyPassword(password, local['passwordHash'])) {
        print("⚠️ Offline login used for $email (local cache)");
        return null; // Offline login, no Firebase User
      }
      rethrow;
    }
  }

  /// ✅ Get user role (Firestore → local fallback)
  Future<String?> getUserRoleHybrid(String uid, String email) async {
    String? role;

    try {
      final doc = await _firestore.collection("users").doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        role = data?["role"]?.toString().toLowerCase();
      }
    } catch (_) {
      // ignore errors
    }

    role ??= LocalStorageService.getLocalUserByEmail(email)?['role']
        ?.toString()
        .toLowerCase();

    return role;
  }

  /// ✅ Get user branch (Firestore → local fallback)
  Future<String?> getUserBranchHybrid(String uid, String email) async {
    String? branchId;

    try {
      final doc = await _firestore.collection("users").doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        branchId = data?["branchId"]?.toString();
      }
    } catch (_) {}

    branchId ??=
        LocalStorageService.getLocalUserByEmail(email)?['branchId']?.toString();
    return branchId;
  }

  /// ✅ Logout
  Future<void> logout() async {
    await _auth.signOut();
  }
}
