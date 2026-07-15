import 'package:flutter/widgets.dart';

/// Owns the persistent focus target used when a Studio surface removes the
/// control that currently owns keyboard focus.
///
/// The work drawer is deliberately mounted and unmounted as users collapse it.
/// Returning focus to the stable Progress control keeps keyboard users in a
/// known location instead of leaving focus on a removed widget.
class StudioFocusRestoration extends InheritedWidget {
  final FocusNode progressToggleFocusNode;

  const StudioFocusRestoration({
    super.key,
    required this.progressToggleFocusNode,
    required super.child,
  });

  static StudioFocusRestoration? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<StudioFocusRestoration>();
  }

  void restoreToProgressToggle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (progressToggleFocusNode.context == null ||
          !progressToggleFocusNode.canRequestFocus) {
        return;
      }
      progressToggleFocusNode.requestFocus();
    });
  }

  @override
  bool updateShouldNotify(StudioFocusRestoration oldWidget) {
    return oldWidget.progressToggleFocusNode != progressToggleFocusNode;
  }
}
