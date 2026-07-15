import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/background_agent_provider.dart';
import '../../state/theme_provider.dart';

/// Overlay widget that shows toast notifications for completed background agents.
/// Place this in the widget tree's Stack (e.g., in IDEScaffold).
class BackgroundAgentToastOverlay extends ConsumerStatefulWidget {
  const BackgroundAgentToastOverlay({super.key});

  @override
  ConsumerState<BackgroundAgentToastOverlay> createState() =>
      _BackgroundAgentToastOverlayState();
}

class _BackgroundAgentToastOverlayState
    extends ConsumerState<BackgroundAgentToastOverlay> {
  final _visibleToasts = <BackgroundAgentResult>[];
  final _timers = <String, Timer>{};

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(backgroundAgentProvider, (prev, next) {
      if (prev == null) return;
      // Check for new results
      if (next.recentResults.isNotEmpty &&
          (prev.recentResults.isEmpty ||
              next.recentResults.first != prev.recentResults.first)) {
        _showToast(next.recentResults.first);
      }
    });

    if (_visibleToasts.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 40,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _visibleToasts
            .map(
              (result) => _Toast(
                result: result,
                onDismiss: () => _dismissToast(result),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showToast(BackgroundAgentResult result) {
    setState(() {
      _visibleToasts.insert(0, result);
      if (_visibleToasts.length > 3) {
        _visibleToasts.removeLast();
      }
    });

    final key =
        '${result.agentName}:${result.timestamp.millisecondsSinceEpoch}';
    _timers[key] = Timer(const Duration(seconds: 8), () {
      _dismissToast(result);
      _timers.remove(key);
    });
  }

  void _dismissToast(BackgroundAgentResult result) {
    if (mounted) {
      setState(() {
        _visibleToasts.remove(result);
      });
    }
  }
}

class _Toast extends ConsumerStatefulWidget {
  final BackgroundAgentResult result;
  final VoidCallback onDismiss;

  const _Toast({required this.result, required this.onDismiss});

  @override
  ConsumerState<_Toast> createState() => _ToastState();
}

class _ToastState extends ConsumerState<_Toast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: Spacing.sm),
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: tokens.bgLighter,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: widget.result.success
                  ? tokens.success.withValues(alpha: 0.3)
                  : tokens.error.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.result.success
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 16,
                color: widget.result.success ? tokens.success : tokens.error,
              ),
              const SizedBox(width: Spacing.md),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.result.agentName,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.result.summary,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              GestureDetector(
                onTap: widget.onDismiss,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 14, color: tokens.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
