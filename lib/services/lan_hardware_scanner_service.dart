// lib/services/lan_hardware_scanner_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'zkteco_network_service.dart';

class LanHardwareDevice {
  final String id;
  final String name;
  final String category; // 'biometric', 'printer', 'router', 'server'
  final String ipAddress;
  final int port;
  final bool isOnline;
  final int latencyMs;
  final String statusText;
  final DateTime lastChecked;

  LanHardwareDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.ipAddress,
    required this.port,
    required this.isOnline,
    required this.latencyMs,
    required this.statusText,
    required this.lastChecked,
  });

  LanHardwareDevice copyWith({
    bool? isOnline,
    int? latencyMs,
    String? statusText,
    DateTime? lastChecked,
  }) {
    return LanHardwareDevice(
      id: id,
      name: name,
      category: category,
      ipAddress: ipAddress,
      port: port,
      isOnline: isOnline ?? this.isOnline,
      latencyMs: latencyMs ?? this.latencyMs,
      statusText: statusText ?? this.statusText,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

class LanHardwareScannerService {
  static final LanHardwareScannerService _instance = LanHardwareScannerService._internal();
  factory LanHardwareScannerService() => _instance;
  LanHardwareScannerService._internal();

  Timer? _scanTimer;
  final StreamController<List<LanHardwareDevice>> _devicesStreamController =
      StreamController<List<LanHardwareDevice>>.broadcast();

  Stream<List<LanHardwareDevice>> get devicesStream => _devicesStreamController.stream;

  final List<LanHardwareDevice> _monitoredDevices = [
    // Biometric Readers
    LanHardwareDevice(
      id: 'bio_office',
      name: 'Office HQ Main Gate Scanner',
      category: 'biometric',
      ipAddress: '192.168.1.150',
      port: 4370,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),
    LanHardwareDevice(
      id: 'bio_dispensary',
      name: 'Dispensary Medical Scanner',
      category: 'biometric',
      ipAddress: '192.168.1.151',
      port: 4370,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),
    LanHardwareDevice(
      id: 'bio_madrassa',
      name: 'Madrassa & Hifz Gate Scanner',
      category: 'biometric',
      ipAddress: '192.168.1.152',
      port: 4370,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),
    LanHardwareDevice(
      id: 'bio_school',
      name: 'GMWF Model School Scanner',
      category: 'biometric',
      ipAddress: '192.168.1.153',
      port: 4370,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),
    LanHardwareDevice(
      id: 'bio_dasterkhwaan',
      name: 'Dasterkhwaan Kitchen Scanner',
      category: 'biometric',
      ipAddress: '192.168.1.154',
      port: 4370,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),
    LanHardwareDevice(
      id: 'bio_aux',
      name: 'Auxiliary Staff Scanner',
      category: 'biometric',
      ipAddress: '192.168.1.155',
      port: 4370,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),

    // Thermal Printers
    LanHardwareDevice(
      id: 'printer_dispensary',
      name: 'Dispensary Slip Printer',
      category: 'printer',
      ipAddress: '192.168.1.200',
      port: 9100,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),
    LanHardwareDevice(
      id: 'printer_donations',
      name: 'Donation Receipt Printer',
      category: 'printer',
      ipAddress: '192.168.1.201',
      port: 9100,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),

    // Core Router / Server
    LanHardwareDevice(
      id: 'lan_router',
      name: 'Main Gateway / Router',
      category: 'router',
      ipAddress: '192.168.1.1',
      port: 80,
      isOnline: false,
      latencyMs: 0,
      statusText: 'Checking...',
      lastChecked: DateTime.now(),
    ),
  ];

  List<LanHardwareDevice> get currentDevices => List.unmodifiable(_monitoredDevices);

  /// Starts background ping monitoring for all hardware devices every 15 seconds
  void startMonitoring({int intervalSeconds = 15}) {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      scanAllDevices();
    });
    // Trigger immediate initial scan
    scanAllDevices();
  }

  void stopMonitoring() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  /// Scans all configured LAN hardware devices
  Future<void> scanAllDevices() async {
    if (kIsWeb) return;

    for (int i = 0; i < _monitoredDevices.length; i++) {
      final dev = _monitoredDevices[i];
      final res = await _pingSingleDevice(dev);
      _monitoredDevices[i] = dev.copyWith(
        isOnline: res['isOnline'] == true,
        latencyMs: res['latencyMs'] as int? ?? 0,
        statusText: res['statusText'] as String? ?? 'Offline',
        lastChecked: DateTime.now(),
      );
    }

    _devicesStreamController.add(List.from(_monitoredDevices));
  }

  static Future<Map<String, dynamic>> _pingSingleDevice(LanHardwareDevice dev) async {
    if (kIsWeb) {
      return {'isOnline': false, 'latencyMs': 0, 'statusText': 'Web Mode'};
    }

    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(dev.ipAddress, dev.port, timeout: const Duration(seconds: 2));
      stopwatch.stop();
      socket.destroy();
      return {
        'isOnline': true,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'statusText': 'Connected (${stopwatch.elapsedMilliseconds}ms)',
      };
    } catch (_) {
      if (dev.category == 'biometric') {
        final isZkOnline = await ZkTecoNetworkService.pingDevice(dev.ipAddress, port: dev.port);
        stopwatch.stop();
        return {
          'isOnline': isZkOnline,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'statusText': isZkOnline ? 'Connected (UDP)' : 'Offline',
        };
      }

      stopwatch.stop();
      return {
        'isOnline': false,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'statusText': 'Offline',
      };
    }
  }
}
