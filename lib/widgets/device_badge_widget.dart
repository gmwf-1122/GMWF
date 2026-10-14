// lib/widgets/device_badge_widget.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class DeviceBadgeWidget extends StatelessWidget {
  final Map<String, dynamic>? deviceInfo;
  final bool compact;
  final bool showLabel;

  const DeviceBadgeWidget({
    super.key,
    this.deviceInfo,
    this.compact = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    if (deviceInfo == null || deviceInfo!.isEmpty) {
      return const SizedBox.shrink();
    }

    final platform = (deviceInfo!['platform'] as String?) ?? '';
    final browser = (deviceInfo!['browser'] as String?) ?? '';
    final os = (deviceInfo!['os'] as String?) ?? '';
    final iconType = (deviceInfo!['iconType'] as String?) ?? '';
    final deviceName = (deviceInfo!['deviceName'] as String?) ?? '';
    final deviceModel = (deviceInfo!['deviceModel'] as String?) ?? '';
    final isOnline = deviceInfo!['isOnline'] as bool? ?? false;

    IconData icon = FontAwesomeIcons.desktop;
    Color iconColor = context.adapt(SoftPalette.blue500);
    Color bgColor = context.adapt(SoftPalette.slate100);
    Color borderColor = context.adapt(SoftPalette.sky300);
    String label = '$platform $browser';

    switch (iconType.toLowerCase()) {
      case 'chrome':
        icon = FontAwesomeIcons.chrome;
        iconColor = context.adapt(SoftPalette.blue400); // Google Blue
        bgColor = context.adapt(SoftPalette.slate100);
        borderColor = context.adapt(SoftPalette.blue200);
        label = 'Chrome ($os)';
        break;
      case 'edge':
        icon = FontAwesomeIcons.edge;
        iconColor = context.adapt(SoftPalette.blue500); // Edge Blue/Teal
        bgColor = context.adapt(SoftPalette.slate100);
        borderColor = context.adapt(SoftPalette.sky300);
        label = 'Edge ($os)';
        break;
      case 'firefox':
        icon = FontAwesomeIcons.firefoxBrowser;
        iconColor = context.adapt(SoftPalette.orange350); // Firefox Orange
        bgColor = context.adapt(SoftPalette.orange100m);
        borderColor = context.adapt(SoftPalette.orange200);
        label = 'Firefox ($os)';
        break;
      case 'safari':
        icon = FontAwesomeIcons.safari;
        iconColor = context.adapt(SoftPalette.blue550); // Safari Compass Blue
        bgColor = context.adapt(SoftPalette.slate100);
        borderColor = context.adapt(SoftPalette.blue300);
        label = 'Safari ($os)';
        break;
      case 'windows':
        icon = FontAwesomeIcons.windows;
        iconColor = context.adapt(SoftPalette.sky350); // Windows Blue
        bgColor = context.adapt(SoftPalette.slate100);
        borderColor = context.adapt(SoftPalette.sky200);
        label = (deviceName.isNotEmpty && deviceName != 'Windows PC')
            ? '$deviceName ($os)'
            : (os.isNotEmpty ? os : 'Windows PC');
        break;
      case 'android':
        icon = FontAwesomeIcons.android;
        iconColor = context.adapt(SoftPalette.green300); // Android Green
        bgColor = context.adapt(SoftPalette.emerald100m);
        borderColor = context.adapt(SoftPalette.emerald200);
        label = deviceModel.isNotEmpty ? deviceModel : 'Android';
        break;
      case 'ios':
        icon = FontAwesomeIcons.apple;
        iconColor = context.adapt(SoftPalette.gray750); // Apple Dark
        bgColor = context.adapt(SoftPalette.gray100);
        borderColor = context.adapt(SoftPalette.gray200);
        label = os.isNotEmpty ? os : 'iOS Device';
        break;

      case 'macos':
        icon = FontAwesomeIcons.apple;
        iconColor = context.adapt(SoftPalette.gray750);
        bgColor = context.adapt(SoftPalette.gray100);
        borderColor = context.adapt(SoftPalette.gray200);
        label = 'macOS';
        break;

      case 'linux':
        icon = FontAwesomeIcons.linux;
        iconColor = context.adapt(SoftPalette.yellow200);
        bgColor = context.adapt(SoftPalette.yellow50m);
        borderColor = context.adapt(SoftPalette.yellow150);
        label = 'Linux';
        break;

      default:
        if (platform.toLowerCase() == 'web') {
          icon = FontAwesomeIcons.globe;
          iconColor = context.adapt(SoftPalette.teal500);
          bgColor = context.adapt(SoftPalette.teal100m);
          borderColor = context.adapt(SoftPalette.teal300);
          label = 'Web Browser';
        } else {
          icon = FontAwesomeIcons.mobileScreenButton;
          iconColor = context.adapt(SoftPalette.indigo600);
          bgColor = context.adapt(SoftPalette.slate150);
          borderColor = context.adapt(SoftPalette.indigo350);
          label = platform;
        }
    }

    final appVersion = (deviceInfo!['appVersion'] as String?) ?? '';

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 12, color: iconColor),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            ],
            if (appVersion.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                'v$appVersion',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: iconColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
          if (appVersion.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'v$appVersion',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ),
          ],
          if (isOnline) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: SoftPalette.green400,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
