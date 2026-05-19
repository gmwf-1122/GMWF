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
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'constants/colors.dart';

import 'firebase_options.dart';

import 'pages/login_page.dart';
import 'pages/home_router.dart';
import 'pages/overview.dart';
import 'pages/dispensary/dispensar/dispensar_screen.dart';
import 'pages/dispensary/dispensar/inventory.dart';
import 'pages/donations/donations_screen.dart';

import 'services/local_storage_service.dart';
import 'services/donations_local_storage.dart';
import 'services/offline_auth_service.dart' as offline_auth;
import 'realtime/server_sync_manager.dart';
import 'widgets/gmwf_loading_view.dart';
import 'widgets/custom_title_bar.dart';

import 'constants/navigator_key.dart';

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
  if (kIsWeb) return;
  try {
    final dir = await getApplicationSupportDirectory();
    final logFile = File(path.join(dir.path, 'gmwf_crash.log'));
    final timestamp = DateTime.now().toIso8601String();
    final entry =
        '[$timestamp] ERROR: $message\nSTACK: ${stack ?? ''}\n\n';
    await logFile.writeAsString(entry, mode: FileMode.append);
    debugPrint("Error logged to file: $message");
  } catch (e) {
    debugPrint("Unable to write crash log: $e");
  }
}

Future<void> _markLastCrash() async {
  if (kIsWeb) return;
  try {
    final dir = await getApplicationSupportDirectory();
    final crashMarker = File(path.join(dir.path, '.last_crash'));
    await crashMarker.writeAsString(DateTime.now().toIso8601String());
  } catch (e) {
    debugPrint("Failed to write crash marker: $e");
  }
}

Future<void> _clearCrashMarkerOnSuccess() async {
  if (kIsWeb) return;
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
  // Ensure we show the window if it's hidden
  if (!kIsWeb && Platform.isWindows) {
    try { appWindow.show(); } catch (_) {}
  }

  final crashApp = MaterialApp(
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
              const Text('GMWF — Startup Error',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(
                'The app failed to start:\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => WidgetsBinding.instance.reassembleApplication(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Startup'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  try {
                    // Try to kill any other gmwf processes that might be locking the files.
                    // This uses taskkill on Windows.
                    await Process.run('taskkill', ['/f', '/im', 'gmwf.exe']);
                    // The current process might also be killed, which is fine as it allows a clean restart.
                  } catch (e) {
                    debugPrint("Failed to kill processes: $e");
                  }
                },
                icon: const Icon(Icons.cleaning_services, color: Colors.orange),
                label: const Text('Kill Background Processes & Clear Locks', style: TextStyle(color: Colors.orange)),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await LocalStorageService.clearAllData();
                    WidgetsBinding.instance.reassembleApplication();
                  } catch (e) {
                    debugPrint("Factory reset failed: $e");
                  }
                },
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text('Factory Reset (Wipe All Data)', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // If we haven't started an app yet, start this one immediately
  runApp(crashApp);
}

void _installGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _logError(details.exceptionAsString(), details.stack?.toString());
    _markLastCrash();
    // Report to Sentry
    Sentry.captureException(details.exception, stackTrace: details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _logError(error.toString(), stack.toString());
    _markLastCrash();
    // Report to Sentry
    Sentry.captureException(error, stackTrace: stack);
    return true;
  };
}

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://1decf155927c0b93fcbc40447bb21a12@o4511376159014912.ingest.de.sentry.io/4511376169631824';
      options.tracesSampleRate = 1.0;
      options.environment = 'production';
    },
    appRunner: () async {
      WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
      _installGlobalErrorHandlers();

      // Show window immediately
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        doWhenWindowReady(() {
          appWindow.minSize = const Size(1280, 720);
          appWindow.alignment = Alignment.center;
          appWindow.title = "Gulzar Madina Dispensary";
          appWindow.show();
          appWindow.maximize();
        });
      }

      runApp(const MyApp());
    },
  );
}

