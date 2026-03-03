import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/ghost_mode_models.dart';
import '../../state/ghost_mode_provider.dart';
import '../../state/theme_provider.dart';

class GhostCompletionToastOverlay extends ConsumerStatefulWidget {
  const GhostCompletionToastOverlay({super.key});

  @override
  ConsumerState<GhostCompletionToastOverlay> createState() =>
      _GhostCompletionToastOverlayState();
}

class _GhostCompletionToastOverlayState
    extends ConsumerState<GhostCompletionToastOverlay> {
  final _visibleTasks = <GhostTask>[];
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
    ref.listen(ghostModeProvider, (prev, next) {
      if (prev == null) return;
      // Check for newly completed or failed tasks
      for (final task in next.tasks) {
        final prevTask = prev.tasks.cast<GhostTask?>().firstWhere(
              (t) => t!.id == task.id,
              orElse: () => null,
            );
        if (prevTask != null &&
            prevTask.status == GhostStatus.running &&
            (task.status == GhostStatus.completed ||
                task.status == GhostStatus.failed)) {
          _showToast(task);
        }
      }
    });

    if (_visibleTasks.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 40,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _visibleTasks
            .map((task) => _GhostToast(
                  task: task,
                  onDismiss: () => _dismissToast(task),
                  onViewChanges: () {
                    ref.read(ghostModeProvider.notifier).viewChanges(task.id);
                    _dismissToast(task);
                  },
                  onUndo: () {
                    ref.read(ghostModeProvider.notifier).undoGhost(task.id);
                    _dismissToast(task);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _showToast(GhostTask task) {
    setState(() {
      _visibleTasks.insert(0, task);
      if (_visibleTasks.length > 3) _visibleTasks.removeLast();
    });

    _timers[task.id] = Timer(const Duration(seconds: 15), () {
      _dismissToast(task);
      _timers.remove(task.id);
    });
  }

  void _dismissToast(GhostTask task) {
    if (mounted) {
      setState(() => _visibleTasks.removeWhere((t) => t.id == task.id));
    }
  }
}

class _GhostToast extends ConsumerStatefulWidget {
  final GhostTask task;
  final VoidCallback onDismiss;
  final VoidCallback onViewChanges;
  final VoidCallback onUndo;

  const _GhostToast({
    required this.task,
    required this.onDismiss,
    required this.onViewChanges,
    required this.onUndo,
  });

  @override
  ConsumerState<_GhostToast> createState() => _GhostToastState();
}

class _GhostToastState extends ConsumerState<_GhostToast>
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
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
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
    final isSuccess = widget.task.status == GhostStatus.completed;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: Spacing.sm),
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: tokens.bgLighter,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: isSuccess
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title row
              Row(
                children: [
                  Icon(
                    Icons.visibility_off,
                    size: 16,
                    color: isSuccess ? tokens.success : tokens.error,
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      isSuccess ? 'Ghost Complete' : 'Ghost Failed',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.close,
                          size: 14, color: tokens.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),

              // Summary
              Text(
                widget.task.summary ??
                    widget.task.error ??
                    widget.task.description,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Action buttons
              if (isSuccess) ...[
                const SizedBox(height: Spacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onUndo,
                      child: Text(
                        'Undo',
                        style: TextStyle(
                          color: tokens.error,
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    TextButton(
                      onPressed: widget.onViewChanges,
                      child: Text(
                        'View Changes',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
