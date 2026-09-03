// lib/utils/keyboard_focus_utils.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps any form or widget tree to enable seamless Tab and Enter key traversal between focusable inputs.
class FormKeyboardNavigation extends StatelessWidget {
  final Widget child;
  final VoidCallback? onFormSubmit;

  const FormKeyboardNavigation({
    super.key,
    required this.child,
    this.onFormSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter): () {
            final currentFocus = FocusManager.instance.primaryFocus;
            if (currentFocus != null && currentFocus.context != null) {
              // If current focus is a multiline textfield or button, don't hijack enter
              final widget = currentFocus.context!.widget;
              if (widget is EditableText && (widget.maxLines == null || widget.maxLines! > 1)) {
                return;
              }
              final moved = currentFocus.nextFocus();
              if (!moved && onFormSubmit != null) {
                onFormSubmit!();
              }
            }
          },
        },
        child: child,
      ),
    );
  }
}

/// Helper extension on BuildContext to quickly advance focus on field submission
extension KeyboardFocusContextX on BuildContext {
  void nextFieldFocus([VoidCallback? onFinal]) {
    final moved = FocusScope.of(this).nextFocus();
    if (!moved && onFinal != null) {
      onFinal();
    }
  }
}
