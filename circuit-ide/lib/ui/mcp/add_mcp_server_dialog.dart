import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/mcp/github_mcp.dart';
import '../../agent/mcp/jira_mcp.dart';
import '../../agent/mcp/mcp_config.dart';
import '../../agent/mcp/webex_mcp.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';

class AddMcpServerDialog extends ConsumerStatefulWidget {
  const AddMcpServerDialog({super.key});

  @override
  ConsumerState<AddMcpServerDialog> createState() => _AddMcpServerDialogState();
}

enum _ServerPreset { custom, webex, jira, github }

class _AddMcpServerDialogState extends ConsumerState<AddMcpServerDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _headersController = TextEditingController();
  final _scriptPathController = TextEditingController();
  final _tokenControllers = <String, TextEditingController>{};
  var _transport = McpTransportType.http;
  var _preset = _ServerPreset.custom;
  bool _obscureTokens = true;

  List<String> get _requiredEnvVars {
    switch (_preset) {
      case _ServerPreset.webex:
        return WebexMcp.requiredEnvVars;
      case _ServerPreset.jira:
        return JiraMcp.requiredEnvVars;
      case _ServerPreset.github:
        return GitHubMcp.requiredEnvVars;
      case _ServerPreset.custom:
        return [];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _headersController.dispose();
    _scriptPathController.dispose();
    for (final c in _tokenControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureTokenControllers(List<String> envVars) {
    // Remove controllers for env vars no longer needed
    final toRemove = _tokenControllers.keys
        .where((k) => !envVars.contains(k))
        .toList();
    for (final k in toRemove) {
      _tokenControllers[k]?.dispose();
      _tokenControllers.remove(k);
    }
    // Add controllers for new env vars
    for (final envVar in envVars) {
      _tokenControllers.putIfAbsent(envVar, () => TextEditingController());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final envVars = _requiredEnvVars;
    _ensureTokenControllers(envVars);

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      child: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xxl),
            child: SingleChildScrollView(
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

                  Text(
                    'Quick Setup',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  DropdownButtonFormField<_ServerPreset>(
                    initialValue: _preset,
                    dropdownColor: tokens.bgLighter,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                    ),
                    decoration: _dropdownDecoration(tokens),
                    items: const [
                      DropdownMenuItem(
                        value: _ServerPreset.custom,
                        child: Text('Custom'),
                      ),
                      DropdownMenuItem(
                        value: _ServerPreset.webex,
                        child: Text('Webex Teams'),
                      ),
                      DropdownMenuItem(
                        value: _ServerPreset.jira,
                        child: Text('Jira'),
                      ),
                      DropdownMenuItem(
                        value: _ServerPreset.github,
                        child: Text('GitHub'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _preset = v;
                        _applyPreset(v);
                      });
                    },
                  ),
                  const SizedBox(height: Spacing.xl),

                  _buildField(tokens, 'Name', _nameController, 'e.g. my-tools'),
                  const SizedBox(height: Spacing.xl),
                  _buildField(
                    tokens,
                    'URL',
                    _urlController,
                    'http://localhost:3000/mcp',
                  ),
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
                    decoration: _dropdownDecoration(tokens),
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

                  // Script Path field
                  _buildField(
                    tokens,
                    'Script Path (optional)',
                    _scriptPathController,
                    '/path/to/server.py',
                  ),
                  const SizedBox(height: Spacing.xl),

                  // Token fields (contextual, based on preset)
                  if (envVars.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.key, size: 12, color: tokens.textSecondary),
                        const SizedBox(width: Spacing.sm),
                        Text(
                          'Tokens',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.xs,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _obscureTokens
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 14,
                            color: tokens.textMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscureTokens = !_obscureTokens),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Stored securely in OS keychain, never saved to JSON.',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    ...envVars.map(
                      (envVar) => Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.lg),
                        child: _buildField(
                          tokens,
                          envVar,
                          _tokenControllers[envVar]!,
                          'Enter $envVar',
                          obscure: _obscureTokens,
                        ),
                      ),
                    ),
                  ],

                  if (envVars.isEmpty) ...[
                    _buildField(
                      tokens,
                      'Headers (optional)',
                      _headersController,
                      'key: value (one per line)',
                      maxLines: 3,
                    ),
                  ],

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
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(dynamic tokens) {
    return InputDecoration(
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
    );
  }

  Widget _buildField(
    dynamic tokens,
    String label,
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    bool obscure = false,
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
          maxLines: obscure ? 1 : maxLines,
          obscureText: obscure,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
            fontFamily: obscure ? 'monospace' : null,
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

  void _applyPreset(_ServerPreset preset) {
    switch (preset) {
      case _ServerPreset.webex:
        _nameController.text = 'webex';
        _urlController.text = 'http://localhost:5001/mcp';
        _transport = McpTransportType.http;
      case _ServerPreset.jira:
        _nameController.text = 'jira';
        _urlController.text = 'http://localhost:5002/mcp';
        _transport = McpTransportType.http;
      case _ServerPreset.github:
        _nameController.text = 'github';
        _urlController.text = 'http://localhost:5003/mcp';
        _transport = McpTransportType.http;
      case _ServerPreset.custom:
        break;
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || url.isEmpty) return;

    final notifier = ref.read(mcpHubProvider.notifier);
    final envVars = _requiredEnvVars;

    // Save tokens to secure storage (never to JSON)
    if (envVars.isNotEmpty) {
      final tokenMap = <String, String>{};
      for (final envVar in envVars) {
        final value = _tokenControllers[envVar]?.text.trim() ?? '';
        if (value.isNotEmpty) {
          tokenMap[envVar] = value;
        }
      }
      if (tokenMap.isNotEmpty) {
        await notifier.saveServerTokens(name, tokenMap);
      }
    }

    // Parse headers for custom servers
    final headers = <String, String>{};
    if (envVars.isEmpty) {
      for (final line in _headersController.text.split('\n')) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          headers[line.substring(0, idx).trim()] = line
              .substring(idx + 1)
              .trim();
        }
      }
    } else {
      headers['Accept'] = 'application/json';
    }

    final scriptPath = _scriptPathController.text.trim();

    final config = McpServerConfig(
      name: name,
      url: url,
      transport: _transport,
      headers: headers,
      scriptPath: scriptPath.isEmpty ? null : scriptPath,
      requiredEnvVars: envVars,
    );

    await notifier.addServer(config);
    if (!mounted) return;
    Navigator.pop(context);
  }
}
