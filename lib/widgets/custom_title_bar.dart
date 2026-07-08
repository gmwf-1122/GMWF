import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'sync_status_indicator.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('app_settings').listenable(),
      builder: (context, Box box, child) {
        final colorHex = box.get('custom_accent_color') as String?;
        Color barColor = const Color(0xFF00695C); // default teal
        if (colorHex != null && colorHex.isNotEmpty) {
          try {
            final hex = colorHex.replaceAll('#', '');
            barColor = Color(int.parse('FF$hex', radix: 16));
          } catch (_) {}
        }

        final mouseOverColor = Color.alphaBlend(Colors.white.withValues(alpha: 0.15), barColor);
        final mouseDownColor = Color.alphaBlend(Colors.black.withValues(alpha: 0.15), barColor);

        return WindowTitleBarBox(
          child: Container(
            color: barColor,
            child: Row(
              children: [
                Expanded(
                  child: MoveWindow(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/logo/gmwf.png',
                            height: 20,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.business, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "GMWF",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          const SyncStatusIndicator(),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                WindowButtons(
                  mouseOver: mouseOverColor,
                  mouseDown: mouseDownColor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class WindowButtons extends StatelessWidget {
  final Color mouseOver;
  final Color mouseDown;

  const WindowButtons({
    super.key,
    required this.mouseOver,
    required this.mouseDown,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColors = WindowButtonColors(
      iconNormal: Colors.white,
      mouseOver: mouseOver,
      mouseDown: mouseDown,
      iconMouseOver: Colors.white,
      iconMouseDown: Colors.white,
    );

    final closeButtonColors = WindowButtonColors(
      mouseOver: const Color(0xFFD32F2F),
      mouseDown: const Color(0xFFB71C1C),
      iconNormal: Colors.white,
      iconMouseOver: Colors.white,
    );

    return Row(
      children: [
        MinimizeWindowButton(colors: buttonColors),
        MaximizeWindowButton(colors: buttonColors),
        CloseWindowButton(colors: closeButtonColors),
      ],
    );
  }
}