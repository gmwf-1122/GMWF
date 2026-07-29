// lib/widgets/device_badge_widget.dart

import 'package:flutter/material.dart';
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
    Color iconColor = Colors.blue.shade700;
    Color bgColor = Colors.blue.shade50;
    Color borderColor = Colors.blue.shade200;
    String label = '$platform $browser';

    switch (iconType.toLowerCase()) {
      case 'chrome':
        icon = FontAwesomeIcons.chrome;
        iconColor = const Color(0xFF4285F4); // Google Blue
        bgColor = const Color(0xFFE8F0FE);
        borderColor = const Color(0xFFAECBFA);
        label = 'Chrome ($os)';
        break;
      case 'edge':
        icon = FontAwesomeIcons.edge;
        iconColor = const Color(0xFF0078D7); // Edge Blue/Teal
        bgColor = const Color(0xFFE6F2FB);
        borderColor = const Color(0xFF99C9EE);
        label = 'Edge ($os)';
        break;
      case 'firefox':
        icon = FontAwesomeIcons.firefoxBrowser;
        iconColor = const Color(0xFFFF7139); // Firefox Orange
        bgColor = const Color(0xFFFFF0EB);
        borderColor = const Color(0xFFFFC5B2);
        label = 'Firefox ($os)';
        break;
      case 'safari':
        icon = FontAwesomeIcons.safari;
        iconColor = const Color(0xFF0066CC); // Safari Compass Blue
        bgColor = const Color(0xFFE5F0FA);
        borderColor = const Color(0xFF99C2EC);
        label = 'Safari ($os)';
        break;
      case 'windows':
        icon = FontAwesomeIcons.windows;
        iconColor = const Color(0xFF00ADEF); // Windows Blue
        bgColor = const Color(0xFFE5F7FD);
        borderColor = const Color(0xFF99DFFB);
        label = (deviceName.isNotEmpty && deviceName != 'Windows PC')
            ? '$deviceName ($os)'
            : (os.isNotEmpty ? os : 'Windows PC');
        break;
      case 'android':
        icon = FontAwesomeIcons.android;
        iconColor = const Color(0xFF3DDC84); // Android Green
        bgColor = const Color(0xFFEAFBF2);
        borderColor = const Color(0xFFA1F0C7);
        label = deviceModel.isNotEmpty ? deviceModel : 'Android';
        break;
      case 'ios':
        icon = FontAwesomeIcons.apple;
        iconColor = const Color(0xFF333333); // Apple Dark
        bgColor = const Color(0xFFF2F2F2);
        borderColor = const Color(0xFFCCCCCC);
        label = os.isNotEmpty ? os : 'iOS Device';
        break;

      case 'macos':
        icon = FontAwesomeIcons.apple;
        iconColor = const Color(0xFF333333);
        bgColor = const Color(0xFFF2F2F2);
        borderColor = const Color(0xFFCCCCCC);
        label = 'macOS';
        break;

      case 'linux':
        icon = FontAwesomeIcons.linux;
        iconColor = const Color(0xFFFCC624);
        bgColor = const Color(0xFFFFFBEA);
        borderColor = const Color(0xFFFFE999);
        label = 'Linux';
        break;

      default:
        if (platform.toLowerCase() == 'web') {
          icon = FontAwesomeIcons.globe;
          iconColor = Colors.teal;
          bgColor = Colors.teal.shade50;
          borderColor = Colors.teal.shade200;
          label = 'Web Browser';
        } else {
          icon = FontAwesomeIcons.mobileScreenButton;
          iconColor = Colors.indigo;
          bgColor = Colors.indigo.shade50;
          borderColor = Colors.indigo.shade200;
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
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