/// A dedicated screen that handles the async initialization of the app
/// while showing a loading indicator.
class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});
  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  bool _hasError = false;
  String _errorMsg = "";

  @override
  void initState() {
    super.initState();
    _startInit();
  }

  Future<void> _startInit() async {
    try {
      debugPrint("[Init] Starting async setup...");
      
      // 1. Firebase (with timeout)
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
          .timeout(const Duration(seconds: 15));

      // 2. Hive
      if (!kIsWeb && Platform.isWindows) {
        final appSupportDir = await getApplicationSupportDirectory();
        final hiveDir = path.join(appSupportDir.path, 'gmwf_hive');
        await Hive.initFlutter(hiveDir);
      } else {
        await Hive.initFlutter();
      }
      Hive.registerAdapter(TimestampAdapter());

      // 3. Services
      await Future.wait([
        LocalStorageService.init(),
        DonationsLocalStorage.init(),
        ServerSyncManager.initHive(),
      ]).timeout(const Duration(seconds: 15));

      await LocalStorageService.seedLocalAdmins();
      await LocalStorageService.forceDeduplicatePatients();
      await _clearCrashMarkerOnSuccess();

      debugPrint("[Init] Success. Moving to home.");
      if (mounted) {
        FlutterNativeSplash.remove();
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e, st) {
      debugPrint("[Init] CRITICAL ERROR: $e");
      await _logError("Init Failed: $e", st.toString());
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Return the error view directly if init fails
      return _buildErrorView();
    }

    // While initializing, show the GMWF loading view
    return const GmwfLoadingView();
  }

  Widget _buildErrorView() {
    return Scaffold(
      backgroundColor: Colors.red[50],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 72, color: Colors.red),
              const SizedBox(height: 24),
              const Text('GMWF — Startup Error', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(_errorMsg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => _startInit(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Startup'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  await Process.run('taskkill', ['/f', '/im', 'gmwf.exe']);
                },
                icon: const Icon(Icons.cleaning_services, color: Colors.orange),
                label: const Text('Kill Background Processes', style: TextStyle(color: Colors.orange)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main App ──────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'GM-D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: GoogleFonts.dmSans().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.navy,
        ),
        scaffoldBackgroundColor: AppColors.gray50,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.gray200, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.gray200, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray600),
          hintStyle: const TextStyle(fontSize: 14, color: AppColors.gray400),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      builder: (context, child) {
        if (!kIsWeb && Platform.isWindows) {
          return Scaffold(
            body: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Column(
                    children: [
                      const CustomTitleBar(),
                      Expanded(child: child!),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return child!;
      },
      initialRoute: '/',
      routes: {
        '/': (context) => const InitializationScreen(),
        '/home': (context) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const GmwfLoadingView();
                }
                if (snapshot.hasData && snapshot.data != null) {
                  return HomeRouter(user: snapshot.data!);
                }

                return FutureBuilder<Map<String, dynamic>?>(
                  future: offline_auth.OfflineAuthService.getCachedUserData(),
                  builder: (context, cachedSnap) {
                    if (cachedSnap.connectionState == ConnectionState.waiting) {
                      return const GmwfLoadingView();
                    }
                    if (cachedSnap.hasData && cachedSnap.data != null) {
                      return HomeRouter(user: null, localUser: cachedSnap.data!);
                    }
                    return const LoginPage();
                  },
                );
              },
            ),
        '/login': (context) => const LoginPage(),
        '/admin': (context) => const OverviewScreen(),
        '/chairman': (context) => const OverviewScreen(),
        '/donations': (context) => const DonationsScreen.embedded(),
        '/dispensar': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>?;
          return DispensarScreen(branchId: args?['branchId'] ?? 'unknown');
        },
        '/inventory': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>?;
          return InventoryPage(branchId: args?['branchId'] ?? 'unknown');
        },
      },
    );
  }
}