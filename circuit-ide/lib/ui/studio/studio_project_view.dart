import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../state/file_tree_provider.dart';
import '../../state/project_profile_provider.dart';
import '../../state/theme_provider.dart';

class StudioProjectView extends ConsumerWidget {
  const StudioProjectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final profile = ref.watch(projectProfileProvider);
    final projectName = rootPath == null ? 'Circuit-IDE' : p.basename(rootPath);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.xxxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                projectName,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Cisco Circuit project studio',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.sm,
                ),
              ),
              const SizedBox(height: Spacing.xxxl),
              _ProjectSummaryCard(),
              const SizedBox(height: Spacing.xl),
              const _CoreRuntimeNotice(),
              if (profile.error != null) ...[
                const SizedBox(height: Spacing.lg),
                Text(
                  profile.error!,
                  style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectSummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final profile = ref.watch(projectProfileProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.studioPanel,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Row(
        children: [
          _SummaryStat(label: 'Stack', value: profile.primaryType.label),
          _SummaryStat(
            label: 'Entrypoints',
            value: profile.entrypoints.length.toString(),
          ),
          _SummaryStat(label: 'Changes', value: '${profile.changedFiles}'),
          _SummaryStat(
            label: 'Ready',
            value: profile.readiness.name,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends ConsumerWidget {
  final String label;
  final String value;
  final bool last;

  const _SummaryStat({
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(right: last ? 0 : Spacing.xl),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(right: BorderSide(color: tokens.studioDivider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoreRuntimeNotice extends ConsumerWidget {
  const _CoreRuntimeNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.studioCard,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Text(
        'Use the Studio composer to start work. Studio now routes prompts through the turn runtime so intent, context, approvals, plans, patches, and verification stay scoped to one reliable request.',
        style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
      ),
    );
  }
}
