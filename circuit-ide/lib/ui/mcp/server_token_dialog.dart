import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';

/// Dialog for editing per-server tokens stored in secure storage.
class ServerTokenDialog extends ConsumerStatefulWidget {
  final String serverName;
  final List<String> requiredEnvVars;

  const ServerTokenDialog({
    super.key,
    required this.serverName,
    required this.requiredEnvVars,
  });

  @override
  ConsumerState<ServerTokenDialog> createState() => _ServerTokenDialogState();
}

class _ServerTokenDialogState extends ConsumerState<ServerTokenDialog> {
  final _controllers = <String, TextEditingController>{};
  bool _obscure = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    for (final envVar in widget.requiredEnvVars) {
      _controllers[envVar] = TextEditingController();
    }
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    final tokens = await ref
        .read(mcpHubProvider.notifier)
        .loadServerTokens(widget.serverName, widget.requiredEnvVars);
    if (!mounted) return;
    setState(() {
      for (final entry in tokens.entries) {
        _controllers[entry.key]?.text = entry.value;
      }
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.key, size: 16, color: tokens.accent),
                  const SizedBox(width: Spacing.md),
                  Text(
                    '${widget.serverName} Tokens',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.lg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),

              Text(
                'Tokens are stored securely in the OS keychain.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
              ),
              const SizedBox(height: Spacing.xl),

              if (_isLoading)
                Center(
                  child: CircularProgressIndicator(
                    color: tokens.accent,
                    strokeWidth: 2,
                  ),
                )
              else
                ...widget.requiredEnvVars.map(
                  (envVar) => Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.xl),
                    child: _buildTokenField(tokens, envVar),
                  ),
                ),

              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: tokens.textMuted),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenField(dynamic tokens, String envVar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          envVar,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _controllers[envVar],
          obscureText: _obscure,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Enter $envVar',
            hintStyle: TextStyle(color: tokens.textMuted),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            filled: true,
            fillColor: tokens.bgLighter,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: tokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: tokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: tokens.accent),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final tokenMap = <String, String>{};
    for (final entry in _controllers.entries) {
      tokenMap[entry.key] = entry.value.text.trim();
    }

    await ref
        .read(mcpHubProvider.notifier)
        .replaceServerTokens(
          widget.serverName,
          widget.requiredEnvVars,
          tokenMap,
        );
    if (!mounted) return;
    Navigator.pop(context);
  }
}
