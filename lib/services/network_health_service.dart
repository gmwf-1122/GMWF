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
  bool _isChecking = false;

  void start() {
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
      if (!hasInterface && !isDesktop) {
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
      if (kIsWeb) {
        _updateState(NetworkQualityState.onlineStable);
        return;
      }
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);

      final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
      if (!hasInterface && !isDesktop) {
        _updateState(NetworkQualityState.offline);
        return;
      }

      final isPingOk = await _pingHighAvailabilityHost();

      if (isPingOk) {
        // Promote immediately after 1 stable ping on all platforms
        _updateState(NetworkQualityState.onlineStable);
      } else {
        _updateState(NetworkQualityState.offline);
      }
    } catch (e) {
      debugPrint('[NetworkHealthService] Health check exception: $e');
      _updateState(NetworkQualityState.offline);
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
      final latencyThreshold = _isMobilePlatform ? 7000 : 3500;

      // 1. Android/OS-native captive portal probe: connectivitycheck.gstatic.com (generate_204)
      bool ok = false;
      try {
        final client = HttpClient()..connectionTimeout = pingTimeout;
        final req = await client.getUrl(Uri.parse('http://connectivitycheck.gstatic.com/generate_204')).timeout(pingTimeout);
        final resp = await req.close().timeout(pingTimeout);
        client.close(force: true);
        if (resp.statusCode == 204 || resp.statusCode == 200) {
          ok = true;
        }
      } catch (_) {}

      // 2. DNS resolve probe to google.com / cloudflare.com
      if (!ok) {
        try {
          final res = await InternetAddress.lookup('google.com').timeout(pingTimeout);
          if (res.isNotEmpty && res[0].rawAddress.isNotEmpty) {
            ok = true;
          }
        } catch (_) {}
      }

      // 3. Socket probe: Cloudflare 1.1.1.1 HTTPS (port 443) fallback
      if (!ok) {
        ok = await Socket.connect('1.1.1.1', 443, timeout: pingTimeout)
            .then((socket) {
              socket.destroy();
              return true;
            })
            .catchError((_) => false);
      }

      // 4. Secondary socket probe: Google 8.8.8.8 HTTPS (port 443)
      if (!ok) {
        ok = await Socket.connect('8.8.8.8', 443, timeout: pingTimeout)
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
