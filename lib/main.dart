// lib/main.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:window_manager/window_manager.dart';

import 'firebase_options.dart';

// Pages
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/home_router.dart';
import 'pages/admin_screen.dart';

// Services
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint("❌ Flutter Error: ${details.exceptionAsString()}");
  };

  runZonedGuarded(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);

    await LocalStorageService.init();
    await LocalStorageService.seedLocalAdmins();

    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.white,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
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
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            return HomeRouter(
                user: snapshot.data!); // ✅ handles branchId + role
          }

          return const LoginPage();
        },
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/admin': (context) =>
            const AdminScreen(), // ✅ Admin doesn’t need branchId
      },
    );
  }
}
