import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'sync_status_indicator.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return WindowTitleBarBox(
      child: Container(
        color: const Color(0xFF00695C),
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
            const WindowButtons(),
          ],
        ),
      ),
    );
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonColors = WindowButtonColors(
      iconNormal: Colors.white,
      mouseOver: const Color(0xFF00796B),
      mouseDown: const Color(0xFF004D40),
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