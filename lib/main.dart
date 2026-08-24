// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'pages/donations/donations_shared.dart';


import 'services/local_storage_service.dart';
import 'services/donations_local_storage.dart';
import 'services/offline_auth_service.dart' as offline_auth;
import 'services/zkteco_network_service.dart';
import 'realtime/server_sync_manager.dart';
import 'realtime/realtime_router.dart';
import 'widgets/gmwf_loading_view.dart';
import 'widgets/custom_title_bar.dart';
import 'tools/finance_v2_migration.dart';

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
    if (!kIsWeb && Platform.isWindows) {
      try { appWindow.show(); } catch (_) {}
    }
    FlutterError.presentError(details);
    _logError(details.exceptionAsString(), details.stack?.toString());
    _markLastCrash();
    // Report to Sentry
    Sentry.captureException(details.exception, stackTrace: details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (!kIsWeb && Platform.isWindows) {
      try { appWindow.show(); } catch (_) {}
    }
    _logError(error.toString(), stack.toString());
    _markLastCrash();
    // Report to Sentry
    Sentry.captureException(error, stackTrace: stack);
    return true;
  };
}

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  _installGlobalErrorHandlers();

  // Show window immediately on Desktop so app is NEVER hidden on launch or startup warning
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      doWhenWindowReady(() {
        appWindow.minSize = const Size(1280, 720);
        appWindow.alignment = Alignment.center;
        appWindow.title = "Gulzar Madina Dispensary";
        appWindow.show();
        appWindow.maximize();
      });
    } catch (e) {
      debugPrint('[Main] Window ready error: $e');
    }
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://1decf155927c0b93fcbc40447bb21a12@o4511376159014912.ingest.de.sentry.io/4511376169631824';
      options.tracesSampleRate = 1.0;
      options.environment = 'production';
    },
    appRunner: () async {
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
            .timeout(const Duration(seconds: 5))
            .catchError((e) {
              debugPrint('[Main] Firebase init warning: $e');
              return Firebase.app();
            });

      if (kIsWeb) {
        await Hive.initFlutter();
      } else if (Platform.isWindows) {
        final appSupportDir = await getApplicationSupportDirectory();
        final hiveDir = path.join(appSupportDir.path, 'gmwf_hive');
        LocalStorageService.setHiveDirectoryPath(hiveDir);
        await Hive.initFlutter(hiveDir);
      } else {
        final appSupportDir = await getApplicationSupportDirectory();
        LocalStorageService.setHiveDirectoryPath(appSupportDir.path);
        await Hive.initFlutter();
      }
      Hive.registerAdapter(TimestampAdapter());

      try {
        await Hive.openBox('app_settings');
      } catch (hiveErr) {
        debugPrint('[Main] Hive app_settings box error: $hiveErr');
      }

      await Future.wait<dynamic>([
        LocalStorageService.init(),
        DonationsLocalStorage.init(),
        ServerSyncManager.initHive(),
        RealtimeRouter.init(),
      ]).catchError((e) {
        debugPrint('[Main] Non-critical service init warning: $e');
        return <dynamic>[];
      });

      await LocalStorageService.seedLocalAdmins();
    } catch (e, st) {
      debugPrint('[Main] Pre-init error caught safely: $e');
      _logError('Pre-init error: $e', st.toString());
    }

    runApp(const ProviderScope(child: MyApp()));
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
  if (kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST')) {
    _startInit();
  }
}

