// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';

import 'pages/login_page.dart';
import 'pages/home_router.dart';
import 'pages/admin_screen.dart';
import 'pages/chairman_screen.dart';
import 'pages/dispensar_screen.dart';
import 'pages/inventory.dart';

import 'services/local_storage_service.dart';

// Global navigator key — used to show Flushbar/SnackBar from anywhere (safely)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class TimestampAdapter extends TypeAdapter<Timestamp> {
  @override
  final int typeId = 100;

  @override
  Timestamp read(BinaryReader reader) {
    final seconds = reader.readInt();
    final nanoseconds = reader.readInt();
    return Timestamp(seconds, nanoseconds);
  }

  @override
  void write(BinaryWriter writer, Timestamp obj) {
    writer.writeInt(obj.seconds);
    writer.writeInt(obj.nanoseconds);
  }
}

Future<void> _logError(String message, [String? stack]) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final logFile = File(path.join(dir.path, 'gmwf_crash.log'));
    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] ERROR: $message\nSTACK: ${stack ?? ''}\n\n';
    await logFile.writeAsString(entry, mode: FileMode.append);
    debugPrint("Error logged to file: $message");
  } catch (e) {
    debugPrint("Unable to write crash log: $e");
  }
}

Future<void> _markLastCrash() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final crashMarker = File(path.join(dir.path, '.last_crash'));
    await crashMarker.writeAsString(DateTime.now().toIso8601String());
    debugPrint("Crash marker written");
  } catch (e) {
    debugPrint("Failed to write crash marker: $e");
  }
}

Future<void> _clearCrashMarkerOnSuccess() async {
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
}

void _showCrashScreen(Object error, StackTrace stack) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      debugPrint("Cannot show crash screen: navigatorKey context is null");
      return;
    }

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
                    'GMWF — An error occurred',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'An unexpected error happened. The app logged the problem. You can try to continue using the app or restart it manually.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Log saved. Send the gmwf_crash.log file to support if the issue persists.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () {
                      WidgetsBinding.instance.reassembleApplication();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload UI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  });
}

void _installGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _logError(details.exceptionAsString(), details.stack?.toString());
    _markLastCrash();
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _logError(error.toString(), stack.toString());
    _markLastCrash();
    return true;
  };
}

Future<void> main() async {
  _installGlobalErrorHandlers();

  WidgetsFlutterBinding.ensureInitialized();

  // Show loading screen immediately
  runApp(const _StartupLoadingScreen());

  try {
    debugPrint("[main] Starting initialization...");

    debugPrint("[main] 1. Initializing Firebase...");
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("[main] Firebase initialized");

    debugPrint("[main] 2. Initializing Hive...");
    await Hive.initFlutter();
    Hive.registerAdapter(TimestampAdapter());
    debugPrint("[main] Hive initialized");

    debugPrint("[main] 3. Opening Hive boxes...");
    await LocalStorageService.init();
    debugPrint("[main] Hive boxes opened");

    debugPrint("[main] 4. Seeding local admins...");
    await LocalStorageService.seedLocalAdmins();
    debugPrint("[main] Admins seeded");

    debugPrint("[main] 5. Running patient deduplication...");
    await LocalStorageService.forceDeduplicatePatients();
    debugPrint("[main] Patient deduplication completed");

    await _clearCrashMarkerOnSuccess();
    debugPrint("[main] Startup sequence completed successfully");
  } catch (e, st) {
    await _logError("App initialization failed: $e", st.toString());
    await _markLastCrash();
    debugPrint("[main] CRITICAL STARTUP ERROR: $e\n$st");

    // Show crash screen
    _showCrashScreen(e, st);
    return; // Don't continue to MyApp if init failed
  }

  // Only reach here if init succeeded
  runApp(const MyApp());

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        doWhenWindowReady(() {
          const minSize = Size(1280, 720);
          appWindow.minSize = minSize;
          appWindow.alignment = Alignment.center;
          appWindow.title = "Gulzar Madina Dispensary";
          appWindow.maximize();
          appWindow.show();
        });
      } catch (e, st) {
        _logError("Window setup failed: $e", st.toString());
      }
    });
  }
}

// Simple loading screen shown during startup
class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logo/gmwf.png',
                height: 120,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_pharmacy,
                  size: 100,
                  color: Color(0xFF00695C),
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text(
                "GMWF is starting...",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              const Text(
                "Initializing services...",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  void _enterFullScreen() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        appWindow.maximize();
      } catch (e, st) {
        _logError("Failed to maximize window: $e", st.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'GM-D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _StartupLoadingScreen();
                }

                if (snapshot.hasData && snapshot.data != null) {
                  Future.microtask(() => _enterFullScreen());
                  return HomeRouter(user: snapshot.data!);
                }

                return const LoginPage();
              },
            ),
        '/login': (context) => const LoginPage(),
        '/admin': (context) => AdminScreen(branchId: 'all'),
        '/chairman': (context) => const ChairmanScreen(),
        '/dispensar': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return DispensarScreen(branchId: args?['branchId'] ?? 'unknown');
        },
        '/inventory': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return InventoryPage(branchId: args?['branchId'] ?? 'unknown');
        },
      },
    );
  }
}