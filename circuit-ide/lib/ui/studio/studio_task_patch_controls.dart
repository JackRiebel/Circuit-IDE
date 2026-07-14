import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

class StudioPatchActionButton extends ConsumerWidget {
  final VoidCallback? onPressed;
  final String label;

  const StudioPatchActionButton({
    super.key,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 24),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
        foregroundColor: tokens.textSecondary,
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.56)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(
          fontSize: FontSizes.xs,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

ButtonStyle studioPatchPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  ).copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: tokens.outlineFocus, width: 1.5)
          : BorderSide.none,
    ),
  );
}

ButtonStyle studioPatchSecondaryActionStyle(ThemeTokens tokens) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  ).copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: tokens.outlineFocus, width: 1.5)
          : BorderSide(color: tokens.studioDivider.withValues(alpha: 0.58)),
    ),
  );
}

ButtonStyle studioPatchTextActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  ).copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: tokens.outlineFocus, width: 1.5)
          : BorderSide.none,
    ),
  );
}
