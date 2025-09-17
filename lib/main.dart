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

  // Catch all Flutter errors
  FlutterError.onError = (details) {
    debugPrint("❌ Flutter Error: ${details.exceptionAsString()}");
  };

  runZonedGuarded(() async {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Firestore offline cache
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);

    // Initialize Hive (centralized in LocalStorageService)
    await LocalStorageService.init();
    await LocalStorageService.seedLocalAdmins();

    // Window manager (for desktop apps)
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
      home: const InitAppScreen(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/admin': (context) => const AdminScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          final args = settings.arguments as Map<String, dynamic>?;

          if (args == null || (args['uid'] == null && args['user'] == null)) {
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(child: Text("❌ Invalid arguments for HomeRouter")),
              ),
            );
          }

          User? firebaseUser;
          if (args['user'] != null && args['user'] is User) {
            firebaseUser = args['user'] as User;
          } else if (args['uid'] != null) {
            firebaseUser = FakeUser(uid: args['uid']);
          }

          return MaterialPageRoute(
            builder: (_) => HomeRouter(user: firebaseUser!),
          );
        }
        return null;
      },
    );
  }
}

/// Minimal fake User for offline/admin
class FakeUser implements User {
  @override
  final String uid;

  FakeUser({required this.uid});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Initialization screen waits before showing login
class InitAppScreen extends StatelessWidget {
  const InitAppScreen({super.key});

  Future<void> _initialize() async {
    // Slight delay to allow Hive / Firebase to initialize fully
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialize(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text("❌ Init failed: ${snapshot.error}"),
            ),
          );
        }

        return const LoginPage();
      },
    );
  }
}
