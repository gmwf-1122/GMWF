import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/local_storage_service.dart';

// Updated page imports
import 'receptionist_screen.dart';
import 'doctor_screen.dart';
import 'admin_screen.dart';
import 'supervisor.dart'; // Uses branchId + supervisorId only
import 'inventory.dart';
import 'dispensar_screen.dart';
import 'unknown_role.dart';

class HomeRouter extends StatelessWidget {
  final User? user;
  final Map<String, dynamic>? localUser;

  const HomeRouter({super.key, this.user, this.localUser});

  // Fetch User Data (Firestore + Local Fallback)
  Future<Map<String, dynamic>?> _fetchUserData() async {
    try {
      if (localUser != null) return localUser;
      final u = user;
      if (u == null) return null;

      // Hardcoded Admin
      if (u.email?.toLowerCase() == 'admin@system.com') {
        return {
          'role': 'admin',
          'branchId': 'all',
          'uid': u.uid,
          'email': u.email,
          'name': 'Admin',
        };
      }

      // Fetch user data from any branch
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
            "name": userDoc.data()?['username'] ??
                userDoc.data()?['name'] ??
                'Unknown',
          };
        }
      }
    } catch (e) {
      debugPrint('Firestore fetch error: $e');
    }

    // Local fallback
    final email = user?.email?.toLowerCase() ?? localUser?['email'] ?? '';
    final uid = user?.uid ?? localUser?['uid'] ?? '';
    final cached = LocalStorageService.getLocalUserByEmail(email) ??
        LocalStorageService.getLocalUserByUid(uid);
    return cached;
  }

  // Role-based Routing
  Widget _getScreenByRole(
      String role, String branchId, String uid, String userName) {
    final normalized = role.toLowerCase().trim();

    switch (normalized) {
      case 'doctor':
        return DoctorScreen(
          branchId: branchId,
          doctorId: uid,
        );

      case 'receptionist':
        return ReceptionistScreen(
          branchId: branchId,
          receptionistId: uid,
          receptionistName: userName,
        );

      case 'dispenser':
      case 'dispensar':
      case 'dispensor':
      case 'pharmacist':
        return DispensarScreen(branchId: branchId);

      case 'inventory':
        return InventoryPage(branchId: branchId);

      case 'admin':
        return const AdminScreen();

      case 'supervisor':
        return SupervisorScreen(
          branchId: branchId,
          supervisorId: uid,
          // supervisorName REMOVED — fetched inside SupervisorScreen
        );

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
          Future.microtask(() => Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (r) => false));
          return const Scaffold(
            body: Center(child: Text("Redirecting to login...")),
          );
        }

        final data = snapshot.data!;
        final role = (data['role'] ?? 'unknown').toString();
        final branchId = (data['branchId'] ?? 'unknown').toString();
        final uid = data['uid'] ?? user?.uid ?? localUser?['uid'] ?? 'unknown';
        final userName = data['name'] ?? 'Unknown';

        debugPrint(
          'Routing user: role=$role, branchId=$branchId, uid=$uid, name=$userName',
        );

        return _getScreenByRole(role, branchId, uid, userName);
      },
    );
  }
}
