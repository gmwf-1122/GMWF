// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import 'firebase_options.dart';

// Pages
import 'pages/login_page.dart';
import 'pages/home_router.dart';
import 'pages/admin_screen.dart';
import 'pages/dispensar_screen.dart';
import 'pages/inventory.dart';

// Services
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';

// Global error logger
Future<void> logError(String message, [StackTrace? stack]) =>
    _logError(message, stack?.toString() ?? '');

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Clear corrupted data if app crashed last time
    await _clearCorruptedDataOnCrash();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize local storage
    await LocalStorageService.init();
    await LocalStorageService.seedLocalAdmins();

    // Run the app first
    runApp(const MyApp());

    // Desktop window setup (after runApp)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        doWhenWindowReady(() {
          const minSize = Size(1280, 720);
          appWindow.minSize = minSize;
          appWindow.alignment = Alignment.center;
          appWindow.title = "Gulzar Madina Dispensary";
          appWindow.maximize();
          appWindow.show();
        });
      });
    }

    // Firestore verification and sync service after UI is initialized
    Future.microtask(() async {
      try {
        await FirebaseFirestore.instance.collection('ping').limit(1).get();
        debugPrint("Firestore verified.");
      } catch (e) {
        debugPrint("Firestore not ready yet: $e");
      }
    });

    _clearCrashMarkerOnSuccess();
  }, (error, stack) async {
    await _logError(error.toString(), stack.toString());
    _showCrashScreen(error, stack);
  });
}

// Log crash to file
Future<void> _logError(String error, String stack) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final logFile = File(path.join(dir.path, 'gmwf_crash.log'));
    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] ERROR: $error\nSTACK: $stack\n\n';
    await logFile.writeAsString(entry, mode: FileMode.append);
  } catch (_) {}
}

// Crash screen UI
void _showCrashScreen(Object error, StackTrace stack) {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red[50],
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 72, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'GMWF Crashed',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'A critical error occurred. The app will restart in 5 seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Log saved. Send to support if issue persists.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _restartApp,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  // Auto-restart after 5 seconds
  Future.delayed(const Duration(seconds: 5), _restartApp);
}

// Restart app
void _restartApp() {
  final exe = Platform.resolvedExecutable;
  final args = ['--enable-logging'];

  Process.start(exe, args, runInShell: true).then((_) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        appWindow.close();
      }
    });
  }).catchError((e) {
    debugPrint("Failed to restart: $e");
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      appWindow.close();
    }
  });
}

// Clear corrupted data on crash
Future<void> _clearCorruptedDataOnCrash() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final crashMarker = File(path.join(dir.path, '.last_crash'));

    if (await crashMarker.exists()) {
      final appDir = Directory(dir.path);
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
      debugPrint("Cleared corrupted app data due to previous crash.");
    }

    await crashMarker.writeAsString(DateTime.now().toIso8601String());
  } catch (e) {
    debugPrint("Failed to clean crash marker: $e");
  }
}

// Clear crash marker on success
void _clearCrashMarkerOnSuccess() {
  Future.microtask(() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final crashMarker = File(path.join(dir.path, '.last_crash'));
      if (await crashMarker.exists()) {
        await crashMarker.delete();
        debugPrint("Crash marker cleared — normal startup confirmed.");
      }
    } catch (e) {
      debugPrint("Failed to clear crash marker: $e");
    }
  });
}

// === App Widget ===
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final SyncService _syncService = SyncService();
  bool _firestoreReady = false;

  @override
  void initState() {
    super.initState();
    _initializeSyncSafely();
  }

  Future<void> _initializeSyncSafely() async {
    try {
      await FirebaseFirestore.instance.collection('ping').limit(1).get();
      if (mounted) {
        setState(() => _firestoreReady = true);
      }
      _syncService.start();
      debugPrint("SyncService started.");
    } catch (e) {
      debugPrint("Firestore not ready, retrying: $e");
      Future.delayed(const Duration(seconds: 5), _initializeSyncSafely);
    }
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }

  void _enterFullScreen() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      appWindow.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GM-D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                      body: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasData && snapshot.data != null) {
                  Future.microtask(() => _enterFullScreen());
                  return HomeRouter(user: snapshot.data!);
                }
                return const LoginPage();
              },
            ),
        '/login': (context) => const LoginPage(),
        '/admin': (context) => const AdminScreen(),
        '/dispensar': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return DispensarScreen(branchId: args['branchId']);
        },
        '/inventory': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return InventoryPage(branchId: args['branchId']);
        },
      },
    );
  }
}
