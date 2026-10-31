// lib/widgets/blurred_dialog_observer.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/ui_stall_monitor.dart';

/// Global Manager and NavigatorObserver that coordinates dialog backdrop blur.
///
/// Architectural Guarantee:
/// 1. ONLY the page/content BEHIND the dialog is blurred across ALL modules (Dispensary, School, Madrassa, Donations, Office, Employees, etc.).
/// 2. The dialog itself is NEVER blurred (100% crisp and sharp) because dialogs (DialogRoute / PopupRoute) are never wrapped by [BlurOnDialogPageTransitionsBuilder].
/// 3. Notifications, Flushbars, and SnackBars are NEVER blurred because they are independent overlay entries / scaffold messenger views, never wrapped by PageTransitions.
class DialogBlurManager extends NavigatorObserver {
  static final DialogBlurManager instance = DialogBlurManager._();
  factory DialogBlurManager() => instance;
  DialogBlurManager._();

  static final ValueNotifier<bool> isDialogOpen = ValueNotifier<bool>(false);
  static int _dialogCount = 0;

  static bool get isBlurEnabled {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        return Hive.box('app_settings').get('dialog_blur_enabled', defaultValue: false) as bool;
      }
    } catch (_) {}
    return true;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    UiStallMonitor.mark('push ${route.settings.name ?? route.runtimeType}');
    UiStallMonitor.topRoute = route;
    if (_isDialog(route)) {
      _dialogCount++;
      debugPrint('[Dialog] opened ${route.runtimeType} (count $_dialogCount)');
      _update();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    UiStallMonitor.mark('pop ${route.settings.name ?? route.runtimeType}');
    UiStallMonitor.topRoute = previousRoute;
    if (_isDialog(route)) {
      _dialogCount = (_dialogCount - 1).clamp(0, 9999);
      debugPrint('[Dialog] closed ${route.runtimeType} (count $_dialogCount)');
      _update();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isDialog(route)) {
      _dialogCount = (_dialogCount - 1).clamp(0, 9999);
      _update();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null && _isDialog(oldRoute)) {
      _dialogCount = (_dialogCount - 1).clamp(0, 9999);
    }
    if (newRoute != null && _isDialog(newRoute)) {
      _dialogCount++;
    }
    _update();
  }

  void _update() {
    isDialogOpen.value = isBlurEnabled && (_dialogCount > 0);
  }

  static bool _isDialog(Route<dynamic> route) {
    final typeName = route.runtimeType.toString();
    // Exclude notifications, snackbars, tooltips, popup menus, and dropdowns
    if (typeName.contains('Flushbar')) return false;
    if (typeName.contains('SnackBar')) return false;
    if (typeName.contains('Tooltip')) return false;
    if (typeName.contains('PopupMenuRoute')) return false;
    if (typeName.contains('DropdownRoute')) return false;

    // Matches all DialogRoute, RawDialogRoute, ModalBottomSheetRoute, or any custom Dialog/BottomSheet PopupRoute
    return route is RawDialogRoute ||
        typeName.contains('DialogRoute') ||
        typeName.contains('ModalBottomSheetRoute') ||
        (route is PopupRoute && (typeName.contains('Dialog') || typeName.contains('BottomSheet') || typeName.contains('Modal')));
  }
}

/// A PageTransitionsBuilder that wraps pages and blurs them ONLY when a dialog
/// is opened in front of them. The dialog itself is never a PageRoute, so the
/// dialog and any flushbars remain completely unblurred and sharp.
class BlurOnDialogPageTransitionsBuilder extends PageTransitionsBuilder {
  final PageTransitionsBuilder delegate;
  const BlurOnDialogPageTransitionsBuilder(this.delegate);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transitionWidget = delegate.buildTransitions(route, context, animation, secondaryAnimation, child);

    return ValueListenableBuilder<bool>(
      valueListenable: DialogBlurManager.isDialogOpen,
      builder: (context, isDialogOpen, _) {
        final shouldBlur = isDialogOpen && !route.isCurrent;
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0.0, end: shouldBlur ? 7.0 : 0.0),
          builder: (context, sigma, innerChild) {
            // Keep ImageFiltered in the tree at all times and only toggle `enabled`.
            // Swapping `innerChild` <-> `ImageFiltered(innerChild)` changes the parent
            // type, so Flutter disposes and recreates every State under the page
            // (forms reset, tabs reset, panels re-run initState) each time a dialog
            // opens or closes.
            return ImageFiltered(
              enabled: sigma > 0.05,
              imageFilter: ImageFilter.blur(sigmaX: sigma <= 0.05 ? 0.1 : sigma, sigmaY: sigma <= 0.05 ? 0.1 : sigma),
              child: innerChild,
            );
          },
          child: transitionWidget,
        );
      },
    );
  }
}

class _BlurredScope extends InheritedWidget {
  const _BlurredScope({required super.child});

  @override
  bool updateShouldNotify(_BlurredScope oldWidget) => false;
}

/// A widget that wraps any underlying page / dashboard content and automatically
/// applies a smooth blur whenever any dialog is open in the app.
///
/// Because this widget wraps only the screen content, any dialogs, flushbars,
/// snackbars, or popups pushed onto the Navigator sit ABOVE this widget and
/// remain 100% crisp, sharp, and readable.
class BlurredUnderDialogBackground extends StatelessWidget {
  final Widget child;
  const BlurredUnderDialogBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final hasAncestorBlur = context.dependOnInheritedWidgetOfExactType<_BlurredScope>() != null;
    if (hasAncestorBlur) return child;

    return _BlurredScope(
      child: ValueListenableBuilder<bool>(
        valueListenable: DialogBlurManager.isDialogOpen,
        builder: (context, isDialogOpen, staticChild) {
          return TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0.0, end: (isDialogOpen && DialogBlurManager.isBlurEnabled) ? 7.0 : 0.0),
            builder: (context, sigma, innerChild) {
              // See BlurOnDialogPageTransitionsBuilder: never swap the tree shape,
              // only toggle `enabled`, so page State survives dialogs opening/closing.
              return ImageFiltered(
                enabled: sigma > 0.05,
                imageFilter: ImageFilter.blur(sigmaX: sigma <= 0.05 ? 0.1 : sigma, sigmaY: sigma <= 0.05 ? 0.1 : sigma),
                child: innerChild,
              );
            },
            child: staticChild,
          );
        },
        child: child,
      ),
    );
  }
}