Future<void> _startInit() async {
  try {
    debugPrint("[Init] Starting fast async setup...");
    
    // 1. Firebase (fast 5s timeout)
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 5))
        .catchError((e) {
          debugPrint('[Init] Firebase init warning/timeout: $e');
          return Firebase.app();
        });

    // 2. Hive
    if (kIsWeb) {
      await Hive.initFlutter();
    } else if (Platform.isWindows) {
      final appSupportDir = await getApplicationSupportDirectory();
      final hiveDir = path.join(appSupportDir.path, 'gmwf_hive');
      await Hive.initFlutter(hiveDir);
    } else {
      await Hive.initFlutter();
    }
    Hive.registerAdapter(TimestampAdapter());

    // 3. Essential local services
    await Future.wait<dynamic>([
      LocalStorageService.init(),
      DonationsLocalStorage.init(),
      ServerSyncManager.initHive(),
      RealtimeRouter.init(),
      PdfAssetCache.preload(),
    ]).catchError((e) {
      debugPrint('[Init] Non-critical service init warning: $e');
      return <dynamic>[];
    });

      await LocalStorageService.seedLocalAdmins();
      await _clearCrashMarkerOnSuccess();

      // Start embedded ZKTeco biometric listener & Firestore punch stream immediately
      if (!kIsWeb) {
        unawaited(ZkTecoNetworkService.startServer().catchError((e) {
          debugPrint('[Init] ZKTeco background server start error: $e');
          return false;
        }));
      }

      // Launch background tasks without blocking UI splash removal
      unawaited(_runBackgroundCleanups());

      debugPrint("[Init] Fast setup success. Removing splash & moving to home.");
      if (mounted) {
        FlutterNativeSplash.remove();
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushReplacementNamed('/home');
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e, st) {
      debugPrint("[Init] Fast init completed with warning: $e");
      debugPrint("[Init] STACK TRACE: $st");
      await _logError("Init Warning: $e", st.toString());
      if (mounted) {
        FlutterNativeSplash.remove();
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushReplacementNamed('/home');
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    }
  }

  static Future<void> _runBackgroundCleanups() async {
    try {
      await FinanceV2Migration.runMigration();
      await LocalStorageService.forceDeduplicatePatients();

      if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
        final box = Hive.box(DonationsLocalStorage.donationsBox);
        final nestedKeys = box.keys.where((k) => k.toString().split('__').length > 3).toList();
        if (nestedKeys.isNotEmpty) {
          await box.deleteAll(nestedKeys);
          await box.flush();
        }
      }
    } catch (cleanupErr) {
      debugPrint('[CLEANUP] Error during background cleanup: $cleanupErr');
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
    if (!Hive.isBoxOpen('app_settings')) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        title: 'GM-D',
        debugShowCheckedModeBanner: false,
        routes: {
          '/home': (context) => const AuthHomeWrapper(),
          '/login': (context) => const LoginPage(),
        },
        home: const AuthHomeWrapper(),
      );
    }
    return ValueListenableBuilder(
      valueListenable: Hive.box('app_settings').listenable(keys: [
        'custom_accent_color',
        'card_radius',
        'is_dark_mode',
        'language',
        'font_scale',
      ]),
      builder: (context, Box box, child) {
        final colorHex = box.get('custom_accent_color') as String?;

        Color seedColor = AppColors.primary;
        if (colorHex != null && colorHex.isNotEmpty) {
          try {
            final hex = colorHex.replaceAll('#', '');
            seedColor = Color(int.parse('FF$hex', radix: 16));
          } catch (_) {}
        }

        final cardRadius = box.get('card_radius', defaultValue: 16.0) as double;
        final isDarkMode = box.get('is_dark_mode', defaultValue: false) as bool;
        final language = box.get('language', defaultValue: 'en') as String;
        final fontFamily = GoogleFonts.dmSans().fontFamily;
        final isUrdu = language == 'ur';

        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'GM-D',
          debugShowCheckedModeBanner: false,
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
          locale: Locale(language),
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            fontFamily: fontFamily,
            colorScheme: ColorScheme.fromSeed(
              seedColor: seedColor,
              primary: seedColor,
              secondary: AppColors.navy,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFEAEFF5),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cardRadius),
              ),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cardRadius),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                borderSide: const BorderSide(color: AppColors.gray200, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                borderSide: const BorderSide(color: AppColors.gray200, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                borderSide: BorderSide(color: seedColor, width: 2.0),
              ),
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray600),
              hintStyle: const TextStyle(fontSize: 14, color: AppColors.gray400),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: seedColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                elevation: 3,
                shadowColor: seedColor.withValues(alpha: 0.35),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
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
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: fontFamily,
            colorScheme: ColorScheme.fromSeed(
              seedColor: seedColor,
              primary: seedColor,
              secondary: AppColors.navy,
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF090C10),
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFF161B22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cardRadius),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF161B22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cardRadius),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF21262D),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                borderSide: const BorderSide(color: Color(0xFF30363D), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                borderSide: const BorderSide(color: Color(0xFF30363D), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                borderSide: BorderSide(color: seedColor, width: 2.0),
              ),
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8B949E)),
              hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF6E7681)),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: seedColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                elevation: 3,
                shadowColor: seedColor.withValues(alpha: 0.4),
              ),
            ),
          ),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final scale = Hive.isBoxOpen('app_settings')
                ? Hive.box('app_settings').get('font_scale', defaultValue: 1.0) as double
                : 1.0;

            final appDirection = isUrdu ? TextDirection.rtl : TextDirection.ltr;
            final appMediaQuery = mediaQuery.copyWith(
              textScaler: TextScaler.linear(scale),
            );

            final adjustedChild = MediaQuery(
              data: appMediaQuery,
              child: Directionality(
                textDirection: appDirection,
                child: child!,
              ),
            );

            if (!kIsWeb && Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
              return MediaQuery(
                data: appMediaQuery,
                child: Directionality(
                  textDirection: appDirection,
                  child: Material(
                    color: isDarkMode ? const Color(0xFF090C10) : const Color(0xFFEAEFF5),
                    child: Overlay(
                      initialEntries: [
                        OverlayEntry(
                          builder: (context) => Column(
                            children: [
                              const CustomTitleBar(),
                              Expanded(child: adjustedChild),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return adjustedChild;
          },
          home: const AuthHomeWrapper(),
          onUnknownRoute: (settings) {
            return MaterialPageRoute(
              builder: (context) => const AuthHomeWrapper(),
            );
          },
          routes: {
            '/home': (context) => const AuthHomeWrapper(),
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
      },
    );
  }
}

class AuthHomeWrapper extends StatefulWidget {
  const AuthHomeWrapper({super.key});

  @override
  State<AuthHomeWrapper> createState() => _AuthHomeWrapperState();
}

class _SessionData {
  final User? user;
  final Map<String, dynamic>? localUser;
  _SessionData({this.user, this.localUser});
}

class _AuthHomeWrapperState extends State<AuthHomeWrapper> {
  late final Future<_SessionData> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _determineSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
    });
  }

  Future<_SessionData> _determineSession() async {
    try {
      if (!Hive.isBoxOpen('app_settings')) {
        try {
          await Hive.openBox('app_settings');
        } catch (_) {}
      }

      // 1. Check if Firebase currentUser is available immediately
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final localData = _getLocalUserData(currentUser);
        return _SessionData(user: currentUser, localUser: localData);
      }

      // 2. Wait at most 2 seconds for authStateChanges event (prevents infinite hanging)
      final streamUser = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null, orElse: () => null)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);

      if (streamUser != null) {
        final localData = _getLocalUserData(streamUser);
        return _SessionData(user: streamUser, localUser: localData);
      }

      // 3. Fallback to cached offline user credentials (2s timeout)
      final offlineUser = await offline_auth.OfflineAuthService.getCachedUserData()
          .timeout(const Duration(seconds: 2), onTimeout: () => null);

      if (offlineUser != null &&
          (offlineUser['uid'] != null ||
           offlineUser['username'] != null ||
           offlineUser['email'] != null)) {
        return _SessionData(user: null, localUser: offlineUser);
      }
    } catch (e) {
      debugPrint('[AuthHomeWrapper] Session resolution warning: $e');
    }
    return _SessionData(user: null, localUser: null);
  }

  Map<String, dynamic>? _getLocalUserData(User user) {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final cached = Hive.box('app_settings').get('user_data');
        if (cached is Map) {
          final m = Map<String, dynamic>.from(cached);
          final r = (m['role'] ?? '').toString().toLowerCase().trim();
          final uUid = (m['uid'] ?? '').toString();
          final uEmail = (m['email'] ?? '').toString().toLowerCase().trim();
          if (r.isNotEmpty && r != 'unknown' && (uUid == user.uid || uEmail == (user.email ?? '').toLowerCase())) {
            return m;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SessionData>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GmwfLoadingView(
            message: 'Verifying Session...',
            subMessage: 'Connecting to GMWF Security Core',
          );
        }

        final data = snapshot.data;
        if (data != null && (data.user != null || data.localUser != null)) {
          return HomeRouter(user: data.user, localUser: data.localUser);
        }

        return const LoginPage();
      },
    );
  }
}