// lib/pages/home_router.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';

// Pages
import 'receptionist_screen.dart'; // ✅ now sidebar version
import 'doctor_screen.dart';
import 'dispensar_screen.dart';
import 'admin_screen.dart';
import 'unknown_role.dart';
import 'inventory.dart';

class HomeRouter extends StatelessWidget {
  final User? user; // Firebase user (may be null in offline mode)
  final Map<String, dynamic>? localUser; // Offline Hive user

  const HomeRouter({super.key, this.user, this.localUser});

  Future<Map<String, dynamic>?> _fetchUserData() async {
    try {
      // ✅ Prefer Hive/local user if available (offline mode)
      if (localUser != null) {
        return localUser;
      }

      final u = user;
      if (u == null) return null;

      // ✅ Hardcoded Admin login check (only auth check, no Firestore)
      if (u.email?.toLowerCase() == 'admin@system.com') {
        return {
          'role': 'admin',
          'branchId': 'all',
          'uid': u.uid,
          'email': u.email,
        };
      }

      // ✅ Search Firestore under branches/{branchId}/users/{uid}
      final branchesSnap =
          await FirebaseFirestore.instance.collection("branches").get();

      for (final branch in branchesSnap.docs) {
        final userDoc =
            await branch.reference.collection("users").doc(u.uid).get();

        if (userDoc.exists) {
          return {
            ...userDoc.data()!,
            "branchId": branch.id,
            "uid": u.uid,
            "email": u.email,
          };
        }
      }
    } catch (e) {
      debugPrint('❌ Firestore fetch error: $e');
    }

    // ✅ fallback to local cache if no Firestore match
    final email = user?.email?.toLowerCase() ?? localUser?['email'] ?? '';
    final uid = user?.uid ?? localUser?['uid'] ?? '';

    final cached = LocalStorageService.getLocalUserByEmail(email) ??
        LocalStorageService.getLocalUserByUid(uid);

    return cached;
  }

  Widget _getScreenByRole(String role, String branchId, String uid) {
    final normalized = role.toLowerCase().trim();

    switch (normalized) {
      case 'doctor':
        return DoctorScreen(branchId: branchId, doctorId: uid);

      case 'receptionist': // ✅ now opens sidebar dashboard
        return ReceptionistScreen(branchId: branchId, receptionistId: uid);

      case 'inventory':
        return InventoryPage(branchId: branchId, receptionistId: uid);

      case 'dispensor':
      case 'dispenser':
      case 'pharmacist':
        return DispensarScreen(branchId: branchId);

      case 'admin': // ✅ only comes from hardcoded check
        return const AdminScreen();

      default:
        return const UnknownRolePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchUserData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const UnknownRolePage();
        }

        final data = snapshot.data!;
        final role = (data['role'] ?? 'unknown').toString();
        final branchId = (data['branchId'] ?? 'unknown').toString();
        final uid = data['uid'] ?? user?.uid ?? localUser?['uid'] ?? 'unknown';

        debugPrint('🚦 Routing user: role=$role, branchId=$branchId, uid=$uid');

        return _getScreenByRole(role, branchId, uid);
      },
    );
  }
}
