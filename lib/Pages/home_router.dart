// lib/pages/home_router.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../services/local_storage_service.dart';
import '../services/firestore_service.dart';
import '../services/offline_auth_service.dart' as offline_auth;
import '../models/patient.dart';
import '../models/token.dart';

import 'dispensary/receptionist/receptionist_screen.dart';
import 'dispensary/doctor/doctor_screen.dart';
import 'dispensary/dispensar/inventory.dart';
import 'dispensary/dispensar/dispensar_screen.dart';
import 'login_page.dart';
import 'server.dart';

import 'dasterkhwaan/office_boy.dart';
import 'dasterkhwaan/kitchen.dart';
import 'donations/donations_screen.dart';
import 'donations/donations_shared.dart';
import '../widgets/gmwf_loading_view.dart';
import 'global_modular_dashboard.dart'; // Unified modular entry point
import 'madrassa/madrassa_dashboard.dart';
import 'madrassa/madrassa_guardian_screen.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';

import '../constants/navigator_key.dart';

class HomeRouter extends StatefulWidget {
  final User? user;
  final Map<String, dynamic>? localUser;

  const HomeRouter({
    super.key,
    this.user,
    this.localUser,
  });

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  late Future<Map<String, dynamic>?> _userDataFuture;

  @override
  void initState() {
    super.initState();
    _userDataFuture = _fetchUserData();
  }

  @override
  void didUpdateWidget(HomeRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final uidChanged = widget.user?.uid != oldWidget.user?.uid;
    final localUserChanged = widget.localUser != oldWidget.localUser;
    if (uidChanged || localUserChanged) {
      setState(() {
        _userDataFuture = _fetchUserData();
      });
    }
  }

