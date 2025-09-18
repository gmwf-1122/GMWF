import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';

// Pages
import 'receptionist_screen.dart';
import 'doctor_screen.dart';
import 'dispensar_screen.dart';
import 'admin_screen.dart';
import 'unknown_role.dart';

class HomeRouter extends StatefulWidget {
  final User user;

  const HomeRouter({super.key, required this.user});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  String? _role;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    _initRole();
  }

  Future<void> _initRole() async {
    final email = widget.user.email?.toLowerCase();
    final uid = widget.user.uid;

    if (email == null || email.isEmpty) {
      setState(() {
        _role = "unknown";
        _branchId = "unknown";
      });
      return;
    }

    // Hardcoded admin
    if (email == "admin@gmd.com" || uid.startsWith("local-")) {
      await LocalStorageService.seedLocalAdmins();
      setState(() {
        _role = "admin";
        _branchId = "all";
      });
      return;
    }

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

    // Fallback to local cache
    final cachedData = LocalStorageService.getLocalUserByEmail(email) ??
        LocalStorageService.getLocalUserByUid(uid);

    setState(() {
      _role = cachedData?['role']?.toString().toLowerCase() ?? "unknown";
      _branchId = cachedData?['branchId']?.toString() ?? "unknown";
    });
  }

  Widget _getScreenByRole(String role, String branchId) {
    final normalized = role.toLowerCase().trim();

    switch (normalized) {
      case "doctor":
        return DoctorScreen(branchId: branchId);
      case "receptionist":
        return ReceptionistScreen(branchId: branchId);
      case "dispensor": // ✅ fixed spelling
      case "dispensar": // fallback if typo already saved
      case "pharmacist": // optional alias
        return DispensarScreen(branchId: branchId);
      case "admin":
        return const AdminScreen();
      default:
        return const UnknownRolePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null || _branchId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    debugPrint("🚦 Routing user: role=$_role, branchId=$_branchId");
    return _getScreenByRole(_role!, _branchId!);
  }
}
