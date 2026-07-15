import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'studio_task_plan_primitives.dart';

class StudioPlanDraftCard extends ConsumerStatefulWidget {
  final String markdown;

  const StudioPlanDraftCard({super.key, required this.markdown});

  @override
  ConsumerState<StudioPlanDraftCard> createState() => _PlanDraftCardState();
}

class _PlanDraftCardState extends ConsumerState<StudioPlanDraftCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final content = widget.markdown.trim().isEmpty
        ? '_Drafting plan..._'
        : widget.markdown.trim();
    final title = _draftPlanTitle(content);
    final body = _stripLeadingMarkdownHeading(content).trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('studio-plan-draft-card'),
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.reviewWidth,
        ),
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Plan',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: tokens.textMuted.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Drafting...',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      StudioPlanIconAction(
                        icon: _expanded
                            ? StudioIcons.keyboardArrowUp
                            : StudioIcons.keyboardArrowDown,
                        tooltip: _expanded
                            ? 'Collapse draft plan'
                            : 'Expand draft plan',
                        onPressed: () => setState(() => _expanded = !_expanded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xxl,
                  height: 1.12,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: StudioPlanCardBody(
                markdown: body.isEmpty ? content : body,
                expanded: _expanded,
                collapsedMaxHeight: 160,
              ),
            ),
            if (!_expanded)
              Transform.translate(
                offset: const Offset(0, -2),
                child: Center(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor: tokens.textPrimary,
                      foregroundColor: tokens.bgDark,
                      textStyle: const TextStyle(
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => setState(() => _expanded = true),
                    child: const Text('Expand plan'),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    style: _planTextActionStyle(tokens),
                    onPressed: () => setState(() => _expanded = false),
                    child: const Text('Collapse plan'),
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                color: tokens.surfacePanel.withValues(alpha: 0.28),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.42),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: _DraftPlanActionFooter(tokens: tokens),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftPlanActionFooter extends StatelessWidget {
  final ThemeTokens tokens;

  const _DraftPlanActionFooter({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.textMuted.withValues(alpha: 0.76),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Implement this plan?',
                style: TextStyle(
                  color: tokens.textPrimary.withValues(alpha: 0.82),
                  fontSize: FontSizes.sm,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'Not ready yet',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        StudioPlanChoiceButton(
          index: '1',
          label: 'Yes, implement this plan',
          enabled: false,
          onPressed: () {},
        ),
        const SizedBox(height: 6),
        StudioPlanChoiceButton(
          index: null,
          icon: StudioIcons.editOutlined,
          label: 'No, and tell Circuit what to do differently',
          enabled: false,
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              style: _planTextActionStyle(tokens),
              onPressed: null,
              child: const Text('Dismiss'),
            ),
            const SizedBox(width: Spacing.sm),
            FilledButton(
              style: _planPrimaryActionStyle(tokens),
              onPressed: null,
              child: const Text('Submit'),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Actions unlock when Circuit finishes writing the plan.',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: tokens.textMuted.withValues(alpha: 0.82),
            fontSize: FontSizes.xs,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

String _draftPlanTitle(String markdown) {
  final match = RegExp(
    r'^\s*#{1,2}\s+(.+?)\s*$',
    multiLine: true,
  ).firstMatch(markdown);
  final title = match?.group(1)?.trim();
  return title == null || title.isEmpty ? 'Draft plan' : title;
}

String _stripLeadingMarkdownHeading(String markdown) {
  return markdown.replaceFirst(RegExp(r'^\s*#{1,2}\s+.+?(?:\r?\n)+'), '');
}

ButtonStyle _planTextActionStyle(ThemeTokens tokens) {
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
  );
}

ButtonStyle _planPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    visualDensity: VisualDensity.compact,
    backgroundColor: tokens.textPrimary,
    foregroundColor: tokens.bgDark,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}
