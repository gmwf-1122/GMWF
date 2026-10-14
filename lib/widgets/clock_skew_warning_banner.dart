// lib/widgets/clock_skew_warning_banner.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:gmwf/design/components/app_toast.dart';
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
        backgroundColor: context.adapt(SoftPalette.gray50),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 24, 20),
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.adapt(SoftPalette.red100t),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.adapt(SoftPalette.red200)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: SoftPalette.red400,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: SoftPalette.gray50, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incorrect Clock / Shift Detected',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16.5,
                        color: context.adapt(SoftPalette.red600),
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Please verify your Windows date and time',
                      style: TextStyle(fontSize: 12, color: context.adapt(SoftPalette.red550), fontWeight: FontWeight.w500),
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
              Text(
                'Your computer\'s system clock does not match the real internet/server time. '
                'This causes tokens to be assigned to the wrong shift (e.g. morning instead of evening). '
                'The app has automatically calibrated internal timestamps, but you can also re-align existing tokens below.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: context.adapt(SoftPalette.slate700)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.adapt(SoftPalette.gray50),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.adapt(SoftPalette.slate150)),
                ),
                child: Column(
                  children: [
                    _infoRow('🖥️ Computer Local Clock:', localTimeStr, SoftPalette.red500, isBold: true),
                    const Divider(height: 18),
                    _infoRow('🌐 Authoritative Internet Time:', serverTimeStr, SoftPalette.emerald500, isBold: true),
                    const Divider(height: 18),
                    _infoRow('⏱️ Clock Drift Offset:', info.formattedOffset, SoftPalette.orange400),
                    const Divider(height: 18),
                    _infoRow('🎯 Active Clinical Shift:', '${info.authoritativeSession.toUpperCase()} SHIFT', context.adapt(SoftPalette.teal600), isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.adapt(SoftPalette.slate100),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.adapt(SoftPalette.slate200)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, color: context.adapt(SoftPalette.blue550), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Set your Windows Time to "Set time automatically" in Windows Settings so your PC clock stays accurate.',
                        style: TextStyle(fontSize: 11.5, color: context.adapt(SoftPalette.blue600), fontWeight: FontWeight.w500),
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
            child: Text('Dismiss', style: TextStyle(color: context.adapt(SoftPalette.slate550), fontWeight: FontWeight.w600)),
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
                  AppToast.showSnackBar(context, 
                    SnackBar(
                      content: Text('✅ Successfully aligned $count token(s) into current active shift!'),
                      backgroundColor: SoftPalette.emerald500,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: const Text('Realign Tokens to Active Shift'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SoftPalette.teal600,
                foregroundColor: SoftPalette.gray50,
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
                  AppToast.showSnackBar(context, 
                    SnackBar(
                      content: Text('🔄 Successfully restored $count token(s) back to original dates!'),
                      backgroundColor: SoftPalette.sky500,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.history_rounded, size: 16),
              label: const Text('Undo / Restore Original Dates'),
              style: TextButton.styleFrom(
                foregroundColor: SoftPalette.red500,
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
                  AppToast.showSnackBar(context, 
                    SnackBar(
                      content: Text('🌐 Internet Date & Time synced: ${DateFormat('hh:mm:ss a (dd MMM yyyy)').format(syncTime)}'),
                      backgroundColor: SoftPalette.teal600,
                    ),
                  );
                } else {
                  CampSessionService.checkClockSkew();
                }
              }
            },
            icon: const Icon(Icons.sync_rounded, size: 16),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.adapt(SoftPalette.teal600),
              side: BorderSide(color: context.adapt(SoftPalette.teal600)),
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
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.adapt(SoftPalette.slate600))),
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
            color: context.adapt(SoftPalette.yellow50m),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.adapt(SoftPalette.amber300), width: 1.2),
            boxShadow: const [
              BoxShadow(color: SoftPalette.orange400A8, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.adapt(SoftPalette.amber300).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.access_time_filled_rounded, color: context.adapt(SoftPalette.orange400), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'System Clock Drift Detected (Auto-Corrected)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.adapt(SoftPalette.orange600)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: SoftPalette.teal600,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$shiftName SHIFT ACTIVE',
                            style: const TextStyle(color: SoftPalette.gray50, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PC time is $localFmt (${info.formattedOffset}). App is automatically calibrated to true server time: $serverFmt.',
                      style: TextStyle(fontSize: 12, color: context.adapt(SoftPalette.orange350)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _showDetailsDialog(context, info),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  foregroundColor: context.adapt(SoftPalette.orange600),
                ),
                child: const Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: context.adapt(SoftPalette.orange500)),
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
