import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'sync_status_indicator.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('app_settings')) {
      return WindowTitleBarBox(
        child: Container(
          color: SoftPalette.teal600,
          child: Row(
            children: [
              Expanded(
                child: MoveWindow(
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "GMWF",
                        style: TextStyle(color: SoftPalette.gray50, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              const WindowButtons(
                mouseOver: SoftPalette.teal600,
                mouseDown: SoftPalette.teal700,
              ),
            ],
          ),
        ),
      );
    }
    return ValueListenableBuilder(
      valueListenable: Hive.box('app_settings').listenable(keys: ['custom_accent_color']),
      builder: (context, Box box, child) {
        final colorHex = box.get('custom_accent_color') as String?;
        Color barColor = SoftPalette.teal600; // default teal
        if (colorHex != null && colorHex.isNotEmpty) {
          try {
            final hex = colorHex.replaceAll('#', '');
            barColor = Color(int.parse('FF$hex', radix: 16));
          } catch (_) {}
        }

        final mouseOverColor = Color.alphaBlend(SoftPalette.gray50.withValues(alpha: 0.15), barColor);
        final mouseDownColor = Color.alphaBlend(SoftPalette.gray900.withValues(alpha: 0.15), barColor);

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
                            'assets/logo/gmwf-1.webp',
                            height: 20,
                            cacheHeight: 60,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.business, color: SoftPalette.gray50, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "GMWF",
                            style: TextStyle(
                              color: SoftPalette.gray50,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SyncStatusIndicator(isDark: true),
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
      iconNormal: SoftPalette.gray50,
      mouseOver: mouseOver,
      mouseDown: mouseDown,
      iconMouseOver: SoftPalette.gray50,
      iconMouseDown: SoftPalette.gray50,
    );

    final closeButtonColors = WindowButtonColors(
      mouseOver: SoftPalette.red500,
      mouseDown: SoftPalette.red550,
      iconNormal: SoftPalette.gray50,
      iconMouseOver: SoftPalette.gray50,
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