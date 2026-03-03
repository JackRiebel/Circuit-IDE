import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/runtime_models.dart';
import '../../state/theme_provider.dart';

class VariableInspector extends ConsumerWidget {
  final List<RuntimeVariable> variables;

  const VariableInspector({super.key, required this.variables});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: tokens.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Text(
            'VARIABLES',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: variables.isEmpty
              ? Center(
                  child: Text(
                    'No variables at this frame',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(Spacing.sm),
                  itemCount: variables.length,
                  itemBuilder: (context, index) {
                    return _VariableRow(
                      variable: variables[index],
                      tokens: tokens,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _VariableRow extends StatelessWidget {
  final RuntimeVariable variable;
  final dynamic tokens;

  const _VariableRow({required this.variable, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: variable.isModified
            ? tokens.warning.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (variable.isModified)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm, top: 2),
              child: Icon(Icons.edit, size: 10, color: tokens.warning),
            ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variable.name,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  variable.type,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            flex: 3,
            child: Text(
              variable.value,
              style: TextStyle(
                color: variable.isModified
                    ? tokens.warning
                    : tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
