import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../agent/config/config.dart';
import '../../state/theme_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../enums/ai_provider.dart';
import '../../enums/connection_status.dart';

class CredentialCard extends ConsumerStatefulWidget {
  const CredentialCard({super.key});

  @override
  ConsumerState<CredentialCard> createState() => _CredentialCardState();
}

class _CredentialCardState extends ConsumerState<CredentialCard> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _appKeyController = TextEditingController();
  final _anthropicKeyController = TextEditingController();
  final _githubPatController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final config = await AgentConfig.load();
    if (!mounted) return;
    setState(() {
      if (config.ciscoClientId != null) {
        _clientIdController.text = config.ciscoClientId!;
      }
      if (config.ciscoClientSecret != null) {
        _clientSecretController.text = config.ciscoClientSecret!;
      }
      if (config.ciscoAppKey != null) {
        _appKeyController.text = config.ciscoAppKey!;
      }
      if (config.anthropicApiKey != null) {
        _anthropicKeyController.text = config.anthropicApiKey!;
      }
      if (config.githubPat != null) {
        _githubPatController.text = config.githubPat!;
      }
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _appKeyController.dispose();
    _anthropicKeyController.dispose();
    _githubPatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);

    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.bgLight,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
        boxShadow: Shadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cisco section
          _SectionLabel(
            label: 'Cisco Circuit API',
            color: tokens.circuitColor,
            icon: Icons.cloud_outlined,
          ),
          const SizedBox(height: Spacing.lg),
          _CredentialField(
            controller: _clientIdController,
            label: 'Client ID',
            obscure: false,
          ),
          const SizedBox(height: Spacing.md),
          _CredentialField(
            controller: _clientSecretController,
            label: 'Client Secret',
            obscure: _obscure,
          ),
          const SizedBox(height: Spacing.md),
          _CredentialField(
            controller: _appKeyController,
            label: 'App Key',
            obscure: _obscure,
          ),
          const SizedBox(height: Spacing.xl),

          // Divider
          Container(
            height: 1,
            color: tokens.border.withValues(alpha: 0.3),
          ),
          const SizedBox(height: Spacing.xl),

          // Anthropic section
          _SectionLabel(
            label: 'Anthropic Claude API',
            color: tokens.claudeColor,
            icon: Icons.auto_awesome_outlined,
          ),
          const SizedBox(height: Spacing.lg),
          _CredentialField(
            controller: _anthropicKeyController,
            label: 'API Key',
            obscure: _obscure,
          ),
          const SizedBox(height: Spacing.xl),

          // Divider
          Container(
            height: 1,
            color: tokens.border.withValues(alpha: 0.3),
          ),
          const SizedBox(height: Spacing.xl),

          // GitHub section
          const _SectionLabel(
            label: 'GitHub',
            color: Color(0xFF8B949E),
            icon: Icons.code_outlined,
          ),
          const SizedBox(height: Spacing.lg),
          _CredentialField(
            controller: _githubPatController,
            label: 'Personal Access Token',
            obscure: _obscure,
          ),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              'Used for GitHub tools (issues, PRs, repos). '
              'Generate at github.com/settings/tokens',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: Spacing.xl),

          // Error / success messages
          if (_errorMessage != null)
            _FeedbackMessage(
              message: _errorMessage!,
              icon: Icons.error_outline,
              color: tokens.error,
            ),
          if (_successMessage != null)
            _FeedbackMessage(
              message: _successMessage!,
              icon: Icons.check_circle_outline,
              color: tokens.success,
            ),

          // Actions row
          Row(
            children: [
              // Visibility toggle
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _obscure = !_obscure),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 14,
                        color: tokens.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _obscure ? 'Show' : 'Hide',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),

              // Connection status indicator
              if (connectionStatus == ConnectionStatus.connected)
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.lg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.success,
                          boxShadow: [
                            BoxShadow(
                              color: tokens.success.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Connected',
                        style: TextStyle(
                          color: tokens.success,
                          fontSize: FontSizes.xs,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Save & Connect button
              SizedBox(
                height: 32,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        )
                      : const Text('Save & Connect'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final settings = ref.read(settingsProvider);

    // Validate that at least one set of credentials is provided
    final hasCisco = _clientIdController.text.isNotEmpty &&
        _clientSecretController.text.isNotEmpty &&
        _appKeyController.text.isNotEmpty;
    final hasAnthropic = _anthropicKeyController.text.isNotEmpty;

    if (!hasCisco && !hasAnthropic) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please enter credentials for at least one provider.';
      });
      return;
    }

    // Validate active provider has credentials
    if (settings.activeProvider == AIProviderType.cisco && !hasCisco) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Cisco is selected but missing credentials. Fill all 3 fields.';
      });
      return;
    }
    if (settings.activeProvider == AIProviderType.anthropic && !hasAnthropic) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Anthropic is selected but API key is empty.';
      });
      return;
    }

    try {
      // Save credentials
      final config = AgentConfig(
        ciscoClientId: _clientIdController.text.isEmpty
            ? null
            : _clientIdController.text,
        ciscoClientSecret: _clientSecretController.text.isEmpty
            ? null
            : _clientSecretController.text,
        ciscoAppKey:
            _appKeyController.text.isEmpty ? null : _appKeyController.text,
        anthropicApiKey: _anthropicKeyController.text.isEmpty
            ? null
            : _anthropicKeyController.text,
        githubPat: _githubPatController.text.isEmpty
            ? null
            : _githubPatController.text,
      );

      await config.save();

      // Update connection status to connecting
      ref
          .read(connectionStatusProvider.notifier)
          .set(ConnectionStatus.connecting);

      // Try to connect
      final service = ref.read(agentServiceProvider);
      final workingDir = ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;

      final credentials = settings.activeProvider == AIProviderType.cisco
          ? {
              'client_id': _clientIdController.text,
              'client_secret': _clientSecretController.text,
              'app_key': _appKeyController.text,
            }
          : {'api_key': _anthropicKeyController.text};

      final success = await service.connect(
        providerType: settings.activeProvider,
        credentials: credentials,
        workingDir: workingDir,
      );

      if (success) {
        ref
            .read(connectionStatusProvider.notifier)
            .set(ConnectionStatus.connected);
        setState(() {
          _successMessage =
              'Connected to ${settings.activeProvider.displayName}';
        });
      } else {
        ref.read(connectionStatusProvider.notifier).set(ConnectionStatus.error);
        // Surface the actual error from the agent service
        final serviceError = service.state.error;
        setState(() {
          _errorMessage = serviceError != null
              ? serviceError.replaceFirst('Exception: ', '')
              : 'Connection failed. Check credentials and try again.';
        });
      }
    } catch (e) {
      ref.read(connectionStatusProvider.notifier).set(ConnectionStatus.error);
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

class _SectionLabel extends ConsumerWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _SectionLabel({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: FontSizes.sm,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _FeedbackMessage extends ConsumerWidget {
  final String message;
  final IconData icon;
  final Color color;

  const _FeedbackMessage({
    required this.message,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: color,
                  fontSize: FontSizes.xs,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialField extends ConsumerWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;

  const _CredentialField({
    required this.controller,
    required this.label,
    required this.obscure,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: FontSizes.sm,
          fontFamily: 'JetBrains Mono',
          letterSpacing: 0.3,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: Spacing.md),
        ),
      ),
    );
  }
}
