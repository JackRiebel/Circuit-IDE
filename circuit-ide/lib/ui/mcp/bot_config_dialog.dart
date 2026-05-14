import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/mcp/bot_agent_config.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';

class BotConfigDialog extends ConsumerStatefulWidget {
  const BotConfigDialog({super.key});

  @override
  ConsumerState<BotConfigDialog> createState() => _BotConfigDialogState();
}

class _BotConfigDialogState extends ConsumerState<BotConfigDialog> {
  final _scriptPathController = TextEditingController();
  final _portController = TextEditingController(text: '8090');
  final _systemPromptController = TextEditingController();
  final _roomIdsController = TextEditingController();
  final _webexTokenController = TextEditingController();
  final _openaiKeyController = TextEditingController();
  String _model = 'gpt-4o';
  bool _obscure = true;
  bool _isLoading = true;

  static const _models = ['gpt-4o', 'gpt-4.1', 'gpt-4o-mini', 'o3-mini'];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final hubState = ref.read(mcpHubProvider);
    final notifier = ref.read(mcpHubProvider.notifier);

    // Load existing config
    if (hubState.botAgent != null) {
      final config = hubState.botAgent!.config;
      _scriptPathController.text = config.scriptPath ?? '';
      _portController.text = config.port.toString();
      _model = config.model;
      _systemPromptController.text = config.systemPrompt ?? '';
      _roomIdsController.text = config.roomIds.join(', ');
    }

    // Load tokens
    final tokens = await notifier.loadServerTokens(
      'bot_agent',
      BotAgentConfig.requiredEnvVars,
    );
    if (!mounted) return;
    setState(() {
      _webexTokenController.text = tokens['WEBEX_TOKEN'] ?? '';
      _openaiKeyController.text = tokens['OPENAI_API_KEY'] ?? '';
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _scriptPathController.dispose();
    _portController.dispose();
    _systemPromptController.dispose();
    _roomIdsController.dispose();
    _webexTokenController.dispose();
    _openaiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final hubState = ref.watch(mcpHubProvider);

    // Auto-populate MCP server URLs from running servers
    final runningUrls = hubState.servers
        .where((s) => s.connectionState == McpConnectionState.connected)
        .map((s) => s.config.url)
        .toList();

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      child: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xxl),
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: tokens.accent,
                      strokeWidth: 2,
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.smart_toy,
                              size: 16,
                              color: tokens.accent,
                            ),
                            const SizedBox(width: Spacing.md),
                            Text(
                              'Bot Agent Configuration',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: FontSizes.lg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Spacing.xxl),

                        // --- Tokens section ---
                        _sectionLabel(tokens, 'Tokens', Icons.key),
                        const SizedBox(height: Spacing.md),
                        Row(
                          children: [
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 14,
                                color: tokens.textMuted,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ],
                        ),
                        _buildField(
                          tokens,
                          'WEBEX_TOKEN',
                          _webexTokenController,
                          obscure: _obscure,
                        ),
                        const SizedBox(height: Spacing.lg),
                        _buildField(
                          tokens,
                          'OPENAI_API_KEY',
                          _openaiKeyController,
                          obscure: _obscure,
                        ),
                        const SizedBox(height: Spacing.xxl),

                        // --- Config section ---
                        _sectionLabel(tokens, 'Configuration', Icons.settings),
                        const SizedBox(height: Spacing.lg),
                        _buildField(
                          tokens,
                          'Script Path',
                          _scriptPathController,
                          hint: '/path/to/bot_agent.py',
                        ),
                        const SizedBox(height: Spacing.lg),
                        _buildField(
                          tokens,
                          'Port',
                          _portController,
                          hint: '8090',
                        ),
                        const SizedBox(height: Spacing.lg),

                        // Model dropdown
                        Text(
                          'Model',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.xs,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        DropdownButtonFormField<String>(
                          initialValue: _model,
                          dropdownColor: tokens.bgLighter,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.sm,
                          ),
                          decoration: _dropdownDecoration(tokens),
                          items: _models
                              .map(
                                (m) =>
                                    DropdownMenuItem(value: m, child: Text(m)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _model = v);
                          },
                        ),
                        const SizedBox(height: Spacing.lg),
                        _buildField(
                          tokens,
                          'System Prompt',
                          _systemPromptController,
                          hint: 'Optional system prompt for the bot',
                          maxLines: 3,
                        ),
                        const SizedBox(height: Spacing.lg),
                        _buildField(
                          tokens,
                          'Room IDs',
                          _roomIdsController,
                          hint: 'Comma-separated Webex room IDs',
                        ),

                        // Connected MCP servers (auto-populated)
                        if (runningUrls.isNotEmpty) ...[
                          const SizedBox(height: Spacing.lg),
                          Text(
                            'Connected MCP Servers',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: FontSizes.xs,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          ...runningUrls.map(
                            (url) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: Spacing.sm,
                              ),
                              child: Text(
                                url,
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: FontSizes.xs,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
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
                              onPressed: () => _save(runningUrls),
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
        ),
      ),
    );
  }

  Widget _sectionLabel(dynamic tokens, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 12, color: tokens.textSecondary),
        const SizedBox(width: Spacing.sm),
        Text(
          label,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    dynamic tokens,
    String label,
    TextEditingController controller, {
    String? hint,
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
            hintText: hint ?? 'Enter $label',
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

  Future<void> _save(List<String> runningUrls) async {
    final notifier = ref.read(mcpHubProvider.notifier);

    // Save tokens
    final tokenMap = <String, String>{};
    tokenMap['WEBEX_TOKEN'] = _webexTokenController.text.trim();
    tokenMap['OPENAI_API_KEY'] = _openaiKeyController.text.trim();
    await notifier.replaceBotTokens(tokenMap);

    // Parse room IDs
    final roomIds = _roomIdsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Save config
    final config = BotAgentConfig(
      scriptPath: _scriptPathController.text.trim().isEmpty
          ? null
          : _scriptPathController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 8090,
      model: _model,
      systemPrompt: _systemPromptController.text.trim().isEmpty
          ? null
          : _systemPromptController.text.trim(),
      roomIds: roomIds,
      mcpServerUrls: runningUrls,
    );

    await notifier.saveBotConfig(config);
    if (!mounted) return;
    Navigator.pop(context);
  }
}
