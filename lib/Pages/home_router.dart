import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';

// Pages
import 'receptionist_screen.dart';
import 'doctor_screen.dart';
import 'dispensar_screen.dart';
import 'admin_screen.dart'; // ✅ updated name
import 'unknown_role.dart';

class HomeRouter extends StatelessWidget {
  final User user;

  const HomeRouter({super.key, required this.user});

  Future<Map<String, dynamic>?> _fetchUserData(User user) async {
    try {
      // ✅ Hardcoded admin
      if (user.email?.toLowerCase() == "admin@gmd.com" ||
          user.uid.startsWith("local-")) {
        await LocalStorageService.seedLocalAdmins();
        return {
          "role": "admin",
          "branchId": "all",
        };
      }

      // ✅ Fetch from Firestore
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      debugPrint("❌ Firestore fetch error: $e");
    }

    // ✅ Fallback to local cache
    final cached = LocalStorageService.getLocalUserByEmail(
            user.email?.toLowerCase() ?? "") ??
        LocalStorageService.getLocalUserByUid(user.uid);

    return cached;
  }

  Widget _getScreenByRole(String role, String branchId, String uid) {
    final normalized = role.toLowerCase().trim();

    switch (normalized) {
      case "doctor":
        return DoctorScreen(
          branchId: branchId,
          doctorId: uid, // ✅ pass doctorId explicitly
        );
      case "receptionist":
        return ReceptionistScreen(branchId: branchId);
      case "dispensor":
      case "dispenser":
      case "pharmacist":
        return DispensarScreen(branchId: branchId);
      case "admin":
        return const AdminScreen(); // ✅ updated usage
      default:
        return const UnknownRolePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchUserData(user),
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
        final role = (data["role"] ?? "unknown").toString();
        final branchId = (data["branchId"] ?? "unknown").toString();

        debugPrint("🚦 Routing user: role=$role, branchId=$branchId");

        return _getScreenByRole(role, branchId, user.uid);
      },
    );
  }
}
