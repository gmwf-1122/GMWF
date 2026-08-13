// lib/widgets/lan_hardware_status_widget.dart

import 'package:flutter/material.dart';
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
    LanHardwareScannerService().startMonitoring();
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
        return const Color(0xFF0EA5E9); // Sky Blue
      case 'printer':
        return const Color(0xFF8B5CF6); // Purple
      case 'router':
        return const Color(0xFFF59E0B); // Amber
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = LanHardwareScannerService();

    return StreamBuilder<List<LanHardwareDevice>>(
      stream: service.devicesStream,
      initialData: service.currentDevices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];
        final onlineCount = devices.where((d) => d.isOnline).length;
        final totalCount = devices.length;

        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.hub_rounded, color: Color(0xFF10B981), size: 22),
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
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Real-time network ping status for Biometrics, Thermal Printers & Gateway',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: onlineCount > 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: onlineCount > 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Text(
                        '$onlineCount / $totalCount Online',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: onlineCount > 0 ? const Color(0xFF047857) : const Color(0xFFB91C1C),
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
                          : const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Ping All LAN Hardware',
                      onPressed: _isRefreshing ? null : _manualRefresh,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
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
                        color: dev.isOnline ? const Color(0xFFF8FAFC) : const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: dev.isOnline ? const Color(0xFFE2E8F0) : const Color(0xFFFECDD3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.1),
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
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'IP: ${dev.ipAddress}:${dev.port}',
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '• Checked: ${DateFormat('hh:mm:ss a').format(dev.lastChecked)}',
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
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
                              color: dev.isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: dev.isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  dev.isOnline ? 'CONNECTED (${dev.latencyMs}ms)' : 'OFFLINE',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: dev.isOnline ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
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
