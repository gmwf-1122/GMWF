// lib/widgets/connection_status_widget.dart
// Drop-in widget showing live LAN connection state with the modern pill aesthetic.

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../realtime/connection_manager.dart';
import '../realtime/realtime_manager.dart';
import 'lan_server_config_dialog.dart';

class ConnectionStatusBadge extends StatelessWidget {
  final ConnectionStatus status;
  final VoidCallback? onRetry;

  const ConnectionStatusBadge({
    super.key,
    required this.status,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final rm = RealtimeManager();
    final isConnected = rm.isLinkAlive;
    final isSearching = !isConnected && (status.isSearching || status.isConnecting);

    return ValueListenableBuilder<Box>(
      valueListenable:
          Hive.box('app_settings').listenable(keys: ['is_dark_mode']),
      builder: (context, box, _) {
        final isDark = box.get('is_dark_mode', defaultValue: false) == true;

        Color badgeBg = SoftPalette.emerald100;
        Color dotColor = SoftPalette.emerald350;
        String statusLabel = 'Connected';

        if (isConnected) {
          badgeBg = isDark ? SoftPalette.emerald700 : SoftPalette.emerald100;
          dotColor = SoftPalette.emerald350;
          statusLabel = 'Connected';
        } else if (isSearching) {
          badgeBg = isDark ? SoftPalette.orange700 : SoftPalette.amber100;
          dotColor = SoftPalette.orange350;
          statusLabel = status.isConnecting ? 'Connecting…' : 'Searching…';
        } else {
          badgeBg = isDark ? SoftPalette.red700 : SoftPalette.red150m;
          dotColor = SoftPalette.red400;
          statusLabel = 'Disconnected';
        }

        return InkWell(
          onTap: () {
            // When disconnected and retry callback exists, retry immediately
            // instead of opening the config dialog.
            if (!isConnected && onRetry != null) {
              onRetry!();
              return;
            }
            LanServerConfigDialog.show(context);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? SoftPalette.slate900 : SoftPalette.gray50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? SoftPalette.slate700
                    : SoftPalette.slate150,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: SoftPalette.gray900.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: badgeBg,
                  ),
                  child: Center(
                    child: isSearching
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: dotColor,
                            ),
                          )
                        : Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColor,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: dotColor,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      (status.ip ?? rm.serverIp) != null
                          ? '${status.ip ?? rm.serverIp}:${status.port ?? rm.port}'
                          : 'LAN Local',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? SoftPalette.slate350
                            : SoftPalette.slate550,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                if (isConnected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: SoftPalette.emerald350,
                    size: 18,
                  )
                else if (onRetry != null)
                  Icon(
                    Icons.refresh_rounded,
                    color: dotColor,
                    size: 18,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