  Future<bool> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint("HomeRouter: Connectivity check timed out");
        return [ConnectivityResult.none];
      });
      return connectivityResult
          .any((result) => result != ConnectivityResult.none);
    } catch (e) {
      debugPrint("Connectivity check error: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchUserData() async {
    if (widget.localUser != null && widget.localUser!.isNotEmpty) {
      debugPrint("HomeRouter: Using passed localUser data");
      return widget.localUser;
    }

    final currentUser = widget.user;
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
      final querySnap = await FirebaseFirestore.instance
          .collectionGroup('users')
          .where(FieldPath.documentId, isEqualTo: uid)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));

      if (querySnap.docs.isNotEmpty) {
        final doc = querySnap.docs.first;
        final data = doc.data();
        final pathParts = doc.reference.path.split('/');
        final branchId = pathParts.length >= 2 ? pathParts[1] : 'unknown';
        final userData = {
          ...data,
          "branchId": branchId,
          "uid": uid,
          "email": currentUser.email,
          "name": data['username'] ?? data['name'] ?? 'User',
          "username": data['username'] ?? 'unknown',
        };
        await _cacheUserDataLocally(userData);
        return userData;
      }
    } catch (e) {
      debugPrint('HomeRouter: Error fetching user from Firestore branches via collectionGroup: $e');
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
    Map<String, dynamic> userData,
  ) {
    final r = role.toLowerCase().trim();

    switch (r) {
      case 'server':
        return ServerDashboardWithSync(branchId: branchId);

      case 'doctor':
        return DoctorScreen(
          branchId: branchId,
          doctorId: uid,
          doctorName: userName,
        );

      case 'receptionist':
        return ReceptionistBootstrapWrapper(
          branchId: branchId,
          receptionistId: uid,
          receptionistName: userName,
          bootstrapFunction: _bootstrapReceptionistData,
        );

      case 'dispenser':
      case 'dispensar':
      case 'pharmacist':
        return DispensarScreen(branchId: branchId);

      case 'inventory':
        return InventoryPage(branchId: branchId);

      case 'supervisor':
      case 'branch manager':
        return GlobalModularDashboard(userData: {
          'role': r,
          'branchId': branchId,
          'uid': uid,
          'name': userName,
        });

      case 'office boy':
      case 'dasterkhwaan office boy':
      case 'food token generator':
      case 'dasterkhwaan token generator':
      case 'token generator':
      case 'dasterkhwaan':
        return DasterkhwaanOfficeBoy(branchId: branchId, userName: userName, role: r);

      case 'kitchen':
      case 'dasterkhwaan kitchen':
        return DasterkhwaanKitchen(branchId: branchId, username: userName);

      case 'donations':
        return DonationsScreen.embedded(
          branchId:   branchId,
          username:   userName,
          role:       UserRole.staff,
        );

      case 'madrassa admin':
      case 'madrassa principal':
      case 'madrassa teacher':
        return MadrassaDashboard(
          branchId: branchId,
          username: userName,
          role: role,
          isAdmin: r == 'madrassa admin' || r == 'madrassa principal',
        );

      case 'madrassa parent':
      case 'madrassa guardian':
        return MadrassaGuardianScreen(userData: userData);

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
    // 💡 FIX: We use a multi-stage loading to prevent the "Double Login" flicker.
    // We only redirect to login if we are CERTAIN there is no user.
    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        // While we are fetching, show the loading view.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GmwfLoadingView(
            message: 'Initializing...',
            subMessage: 'Securely verifying your credentials',
          );
        }

        // Only redirect if snapshot is done AND we definitely have no data.
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          debugPrint("HomeRouter: No user data - checking for late arrival...");
          
          // Final fallback check to prevent race condition
          if (widget.user == null && widget.localUser == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              }
            });
            debugPrint(
                "HomeRouter: No user data found - redirecting to login");
          }

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
            widget.user?.uid ??
            data['uid'] ??
            'unknown';
        final userName =
            (data['name'] as String?) ?? (data['username'] as String?) ?? 'User';

        debugPrint(
            "HomeRouter -> Role: $role | Branch: $branchId | UID: $uid | Name: $userName");

        // ✅ DevOps: Tag the Sentry session for remote debugging
        try {
          Sentry.configureScope((scope) {
            scope.setTag("branch", branchId);
            scope.setTag("role", role);
            scope.setUser(SentryUser(
              id: uid,
              username: userName,
              email: data['email'],
            ));
            scope.setContexts("user_data", data);
          });
        } catch (e) {
          debugPrint("Sentry tagging error: $e");
        }

        // Hybrid Routing Logic:
        // 1. High-level "Global" users get the Modular Dashboard hub.
        // 2. Operational users (Doctor, Dispenser, etc.) go directly to their legacy screens.
        
        const globalRoles = [
          'chairman',
          'admin',
          'ceo',
          'manager',
          'hq manager',
          'global',
          'global admin',
          'supervisor',
          'branch manager',
        ];
        
        final roleTheme = RoleThemeData.fromString(role);
        if (globalRoles.contains(role)) {
          debugPrint("HomeRouter -> Routing Global User to Modular Dashboard");
          return RoleThemeScope(
            role: roleTheme,
            child: GlobalModularDashboard(userData: data),
          );
        } else {
          debugPrint("HomeRouter -> Routing Operational User directly to $role screen");
          return RoleThemeScope(
            role: roleTheme,
            child: _getScreenByRole(role, branchId, uid, userName, data),
          );
        }
      },
    );
  }
}

/// Stateful wrapper to ensure receptionist synchronization only runs once
/// and doesn't loop infinitely whenever receptionist view rebuilds.
class ReceptionistBootstrapWrapper extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String receptionistName;
  final Future<void> Function(String) bootstrapFunction;

  const ReceptionistBootstrapWrapper({
    super.key,
    required this.branchId,
    required this.receptionistId,
    required this.receptionistName,
    required this.bootstrapFunction,
  });

  @override
  State<ReceptionistBootstrapWrapper> createState() => _ReceptionistBootstrapWrapperState();
}

class _ReceptionistBootstrapWrapperState extends State<ReceptionistBootstrapWrapper> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = widget.bootstrapFunction(widget.branchId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
              ),
            ),
          );
        }
        return ReceptionistScreen(
          branchId: widget.branchId,
          receptionistId: widget.receptionistId,
          receptionistName: widget.receptionistName,
        );
      },
    );
  }
}
