import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/chat_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/theme_provider.dart';

class SessionList extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onSessionLoaded;

  const SessionList({
    super.key,
    required this.onClose,
    required this.onSessionLoaded,
  });

  @override
  ConsumerState<SessionList> createState() => _SessionListState();
}

class _SessionListState extends ConsumerState<SessionList> {
  List<String>? _sessions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final service = ref.read(agentServiceProvider);
    final sessions = await service.listSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  Future<void> _deleteSession(String name) async {
    final service = ref.read(agentServiceProvider);
    await service.deleteSession(name);
    await _loadSessions();
  }

  Future<void> _loadSession(String name) async {
    final success = await ref.read(chatProvider.notifier).loadSession(name);
    if (success) {
      widget.onSessionLoaded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgLight,
        border: Border(
          bottom: BorderSide(color: tokens.border),
        ),
      ),
      constraints: const BoxConstraints(maxHeight: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 13, color: tokens.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'SAVED SESSIONS',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Session list
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
              ),
            )
          else if (_sessions == null || _sessions!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Center(
                child: Text(
                  'No saved sessions',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.sm,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                itemCount: _sessions!.length,
                itemBuilder: (context, index) {
                  final name = _sessions![index];
                  return _SessionRow(
                    name: name,
                    onLoad: () => _loadSession(name),
                    onDelete: () => _deleteSession(name),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionRow extends ConsumerStatefulWidget {
  final String name;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  const _SessionRow({
    required this.name,
    required this.onLoad,
    required this.onDelete,
  });

  @override
  ConsumerState<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends ConsumerState<_SessionRow> {
  bool _isHovered = false;

  String _formatSessionName(String name) {
    // Session names are like "dirname-2025-01-15T14-30-00"
    final parts = name.split('-');
    if (parts.length >= 4) {
      // Try to extract date portion
      try {
        final dateStr = parts.sublist(parts.length - 3).join('-')
            .replaceFirst('T', ' ');
        final projectName = parts.sublist(0, parts.length - 3).join('-');
        return '$projectName  $dateStr';
      } catch (_) {
        return name;
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AnimationDurations.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        color: _isHovered
            ? tokens.accent.withValues(alpha: 0.05)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 12,
              color: tokens.textMuted,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                _formatSessionName(widget.name),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xs,
                  fontFamily: 'JetBrains Mono',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isHovered) ...[
              const SizedBox(width: Spacing.sm),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onLoad,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      'Load',
                      style: TextStyle(
                        color: tokens.accent,
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Icon(
                    Icons.delete_outline,
                    size: 13,
                    color: tokens.error.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
