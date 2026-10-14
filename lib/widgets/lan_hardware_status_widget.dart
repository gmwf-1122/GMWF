// lib/widgets/lan_hardware_status_widget.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/lan_hardware_scanner_service.dart';

class LanHardwareStatusWidget extends StatefulWidget {
  const LanHardwareStatusWidget({super.key});

  @override
  State<LanHardwareStatusWidget> createState() => _LanHardwareStatusWidgetState();
}

class _LanHardwareStatusWidgetState extends State<LanHardwareStatusWidget> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Only while this panel is on screen; the refresh button still scans on demand.
    LanHardwareScannerService().startMonitoring(intervalSeconds: 60);
  }

  @override
  void dispose() {
    // It kept pinging the devices every 15 s for the rest of the session after the panel closed.
    LanHardwareScannerService().stopMonitoring();
    super.dispose();
  }

  Future<void> _manualRefresh() async {
    setState(() => _isRefreshing = true);
    await LanHardwareScannerService().scanAllDevices();
    if (mounted) setState(() => _isRefreshing = false);
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'biometric':
        return Icons.fingerprint_rounded;
      case 'printer':
        return Icons.print_rounded;
      case 'router':
        return Icons.router_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'biometric':
        return SoftPalette.sky400; // Sky Blue
      case 'printer':
        return SoftPalette.violet500; // Purple
      case 'router':
        return SoftPalette.amber300; // Amber
      default:
        return SoftPalette.slate550;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = LanHardwareScannerService();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<LanHardwareDevice>>(
      stream: service.devicesStream,
      initialData: service.currentDevices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];
        final onlineCount = devices.where((d) => d.isOnline).length;
        final totalCount = devices.length;

        return Card(
          elevation: 0,
          color: isDark ? SoftPalette.slate900 : SoftPalette.gray50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? SoftPalette.slate800 : SoftPalette.slate150),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? SoftPalette.teal550.withOpacity(0.25) : SoftPalette.emerald50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SoftPalette.emerald350.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.hub_rounded, color: SoftPalette.emerald350, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LAN Hardware & Device Monitor',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? SoftPalette.gray50 : SoftPalette.slate900,
                            ),
                          ),
                          Text(
                            'Real-time network ping status for Biometrics, Thermal Printers & Gateway',
                            style: GoogleFonts.inter(fontSize: 12, color: isDark ? SoftPalette.slate350 : SoftPalette.slate550),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: onlineCount > 0
                            ? (isDark ? SoftPalette.emerald700.withOpacity(0.4) : SoftPalette.emerald50)
                            : (isDark ? SoftPalette.red700.withOpacity(0.4) : SoftPalette.red100t),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: onlineCount > 0 ? SoftPalette.emerald350 : SoftPalette.red400,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '$onlineCount / $totalCount Online',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: onlineCount > 0
                              ? (isDark ? SoftPalette.emerald300 : SoftPalette.emerald550)
                              : (isDark ? SoftPalette.red350 : SoftPalette.red550),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.refresh_rounded, size: 20, color: isDark ? SoftPalette.slate350 : SoftPalette.slate550),
                      tooltip: 'Ping All LAN Hardware',
                      onPressed: _isRefreshing ? null : _manualRefresh,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: isDark ? SoftPalette.slate800 : SoftPalette.slate100),
                const SizedBox(height: 12),

                // Device Cards Grid / List
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final dev = devices[i];
                    final catColor = _getCategoryColor(dev.category);

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: dev.isOnline
                            ? (isDark ? SoftPalette.slate800 : SoftPalette.gray50)
                            : (isDark ? SoftPalette.red800 : SoftPalette.red100m),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: dev.isOnline
                              ? (isDark ? SoftPalette.slate700 : SoftPalette.slate150)
                              : (isDark ? SoftPalette.red700 : SoftPalette.red200),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_getCategoryIcon(dev.category), color: catColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dev.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? SoftPalette.gray50 : SoftPalette.slate900,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'IP: ${dev.ipAddress}:${dev.port}',
                                      style: GoogleFonts.inter(fontSize: 11, color: isDark ? SoftPalette.slate350 : SoftPalette.slate550),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '• Checked: ${DateFormat('hh:mm:ss a').format(dev.lastChecked)}',
                                      style: GoogleFonts.inter(fontSize: 11, color: isDark ? SoftPalette.slate550 : SoftPalette.slate350),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: dev.isOnline
                                  ? (isDark ? SoftPalette.emerald700.withOpacity(0.5) : SoftPalette.emerald100)
                                  : (isDark ? SoftPalette.red700.withOpacity(0.5) : SoftPalette.red150m),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: dev.isOnline ? SoftPalette.emerald350.withOpacity(0.5) : SoftPalette.red400.withOpacity(0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: dev.isOnline ? SoftPalette.emerald350 : SoftPalette.red400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  dev.isOnline ? 'CONNECTED (${dev.latencyMs}ms)' : 'OFFLINE',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: dev.isOnline
                                        ? (isDark ? SoftPalette.emerald300 : SoftPalette.green550)
                                        : (isDark ? SoftPalette.red350 : SoftPalette.red550),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
