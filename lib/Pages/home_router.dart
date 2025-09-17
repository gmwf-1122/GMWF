// lib/pages/home_router.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';

// Pages
import 'receptionist_screen.dart';
import 'doctor_screen.dart';
import 'dispensar_screen.dart';
import 'admin_screen.dart';

class HomeRouter extends StatefulWidget {
  final User user;

  const HomeRouter({super.key, required this.user});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  String? _role;
  String? _branchId;

  final Set<String> _adminEmails = {"admin@gmd.com"};

  @override
  void initState() {
    super.initState();
    _initRole();
  }

  Future<void> _initRole() async {
    final email = widget.user.email?.toLowerCase();
    final uid = widget.user.uid;

    if (email == null) {
      setState(() {
        _role = "unknown";
        _branchId = "unknown";
      });
      return;
    }

    // ✅ Admin shortcut
    if (_adminEmails.contains(email) || uid == "admin_uid") {
      setState(() {
        _role = "admin";
        _branchId = "all";
      });
      return;
    }

    // Firestore fetch from users collection
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();

      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        final roleFromDb = (data["role"] ?? "").toString().toLowerCase();
        final branchFromDb = (data["branchId"] ?? "").toString();

        if (roleFromDb.isNotEmpty && branchFromDb.isNotEmpty) {
          await LocalStorageService.saveLocalUser({
            "email": email,
            "role": roleFromDb,
            "branchId": branchFromDb,
            "uid": uid,
          });

          setState(() {
            _role = roleFromDb;
            _branchId = branchFromDb;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("❌ Firestore fetch error: $e");
    }

    // Fallback to Hive
    final cachedData = LocalStorageService.getLocalUserByEmail(email) ??
        LocalStorageService.getLocalUserByUid(uid);

    setState(() {
      _role = cachedData?['role']?.toString() ?? "unknown";
      _branchId = cachedData?['branchId']?.toString() ?? "unknown";
    });
  }

  Widget _getScreenByRole(String role, String branchId) {
    switch (role) {
      case "doctor":
        return DoctorScreen(branchId: branchId);
      case "receptionist":
        return ReceptionistScreen(branchId: branchId);
      case "dispensar":
        return DispensarScreen(branchId: branchId);
      case "admin":
        return const AdminScreen();
      default:
        return const Scaffold(
          body: Center(child: Text("❌ Unknown Role")),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null || _branchId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_role == "unknown" || _branchId == "unknown") {
      return const Scaffold(
        body: Center(child: Text("❌ Unknown Role")),
      );
    }

    return _getScreenByRole(_role!, _branchId!);
  }
}
