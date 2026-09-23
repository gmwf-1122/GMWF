// lib/services/network_health_service.dart

import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum NetworkQualityState { onlineStable, onlineUnstable, offline }

class NetworkHealthService {
  static final NetworkHealthService _instance = NetworkHealthService._internal();
  factory NetworkHealthService() => _instance;
  NetworkHealthService._internal();

  final _healthController = StreamController<NetworkQualityState>.broadcast();
  Stream<NetworkQualityState> get onHealthChanged => _healthController.stream;

  NetworkQualityState _currentState = NetworkQualityState.onlineStable;
  NetworkQualityState get currentState => _currentState;

  bool get isStableOnline => _currentState == NetworkQualityState.onlineStable;
  bool get isUnstableOrOffline => _currentState != NetworkQualityState.onlineStable;
  bool get isOffline => _currentState == NetworkQualityState.offline;

  Timer? _pingTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  int _consecutiveStablePings = 0;
  bool _isChecking = false;

  void start() {
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) {
        _consecutiveStablePings = 0;
        _updateState(NetworkQualityState.offline);
      } else {
        checkHealthNow();
      }
    });

    _pingTimer?.cancel();
    // Relaxed 90-second fallback heartbeat (OS connectivity events handle immediate switches)
    _pingTimer = Timer.periodic(const Duration(seconds: 90), (_) => checkHealthNow());
    checkHealthNow();
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _connSub?.cancel();
    _connSub = null;
  }

  Future<void> checkHealthNow() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);

      final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
      if (!hasInterface && !isDesktop) {
        _consecutiveStablePings = 0;
        _updateState(NetworkQualityState.offline);
        return;
      }

      final isPingOk = await _pingHighAvailabilityHost();

      if (isPingOk) {
        _consecutiveStablePings++;
        // On mobile, promote immediately after 1 stable ping (cellular is inherently less stable).
        // On desktop, debounce with 2 consecutive stable pings (~10s window).
        final threshold = (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ? 1 : 2;
        if (_consecutiveStablePings >= threshold || _currentState == NetworkQualityState.onlineStable) {
          _updateState(NetworkQualityState.onlineStable);
        }
      } else {
        _consecutiveStablePings = 0;
        _updateState(NetworkQualityState.onlineUnstable);
      }
    } catch (e) {
      debugPrint('[NetworkHealthService] Health check exception: $e');
      _consecutiveStablePings = 0;
      _updateState(NetworkQualityState.onlineUnstable);
    } finally {
      _isChecking = false;
    }
  }

  /// On mobile, we use a longer timeout since cellular latency is higher.
  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<bool> _pingHighAvailabilityHost() async {
    try {
      if (kIsWeb) return true; // Web browsers handle HTTP timeouts natively

      final stopwatch = Stopwatch()..start();
      // Mobile gets a longer timeout to accommodate cellular latency
      final pingTimeout = Duration(milliseconds: _isMobilePlatform ? 4000 : 2500);
      final latencyThreshold = _isMobilePlatform ? 6000 : 3500;

      // Primary probe: Cloudflare 1.1.1.1 HTTPS (port 443) — open everywhere, never blocked by DNS filters
      bool ok = await Socket.connect('1.1.1.1', 443, timeout: pingTimeout)
          .then((socket) {
            socket.destroy();
            return true;
          })
          .catchError((_) => false);

      // Secondary probe: Google 8.8.8.8 HTTPS (port 443)
      if (!ok) {
        ok = await Socket.connect('8.8.8.8', 443, timeout: pingTimeout)
            .then((socket) {
              socket.destroy();
              return true;
            })
            .catchError((_) => false);
      }

      // Tertiary probe: Google DNS 8.8.8.8 port 53 fallback
      if (!ok) {
        ok = await Socket.connect('8.8.8.8', 53, timeout: pingTimeout)
            .then((socket) {
              socket.destroy();
              return true;
            })
            .catchError((_) => false);
      }

      stopwatch.stop();

      if (ok && stopwatch.elapsedMilliseconds > latencyThreshold) {
        debugPrint('[NetworkHealthService] High latency detected: ${stopwatch.elapsedMilliseconds}ms');
        return false;
      }

      return ok;
    } catch (_) {
      return false;
    }
  }

  void _updateState(NetworkQualityState newState) {
    if (_currentState != newState) {
      debugPrint('[NetworkHealthService] State transition: $_currentState ➔ $newState');
      _currentState = newState;
      if (!_healthController.isClosed) {
        _healthController.add(newState);
      }
    }
  }
}
