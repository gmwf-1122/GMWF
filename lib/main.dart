// lib/main.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

import 'firebase_options.dart';

// Pages
import 'pages/login_page.dart';
import 'pages/home_router.dart';
import 'pages/admin_screen.dart';

// Services
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';
import 'services/firestore_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint("❌ Flutter Error: ${details.exceptionAsString()}");
  };

  runZonedGuarded(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ✅ Enable Firestore persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    // ✅ Initialize local storage + seed hardcoded admin
    await LocalStorageService.init();
    await LocalStorageService.seedLocalAdmins();

    // ✅ Setup custom window frame
    doWhenWindowReady(() {
      const minSize = Size(1280, 720);
      appWindow.minSize = minSize;

      appWindow.alignment = Alignment.center;
      appWindow.title = "Gulzar Madina Dispensary";

      // ✅ Start maximized by default, but user can resize/move later
      appWindow.maximize();

      appWindow.show();
    });

    runApp(const MyApp());
  }, (error, stack) {
    debugPrint("❌ Dart Error: $error\n$stack");
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final SyncService _syncService = SyncService();
  // ignore: unused_field
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _syncService.start();
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }

  void _enterFullScreen() {
    // ✅ Force fullscreen (maximize) after login
    appWindow.maximize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GM-D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasData && snapshot.data != null) {
            // ✅ Enter fullscreen once login is successful
            Future.microtask(() => _enterFullScreen());
            return HomeRouter(user: snapshot.data!);
          }

          return const LoginPage();
        },
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/admin': (context) => const AdminScreen(),
      },
    );
  }
}
