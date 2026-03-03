import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/mcp/mcp_config.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';

class AddMcpServerDialog extends ConsumerStatefulWidget {
  const AddMcpServerDialog({super.key});

  @override
  ConsumerState<AddMcpServerDialog> createState() => _AddMcpServerDialogState();
}

class _AddMcpServerDialogState extends ConsumerState<AddMcpServerDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _headersController = TextEditingController();
  var _transport = McpTransportType.http;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _headersController.dispose();
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
              Text(
                'Add MCP Server',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.xxl),

              _buildField(tokens, 'Name', _nameController, 'e.g. my-tools'),
              const SizedBox(height: Spacing.xl),
              _buildField(tokens, 'URL', _urlController, 'http://localhost:3000/mcp'),
              const SizedBox(height: Spacing.xl),

              Text(
                'Transport',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<McpTransportType>(
                initialValue: _transport,
                dropdownColor: tokens.bgLighter,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                ),
                decoration: InputDecoration(
                  isDense: true,
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
                ),
                items: McpTransportType.values.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(t.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _transport = v);
                },
              ),
              const SizedBox(height: Spacing.xl),

              _buildField(
                tokens,
                'Headers (optional)',
                _headersController,
                'key: value (one per line)',
                maxLines: 3,
              ),

              const SizedBox(height: Spacing.xxl),
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
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                    ),
                    child: const Text('Add Server'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    dynamic tokens,
    String label,
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
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

  void _submit() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || url.isEmpty) return;

    // Parse headers
    final headers = <String, String>{};
    for (final line in _headersController.text.split('\n')) {
      final idx = line.indexOf(':');
      if (idx > 0) {
        headers[line.substring(0, idx).trim()] =
            line.substring(idx + 1).trim();
      }
    }

    final config = McpServerConfig(
      name: name,
      url: url,
      transport: _transport,
      headers: headers,
    );

    ref.read(mcpHubProvider.notifier).addServer(config);
    Navigator.pop(context);
  }
}
