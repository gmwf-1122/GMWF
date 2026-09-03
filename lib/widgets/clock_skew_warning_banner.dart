// lib/widgets/clock_skew_warning_banner.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gmwf/services/camp_session_service.dart';

class ClockSkewWarningBanner extends StatefulWidget {
  final String? branchId;
  const ClockSkewWarningBanner({super.key, this.branchId});

  @override
  State<ClockSkewWarningBanner> createState() => _ClockSkewWarningBannerState();
}

class _ClockSkewWarningBannerState extends State<ClockSkewWarningBanner> {
  bool _dismissed = false;
  static bool _isDialogActive = false;

  void _showDetailsDialog(BuildContext context, ClockSkewInfo info) {
    if (_isDialogActive) return;
    _isDialogActive = true;

    final localTimeStr = DateFormat('hh:mm:ss a (dd MMM yyyy)').format(info.localTime);
    final serverTimeStr = DateFormat('hh:mm:ss a (dd MMM yyyy)').format(info.authoritativeTime);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 24, 20),
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incorrect Clock / Shift Detected',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16.5,
                        color: Color(0xFF991B1B),
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Please verify your Windows date and time',
                      style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your computer\'s system clock does not match the real internet/server time. '
                'This causes tokens to be assigned to the wrong shift (e.g. morning instead of evening). '
                'The app has automatically calibrated internal timestamps, but you can also re-align existing tokens below.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _infoRow('🖥️ Computer Local Clock:', localTimeStr, const Color(0xFFDC2626), isBold: true),
                    const Divider(height: 18),
                    _infoRow('🌐 Authoritative Internet Time:', serverTimeStr, const Color(0xFF059669), isBold: true),
                    const Divider(height: 18),
                    _infoRow('⏱️ Clock Drift Offset:', info.formattedOffset, const Color(0xFFD97706)),
                    const Divider(height: 18),
                    _infoRow('🎯 Active Clinical Shift:', '${info.authoritativeSession.toUpperCase()} SHIFT', const Color(0xFF0F6C5A), isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF2563EB), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Set your Windows Time to "Set time automatically" in Windows Settings so your PC clock stays accurate.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF1E40AF), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _dismissed = true);
            },
            child: const Text('Dismiss', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          if (widget.branchId != null && widget.branchId!.isNotEmpty) ...[
            ElevatedButton.icon(
              onPressed: () async {
                final count = await CampSessionService.realignOrphanedTokens(
                  branchId: widget.branchId!,
                  includeCompleted: true,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Successfully aligned $count token(s) into current active shift!'),
                      backgroundColor: const Color(0xFF059669),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: const Text('Realign Tokens to Active Shift'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F6C5A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final count = await CampSessionService.restoreRealignedTokens(
                  branchId: widget.branchId!,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🔄 Successfully restored $count token(s) back to original dates!'),
                      backgroundColor: const Color(0xFF0284C7),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.history_rounded, size: 16),
              label: const Text('Undo / Restore Original Dates'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
          OutlinedButton.icon(
            onPressed: () async {
              final syncTime = await CampSessionService.syncInternetTime();
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (syncTime != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🌐 Internet Date & Time synced: ${DateFormat('hh:mm:ss a (dd MMM yyyy)').format(syncTime)}'),
                      backgroundColor: const Color(0xFF0F6C5A),
                    ),
                  );
                } else {
                  CampSessionService.checkClockSkew();
                }
              }
            },
            icon: const Icon(Icons.sync_rounded, size: 16),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F6C5A),
              side: const BorderSide(color: Color(0xFF0F6C5A)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            label: const Text('Sync Internet Time'),
          ),
        ],
      ),
    ).whenComplete(() => _isDialogActive = false);
  }

  Widget _infoRow(String label, String value, Color valueColor, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return ValueListenableBuilder<ClockSkewInfo?>(
      valueListenable: CampSessionService.clockSkewNotifier,
      builder: (context, info, _) {
        if (info == null || !info.isSignificantDrift) {
          return const SizedBox.shrink();
        }

        final localFmt = DateFormat('hh:mm a').format(info.localTime);
        final serverFmt = DateFormat('hh:mm a').format(info.authoritativeTime);
        final shiftName = info.authoritativeSession.toUpperCase();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
            boxShadow: const [
              BoxShadow(color: Color(0x14D97706), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.access_time_filled_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'System Clock Drift Detected (Auto-Corrected)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F6C5A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$shiftName SHIFT ACTIVE',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PC time is $localFmt (${info.formattedOffset}). App is automatically calibrated to true server time: $serverFmt.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _showDetailsDialog(context, info),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  foregroundColor: const Color(0xFF92400E),
                ),
                child: const Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Color(0xFFB45309)),
                onPressed: () => setState(() => _dismissed = true),
                tooltip: 'Dismiss',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
        );
      },
    );
  }
}
