import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/security_scan_models.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/security_scan_provider.dart';
import '../../state/theme_provider.dart';
import 'finding_detail_dialog.dart';

class SecurityScanPanel extends ConsumerWidget {
  const SecurityScanPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final scanState = ref.watch(securityScanProvider);
    final hasProject = ref.watch(fileTreeProvider).rootPath != null;

    if (!hasProject) {
      return Center(
        child: Text(
          'Open a project to scan for vulnerabilities',
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
        ),
      );
    }

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Security Scan',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _ScanButton(isScanning: scanState.isScanning),
                ],
              ),

              // Result summary
              if (scanState.lastResult != null) ...[
                const SizedBox(height: Spacing.md),
                _ResultSummary(result: scanState.lastResult!),
              ],
            ],
          ),
        ),

        // Severity filters
        if (scanState.lastResult != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Row(
              children: [
                _SeverityFilter(
                  label: 'Critical',
                  count: scanState.lastResult!.criticalCount,
                  color: tokens.error,
                  isActive: scanState.activeSeverityFilters.contains('critical'),
                  onTap: () => ref
                      .read(securityScanProvider.notifier)
                      .toggleSeverityFilter('critical'),
                ),
                const SizedBox(width: Spacing.sm),
                _SeverityFilter(
                  label: 'High',
                  count: scanState.lastResult!.highCount,
                  color: const Color(0xFFFF6B35),
                  isActive: scanState.activeSeverityFilters.contains('high'),
                  onTap: () => ref
                      .read(securityScanProvider.notifier)
                      .toggleSeverityFilter('high'),
                ),
                const SizedBox(width: Spacing.sm),
                _SeverityFilter(
                  label: 'Medium',
                  count: scanState.lastResult!.mediumCount,
                  color: tokens.warning,
                  isActive: scanState.activeSeverityFilters.contains('medium'),
                  onTap: () => ref
                      .read(securityScanProvider.notifier)
                      .toggleSeverityFilter('medium'),
                ),
                const SizedBox(width: Spacing.sm),
                _SeverityFilter(
                  label: 'Low',
                  count: scanState.lastResult!.lowCount,
                  color: tokens.textMuted,
                  isActive: scanState.activeSeverityFilters.contains('low'),
                  onTap: () => ref
                      .read(securityScanProvider.notifier)
                      .toggleSeverityFilter('low'),
                ),
              ],
            ),
          ),

        const SizedBox(height: Spacing.md),

        // Findings list
        Expanded(
          child: scanState.isScanning
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.accent,
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),
                      Text(
                        'Scanning project...',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.sm,
                        ),
                      ),
                    ],
                  ),
                )
              : scanState.lastResult == null
                  ? _EmptyState(tokens: tokens)
                  : scanState.filteredFindings.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 32, color: tokens.success),
                              const SizedBox(height: Spacing.lg),
                              Text(
                                'No findings match current filters',
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: FontSizes.sm,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md,
                            vertical: Spacing.sm,
                          ),
                          itemCount: scanState.filteredFindings.length,
                          itemBuilder: (context, index) {
                            return _FindingItem(
                              finding: scanState.filteredFindings[index],
                              rootPath:
                                  ref.read(fileTreeProvider).rootPath ?? '',
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

class _ScanButton extends ConsumerStatefulWidget {
  final bool isScanning;
  const _ScanButton({required this.isScanning});

  @override
  ConsumerState<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends ConsumerState<_ScanButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: 'Scan Project',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: widget.isScanning
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.isScanning
              ? null
              : () => ref.read(securityScanProvider.notifier).scanProject(),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: _isHovered && !widget.isScanning
                  ? tokens.accent.withValues(alpha: 0.15)
                  : tokens.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: tokens.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isScanning)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.accent,
                    ),
                  )
                else
                  Icon(Icons.security, size: 14, color: tokens.accent),
                const SizedBox(width: Spacing.sm),
                Text(
                  widget.isScanning ? 'Scanning...' : 'Scan',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultSummary extends ConsumerWidget {
  final ScanResult result;
  const _ResultSummary({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final duration = result.scanDuration.inMilliseconds;

    return Row(
      children: [
        Text(
          '${result.findings.length} findings in ${result.filesScanned} files',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xxs,
          ),
        ),
        const Spacer(),
        Text(
          '${duration}ms',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xxs,
          ),
        ),
      ],
    );
  }
}

class _SeverityFilter extends ConsumerStatefulWidget {
  final String label;
  final int count;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _SeverityFilter({
    required this.label,
    required this.count,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  ConsumerState<_SeverityFilter> createState() => _SeverityFilterState();
}

class _SeverityFilterState extends ConsumerState<_SeverityFilter> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? widget.color.withValues(alpha: _isHovered ? 0.15 : 0.1)
                  : _isHovered
                      ? widget.color.withValues(alpha: 0.05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(
                color: widget.isActive
                    ? widget.color.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    color: widget.isActive
                        ? widget.color
                        : widget.color.withValues(alpha: 0.5),
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isActive
                        ? widget.color.withValues(alpha: 0.8)
                        : widget.color.withValues(alpha: 0.4),
                    fontSize: FontSizes.xxs - 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FindingItem extends ConsumerStatefulWidget {
  final SecurityFinding finding;
  final String rootPath;

  const _FindingItem({required this.finding, required this.rootPath});

  @override
  ConsumerState<_FindingItem> createState() => _FindingItemState();
}

class _FindingItemState extends ConsumerState<_FindingItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final color = _severityColor(widget.finding.severity, tokens);
    final relativePath = widget.finding.filePath.startsWith(widget.rootPath)
        ? widget.finding.filePath.substring(widget.rootPath.length + 1)
        : widget.finding.filePath;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          // Navigate to file
          ref.read(editorProvider.notifier).openFile(widget.finding.filePath);
        },
        onDoubleTap: () {
          // Show detail dialog
          ref.read(securityScanProvider.notifier).clearAnalysis();
          showDialog(
            context: context,
            builder: (_) => FindingDetailDialog(finding: widget.finding),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: Spacing.xs),
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            color: _isHovered
                ? color.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border.all(
              color: _isHovered
                  ? color.withValues(alpha: 0.2)
                  : tokens.border.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // Severity indicator
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.finding.severity.toUpperCase(),
                            style: TextStyle(
                              color: color,
                              fontSize: FontSizes.xxs - 2,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            widget.finding.type.displayName,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.xs,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$relativePath:${widget.finding.line}',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                        fontFamily: 'JetBrains Mono',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_isHovered)
                GestureDetector(
                  onTap: () {
                    ref.read(securityScanProvider.notifier).clearAnalysis();
                    showDialog(
                      context: context,
                      builder: (_) =>
                          FindingDetailDialog(finding: widget.finding),
                    );
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      Icons.auto_fix_high,
                      size: 14,
                      color: tokens.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _severityColor(String severity, dynamic tokens) => switch (severity) {
        'critical' => tokens.error as Color,
        'high' => const Color(0xFFFF6B35),
        'medium' => tokens.warning as Color,
        _ => tokens.textMuted as Color,
      };
}

class _EmptyState extends StatelessWidget {
  final dynamic tokens;
  const _EmptyState({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xl),
              color: (tokens.textMuted as Color).withValues(alpha: 0.06),
            ),
            child: Icon(
              Icons.shield_outlined,
              size: 22,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            'No scan results',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.md,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Click "Scan" to check your project\nfor security vulnerabilities.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
            ),
          ),
        ],
      ),
    );
  }
}
