// lib/pages/home_router.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../services/local_storage_service.dart';
import '../services/firestore_service.dart';
import '../services/offline_auth_service.dart' as offline_auth;
import '../models/patient.dart';
import '../models/token.dart';

import 'dispensary/receptionist/receptionist_screen.dart';
import 'dispensary/doctor/doctor_screen.dart';
import 'admin_screen.dart';
import 'ceo_screen.dart';
import 'chairman_screen.dart';
import 'supervisor.dart';
import 'dispensary/dispensar/inventory.dart';
import 'dispensary/dispensar/dispensar_screen.dart';
import 'login_page.dart';
import 'manager_screen.dart';
import 'server_dashboard_with_sync.dart';

import 'dasterkhwaan/office_boy.dart';
import 'dasterkhwaan/kitchen.dart';
import 'donations/donations_screen.dart';

import '../main.dart';

class HomeRouter extends StatelessWidget {
  final User? user;
  final Map<String, dynamic>? localUser;

  const HomeRouter({
    super.key,
    this.user,
    this.localUser,
  });

  Future<bool> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult is List<ConnectivityResult>) {
        return connectivityResult
            .any((result) => result != ConnectivityResult.none);
      } else {
        return connectivityResult != ConnectivityResult.none;
      }
    } catch (e) {
      debugPrint("Connectivity check error: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchUserData() async {
    if (localUser != null && localUser!.isNotEmpty) {
      debugPrint("HomeRouter: Using passed localUser data");
      return localUser;
    }

    final currentUser = user;
    if (currentUser == null) {
      debugPrint(
          "HomeRouter: No Firebase user and no localUser -> checking cached data");
      try {
        final cachedData =
            await offline_auth.OfflineAuthService.getCachedUserData();
        if (cachedData != null) {
          debugPrint("HomeRouter: Found cached user data");
          return cachedData;
        }
      } catch (e) {
        debugPrint("HomeRouter: Error retrieving cached user data: $e");
      }
      return null;
    }

    final uid = currentUser.uid;
    final emailLower = currentUser.email?.toLowerCase() ?? '';

    final isOnline = await _checkConnectivity();

    if (!isOnline) {
      debugPrint("HomeRouter: Device is offline, using local storage");
      try {
        final cachedData =
            await offline_auth.OfflineAuthService.getCachedUserData();
        if (cachedData != null) {
          debugPrint(
              "HomeRouter: Using cached user data from OfflineAuthService");
          return cachedData;
        }
      } catch (e) {
        debugPrint("HomeRouter: Error retrieving cached data: $e");
      }
      final localByUid = LocalStorageService.getLocalUserByUid(uid);
      if (localByUid != null) {
        return {...localByUid, 'uid': uid, 'email': currentUser.email};
      }
      final localByEmail =
          LocalStorageService.getLocalUserByEmail(emailLower);
      if (localByEmail != null) {
        return {...localByEmail, 'uid': uid, 'email': currentUser.email};
      }
      debugPrint("HomeRouter: No local user data found for offline mode");
      return null;
    }

    // System accounts
    final systemAccounts = {
      'admin@system.com': {
        'role': 'admin',
        'branchId': 'all',
        'username': 'admin',
        'name': 'Admin'
      },
      'chairman@system.com': {
        'role': 'chairman',
        'branchId': 'all',
        'username': 'chairman',
        'name': 'Chairman'
      },
      'ceo@system.com': {
        'role': 'ceo',
        'branchId': 'all',
        'username': 'ceo',
        'name': 'CEO'
      },
    };

    if (systemAccounts.containsKey(emailLower)) {
      final d = systemAccounts[emailLower]!;
      final data = {...d, 'uid': uid, 'email': currentUser.email};
      await _cacheUserDataLocally(data);
      return data;
    }

    // Top-level /users
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final userData = {
          ...data,
          'uid': uid,
          'email': currentUser.email,
          'name': data['username'] ?? data['name'] ?? 'User',
          'username': data['username'] ?? 'unknown',
        };
        await _cacheUserDataLocally(userData);
        return userData;
      }
    } catch (e) {
      debugPrint("HomeRouter: Top-level /users fetch failed: $e");
    }

    // Branch /users
    try {
      final branchesSnap = await FirebaseFirestore.instance
          .collection("branches")
          .get()
          .timeout(const Duration(seconds: 10));

      for (final branch in branchesSnap.docs) {
        final userDoc = await branch.reference
            .collection("users")
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 5));

        if (userDoc.exists) {
          final data = userDoc.data()!;
          final userData = {
            ...data,
            "branchId": branch.id,
            "uid": uid,
            "email": currentUser.email,
            "name": data['username'] ?? data['name'] ?? 'User',
            "username": data['username'] ?? 'unknown',
          };
          await _cacheUserDataLocally(userData);
          return userData;
        }
      }
    } catch (e) {
      debugPrint('HomeRouter: Error fetching user from Firestore branches: $e');
    }

    // Hive fallback
    final localByUid = LocalStorageService.getLocalUserByUid(uid);
    if (localByUid != null) {
      return {...localByUid, 'uid': uid, 'email': currentUser.email};
    }
    final localByEmail = LocalStorageService.getLocalUserByEmail(emailLower);
    if (localByEmail != null) {
      return {...localByEmail, 'uid': uid, 'email': currentUser.email};
    }

    debugPrint("HomeRouter: Could not find user data anywhere for UID: $uid");
    return null;
  }

  Future<void> _cacheUserDataLocally(Map<String, dynamic> userData) async {
    try {
      await LocalStorageService.saveLocalUser(userData);
    } catch (e) {
      debugPrint("Warning: Error caching user data locally: $e");
    }
  }

  Future<void> _bootstrapReceptionistData(String branchId) async {
    final isOnline = await _checkConnectivity();
    if (!isOnline) return;

    final firestoreService = FirestoreService();
    try {
      final existingPatientIds = LocalStorageService.getAllLocalPatients(
              branchId: branchId)
          .map((m) => m['patientId'] as String?)
          .whereType<String>()
          .toSet();

      final List<Patient> patients =
          await firestoreService.getAllPatientsForBranch(branchId);
      for (final patient in patients) {
        final map = patient.toMap();
        final patientId = map['patientId'] as String?;
        if (patientId != null && !existingPatientIds.contains(patientId)) {
          await LocalStorageService.saveLocalPatient(map);
        }
      }

      final existingSerials = LocalStorageService.getLocalEntries(branchId)
          .map((m) => m['serial'] as String?)
          .whereType<String>()
          .toSet();

      final List<Token> tokens =
          await firestoreService.getTodayTokensForBranch(branchId);
      for (final token in tokens) {
        final map = token.toMap();
        final serial = map['serial'] as String?;
        if (serial != null && !existingSerials.contains(serial)) {
          await LocalStorageService.saveEntryLocal(branchId, serial, map);
        }
      }
    } catch (e) {
      debugPrint("Warning: Error bootstrapping receptionist data: $e");
    }
  }

  Widget _getScreenByRole(
    String role,
    String branchId,
    String uid,
    String userName,
  ) {
    final r = role.toLowerCase().trim();

    switch (r) {
      case 'ceo':
        return const CeoScreen();

      case 'chairman':
        return const ChairmanScreen();

      case 'admin':
        return AdminScreen(branchId: branchId);

      // Manager: same authority level as admin, branch-scoped
      case 'manager':
        return ManagerScreen(branchId: branchId, username: userName);

      case 'server':
        return ServerDashboardWithSync(branchId: branchId);

      case 'doctor':
        return DoctorScreen(
          branchId: branchId,
          doctorId: uid,
          doctorName: userName,
        );

      case 'receptionist':
        return FutureBuilder<void>(
          future: _bootstrapReceptionistData(branchId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF4CAF50))),
              );
            }
            return ReceptionistScreen(
              branchId: branchId,
              receptionistId: uid,
              receptionistName: userName,
            );
          },
        );

      case 'dispenser':
      case 'dispensar':
      case 'pharmacist':
        return DispensarScreen(branchId: branchId);

      case 'inventory':
        return InventoryPage(branchId: branchId);

      case 'supervisor':
        return SupervisorScreen(branchId: branchId, supervisorId: uid);

      // Dasterkhwaan: Office Boy
      case 'office boy':
      case 'dasterkhwaan office boy':
      case 'food token generator':
      case 'dasterkhwaan token generator':
      case 'token generator':
      case 'dasterkhwaan':
        return const DasterkhwaanOfficeBoy();

      // Dasterkhwaan: Kitchen
      case 'kitchen':
      case 'dasterkhwaan kitchen':
        return const DasterkhwaanKitchen();

      // Standalone Donations screen
      case 'donations':
        return DonationsScreen();

      default:
        debugPrint("Unknown role: $role");
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF00695C), Color(0xFF004D40)],
              ),
            ),
            child: Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 80, color: Colors.orange),
                      const SizedBox(height: 24),
                      const Text("Unknown Role",
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF004D40))),
                      const SizedBox(height: 16),
                      Text(
                        "Your account role '$role' is not recognized.\nPlease contact your administrator.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            navigatorKey.currentContext!,
                            MaterialPageRoute(
                                builder: (_) => const LoginPage()),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text("Back to Login"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00695C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: Future.delayed(const Duration(milliseconds: 500), _fetchUserData),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: Color(0xFF4CAF50))),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          debugPrint(
              "HomeRouter: No user data found - redirecting to login");

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Flushbar(
                message:
                    "Session expired or account not found. Please log in again.",
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 5),
              ).show(context);

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            }
          });

          return const Scaffold(
            body: Center(
                child: Text(
                    "No user data found. Redirecting to login...")),
          );
        }

        final data = snapshot.data!;
        final role =
            (data['role'] as String? ?? 'unknown').toLowerCase().trim();
        final branchId =
            (data['branchId'] as String? ?? 'unknown').trim();
        final uid = (data['uid'] as String?) ??
            user?.uid ??
            data['uid'] ??
            'unknown';
        final userName =
            (data['name'] as String?) ?? (data['username'] as String?) ?? 'User';

        debugPrint(
            "HomeRouter -> Role: $role | Branch: $branchId | UID: $uid | Name: $userName");

        return _getScreenByRole(role, branchId, uid, userName);
      },
    );
  }
}