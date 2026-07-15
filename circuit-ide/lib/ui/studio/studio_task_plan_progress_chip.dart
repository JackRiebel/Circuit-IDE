import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/studio_turn.dart';
import '../../state/theme_provider.dart';

class StudioPlanProgressTargetChip extends ConsumerWidget {
  final PlanTargetProgress target;

  const StudioPlanProgressTargetChip({super.key, required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final status = _planTargetStatusLabel(target.state);
    final statusColor = switch (target.state) {
      PlanTargetProgressState.conflict => tokens.warning,
      PlanTargetProgressState.blocked => tokens.error,
      PlanTargetProgressState.proposed => tokens.textSecondary,
      PlanTargetProgressState.pending => tokens.textMuted,
      PlanTargetProgressState.applied => tokens.success,
      PlanTargetProgressState.skipped => tokens.textMuted,
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 236),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: FontSizes.xs,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              target.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.1,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _planTargetStatusLabel(PlanTargetProgressState state) {
  return switch (state) {
    PlanTargetProgressState.pending => 'Pending',
    PlanTargetProgressState.proposed => 'Proposed',
    PlanTargetProgressState.applied => 'Applied',
    PlanTargetProgressState.conflict => 'Conflict',
    PlanTargetProgressState.blocked => 'Blocked',
    PlanTargetProgressState.skipped => 'Skipped',
  };
}
