import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/security_scan_models.dart';
import '../../state/security_scan_provider.dart';
import '../../state/theme_provider.dart';

class FindingDetailDialog extends ConsumerWidget {
  final SecurityFinding finding;

  const FindingDetailDialog({super.key, required this.finding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final scanState = ref.watch(securityScanProvider);

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  _SeverityBadge(severity: finding.severity),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      finding.type.displayName,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.lg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: tokens.textMuted, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xl),

              // Details
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DetailRow(
                        tokens: tokens,
                        label: 'File',
                        value: '${finding.filePath}:${finding.line}',
                      ),
                      const SizedBox(height: Spacing.lg),
                      _DetailRow(
                        tokens: tokens,
                        label: 'Description',
                        value: finding.description,
                      ),
                      const SizedBox(height: Spacing.lg),

                      // Code preview
                      Text(
                        'Code',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: Spacing.sm),
                      Container(
                        padding: const EdgeInsets.all(Spacing.lg),
                        decoration: BoxDecoration(
                          color: tokens.bgDark,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          finding.preview,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.xs,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),

                      _DetailRow(
                        tokens: tokens,
                        label: 'Recommendation',
                        value: finding.recommendation,
                      ),
                      const SizedBox(height: Spacing.xl),

                      // AI Analysis
                      if (scanState.isAnalyzing)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.xl),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: tokens.accent,
                                  ),
                                ),
                                const SizedBox(height: Spacing.md),
                                Text(
                                  'Analyzing with AI...',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: FontSizes.xs,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (scanState.aiAnalysis != null) ...[
                        Text(
                          'AI Analysis',
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: FontSizes.xs,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Container(
                          padding: const EdgeInsets.all(Spacing.lg),
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(Radii.md),
                            border: Border.all(
                              color: tokens.accent.withValues(alpha: 0.2),
                            ),
                          ),
                          child: SelectableText(
                            scanState.aiAnalysis!,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: FontSizes.xs,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xl),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!scanState.isAnalyzing && scanState.aiAnalysis == null)
                    TextButton.icon(
                      onPressed: () {
                        ref
                            .read(securityScanProvider.notifier)
                            .aiAnalyzeFinding(finding);
                      },
                      icon: Icon(Icons.auto_fix_high,
                          size: 16, color: tokens.accent),
                      label: Text(
                        'AI Fix',
                        style: TextStyle(color: tokens.accent),
                      ),
                    ),
                  const SizedBox(width: Spacing.md),
                  TextButton(
                    onPressed: () {
                      ref.read(securityScanProvider.notifier).clearAnalysis();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textMuted,
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeverityBadge extends ConsumerWidget {
  final String severity;
  const _SeverityBadge({required this.severity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = _severityColor(tokens, severity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: FontSizes.xxs,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

Color _severityColor(dynamic tokens, String severity) => switch (severity) {
      'critical' => tokens.error as Color,
      'high' => const Color(0xFFFF6B35),
      'medium' => tokens.warning as Color,
      'low' => tokens.textMuted as Color,
      _ => tokens.textMuted as Color,
    };

class _DetailRow extends StatelessWidget {
  final dynamic tokens;
  final String label;
  final String value;

  const _DetailRow({
    required this.tokens,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        SelectableText(
          value,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: FontSizes.sm,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
