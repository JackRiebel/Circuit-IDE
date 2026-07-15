import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../enums/tool_status.dart';
import '../../models/tool_call_info.dart';
import '../../state/theme_provider.dart';

class ToolCallWidget extends ConsumerStatefulWidget {
  final ToolCallInfo toolCall;

  const ToolCallWidget({super.key, required this.toolCall});

  @override
  ConsumerState<ToolCallWidget> createState() => _ToolCallWidgetState();
}

class _ToolCallWidgetState extends ConsumerState<ToolCallWidget> {
  bool _isExpanded = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final tc = widget.toolCall;

    final statusColor = switch (tc.status) {
      ToolStatus.pending => tokens.textMuted,
      ToolStatus.running => tokens.accent,
      ToolStatus.success => tokens.success,
      ToolStatus.error => tokens.error,
      ToolStatus.cancelled => tokens.textMuted,
    };

    final statusIcon = switch (tc.status) {
      ToolStatus.pending => Icons.schedule_outlined,
      ToolStatus.running => Icons.sync,
      ToolStatus.success => Icons.check_circle_outline,
      ToolStatus.error => Icons.error_outline,
      ToolStatus.cancelled => Icons.cancel_outlined,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          curve: AnimationCurves.snappy,
          margin: const EdgeInsets.only(top: Spacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? tokens.bgLighter : tokens.bgDark,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: _isExpanded
                  ? statusColor.withValues(alpha: 0.3)
                  : tokens.border.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (tc.status == ToolStatus.running)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: statusColor,
                      ),
                    )
                  else
                    Icon(statusIcon, size: 13, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    tc.name,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (tc.arguments.isNotEmpty)
                    Flexible(
                      child: Text(
                        _previewArgs(tc),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xxs,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: AnimationDurations.fast,
                    child: Icon(
                      Icons.expand_more,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),

              // Expanded details
              if (_isExpanded) ...[
                const SizedBox(height: Spacing.md),
                if (tc.arguments.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: tokens.codeBlockBg,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(
                        color: tokens.border.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SelectableText(
                      tc.argumentsJson,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xxs,
                        fontFamily: 'JetBrains Mono',
                        height: 1.5,
                      ),
                    ),
                  ),
                if (tc.result != null) ...[
                  const SizedBox(height: Spacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Spacing.md),
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: tokens.codeBlockBg,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(
                        color: tokens.border.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        tc.result!,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xxs,
                          fontFamily: 'JetBrains Mono',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _previewArgs(ToolCallInfo tc) {
    final args = tc.arguments;
    if (args.containsKey('path')) return args['path'] as String;
    if (args.containsKey('command')) return args['command'] as String;
    if (args.containsKey('pattern')) return args['pattern'] as String;
    if (args.containsKey('query')) return args['query'] as String;
    if (args.containsKey('message')) return args['message'] as String;
    return '';
  }
}
