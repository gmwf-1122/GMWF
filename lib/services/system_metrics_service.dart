import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';

class SystemSnapshot {
  final double cpuPercent; // 0.0 - 1.0
  final double ramPercent; // 0.0 - 1.0
  final double usedRamGb;
  final double totalRamGb;
  final double diskPercent; // 0.0 - 1.0
  final double usedDiskGb;
  final double totalDiskGb;
  final double appProcessRamMb;
  final String cpuStatus;
  final String networkStatus;
  final DateTime timestamp;

  const SystemSnapshot({
    this.cpuPercent = 0.08,
    this.ramPercent = 0.25,
    this.usedRamGb = 4.0,
    this.totalRamGb = 16.0,
    this.diskPercent = 0.40,
    this.usedDiskGb = 80.0,
    this.totalDiskGb = 250.0,
    this.appProcessRamMb = 120.0,
    this.cpuStatus = 'Optimal',
    this.networkStatus = 'Stable',
    required this.timestamp,
  });
}

class SystemMetricsService {
  static final SystemMetricsService _instance = SystemMetricsService._internal();
  factory SystemMetricsService() => _instance;
  SystemMetricsService._internal();

  SystemSnapshot _currentSnapshot = SystemSnapshot(timestamp: DateTime.now());
  SystemSnapshot get currentSnapshot => _currentSnapshot;

  final StreamController<SystemSnapshot> _metricsController = StreamController<SystemSnapshot>.broadcast();
  Stream<SystemSnapshot> get metricsStream => _metricsController.stream;

  Timer? _timer;
  bool _isQuerying = false;

  void startMonitoring({Duration interval = const Duration(seconds: 6)}) {
    _timer?.cancel();
    _queryMetrics();
    _timer = Timer.periodic(interval, (_) => _queryMetrics());
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _queryMetrics() async {
    if (_isQuerying) return;
    _isQuerying = true;

    try {
      if (kIsWeb) {
        _isQuerying = false;
        return;
      }

      double cpu = 0.08;
      double usedRamGb = 4.0;
      double totalRamGb = 16.0;
      double usedDiskGb = 50.0;
      double totalDiskGb = 250.0;
      double appRamMb = 0.0;

      try {
        appRamMb = (io.ProcessInfo.currentRss / (1024 * 1024));
      } catch (_) {}

      if (io.Platform.isWindows) {
        final result = await io.Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'$os = Get-CimInstance Win32_OperatingSystem;'
          r'$proc = Get-CimInstance Win32_Processor;'
          r'$drive = Get-PSDrive -Name (Get-Location).Drive.Name;'
          r'Write-Host "RAM_TOTAL=$($os.TotalVisibleMemorySize)";'
          r'Write-Host "RAM_FREE=$($os.FreePhysicalMemory)";'
          r'Write-Host "CPU_LOAD=$($proc.LoadPercentage)";'
          r'Write-Host "DRIVE_USED=$($drive.Used)";'
          r'Write-Host "DRIVE_FREE=$($drive.Free)";'
        ]).timeout(const Duration(seconds: 4));

        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split(RegExp(r'[\r\n]+'));
          for (final line in lines) {
            if (line.startsWith('RAM_TOTAL=')) {
              final val = double.tryParse(line.substring('RAM_TOTAL='.length).trim());
              if (val != null && val > 0) totalRamGb = val / (1024 * 1024);
            } else if (line.startsWith('RAM_FREE=')) {
              final val = double.tryParse(line.substring('RAM_FREE='.length).trim());
              if (val != null && val > 0) {
                final freeGb = val / (1024 * 1024);
                usedRamGb = (totalRamGb - freeGb).clamp(0.1, totalRamGb);
              }
            } else if (line.startsWith('CPU_LOAD=')) {
              final val = double.tryParse(line.substring('CPU_LOAD='.length).trim());
              if (val != null) cpu = (val / 100.0).clamp(0.01, 1.0);
            } else if (line.startsWith('DRIVE_USED=')) {
              final val = double.tryParse(line.substring('DRIVE_USED='.length).trim());
              if (val != null && val > 0) usedDiskGb = val / (1024 * 1024 * 1024);
            } else if (line.startsWith('DRIVE_FREE=')) {
              final val = double.tryParse(line.substring('DRIVE_FREE='.length).trim());
              if (val != null && val > 0) {
                final freeDiskGb = val / (1024 * 1024 * 1024);
                totalDiskGb = usedDiskGb + freeDiskGb;
              }
            }
          }
        }
      }

      final ramPercent = (totalRamGb > 0 ? (usedRamGb / totalRamGb) : 0.25).clamp(0.01, 1.0);
      final diskPercent = (totalDiskGb > 0 ? (usedDiskGb / totalDiskGb) : 0.40).clamp(0.01, 1.0);

      String cpuStatus = 'Optimal';
      if (cpu > 0.75) {
        cpuStatus = 'High Load';
      } else if (cpu > 0.40) {
        cpuStatus = 'Moderate';
      } else {
        cpuStatus = 'Low';
      }

      _currentSnapshot = SystemSnapshot(
        cpuPercent: cpu,
        ramPercent: ramPercent,
        usedRamGb: double.parse(usedRamGb.toStringAsFixed(1)),
        totalRamGb: double.parse(totalRamGb.toStringAsFixed(1)),
        diskPercent: diskPercent,
        usedDiskGb: double.parse(usedDiskGb.toStringAsFixed(1)),
        totalDiskGb: double.parse(totalDiskGb.toStringAsFixed(1)),
        appProcessRamMb: double.parse(appRamMb.toStringAsFixed(1)),
        cpuStatus: cpuStatus,
        networkStatus: 'Stable',
        timestamp: DateTime.now(),
      );

      _metricsController.add(_currentSnapshot);
    } catch (e) {
      debugPrint('[SystemMetricsService] Error querying system metrics: $e');
    } finally {
      _isQuerying = false;
    }
  }
}
