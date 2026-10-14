import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/navigator_key.dart';
import '../main.dart';
import '../pages/login_page.dart';
import '../services/auth_service.dart';
import '../services/role_simulator_service.dart';

/// Global Self-Healing error widget and handler.
/// Replaces Flutter's default blank grey/white screen with an intelligent self-repair UI
/// offering clean recovery to Login or graceful exit.
class SelfHealingErrorView extends StatefulWidget {
  final FlutterErrorDetails? details;

  const SelfHealingErrorView({super.key, this.details});

  @override
  State<SelfHealingErrorView> createState() => _SelfHealingErrorViewState();
}

class _SelfHealingErrorViewState extends State<SelfHealingErrorView> {
  bool _isNavigating = false;

  void _returnToLogin() {
    if (_isNavigating) return;
    _isNavigating = true;
    debugPrint('[SelfHealingErrorView] 🔄 Returning safely to Login Screen');

    try {
      RoleSimulatorService.reset();
    } catch (_) {}

    try {
      AuthHomeWrapper.clearSession();
    } catch (_) {}

    try {
      AuthService().signOut().catchError((e) {
        debugPrint('[SelfHealingErrorView] signOut notice: $e');
      });
    } catch (_) {}

    void performNav() {
      try {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushNamedAndRemoveUntil('/login', (r) => false);
          return;
        }
      } catch (e) {
        debugPrint('[SelfHealingErrorView] navigatorKey push failed: $e');
      }

      try {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (r) => false);
          return;
        }
      } catch (e) {
        debugPrint('[SelfHealingErrorView] rootNavigator push failed: $e');
      }

      try {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (r) => false,
          );
        }
      } catch (e) {
        debugPrint('[SelfHealingErrorView] MaterialPageRoute push failed: $e');
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => performNav());
  }

  void _closeApp() {
    debugPrint('[SelfHealingErrorView] ⏹️ Closing application');
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        try {
          appWindow.close();
          return;
        } catch (_) {}
        exit(0);
      } else {
        SystemNavigator.pop();
      }
    } catch (_) {
      try {
        exit(0);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compact fallback for tiny widget exceptions (e.g. list tile or small card)
        if (constraints.maxHeight < 160 || constraints.maxWidth < 280) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SoftPalette.red400.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SoftPalette.red400.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, size: 16, color: SoftPalette.red400),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Render notice — recovering...',
                      style: TextStyle(fontSize: 11, color: SoftPalette.red400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _returnToLogin,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Login', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        }

        // Full Screen / Major Component Self-Healing View
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Directionality(
          textDirection: TextDirection.ltr,
          child: Material(
            color: isDark ? SoftPalette.slate900 : SoftPalette.slate100,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: isDark ? SoftPalette.slate800 : SoftPalette.gray50,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: SoftPalette.gray900.withValues(alpha: isDark ? 0.35 : 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(
                        color: isDark ? SoftPalette.slate700 : SoftPalette.slate150,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Healing Pulsing Badge
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: SoftPalette.amber200.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            size: 36,
                            color: SoftPalette.amber300,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        Text(
                          'Safe Mode Activated',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? SoftPalette.gray50 : SoftPalette.slate900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),

                        // Description
                        Text(
                          'Repeated rendering errors detected in this view. Safe mode prevented an endless reload loop.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: isDark ? SoftPalette.gray50A70 : SoftPalette.slate600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),

                        // Action buttons: Return to Login Screen and Close App only
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _returnToLogin,
                                icon: const Icon(Icons.login_rounded, size: 18),
                                label: const Text('Return to Login Screen'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: SoftPalette.gray50,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _closeApp,
                                icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                                label: const Text('Close App'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  foregroundColor: isDark ? SoftPalette.red350 : SoftPalette.red500,
                                  side: BorderSide(
                                    color: isDark
                                        ? SoftPalette.red400.withValues(alpha: 0.4)
                                        : SoftPalette.red400.withValues(alpha: 0.5),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
