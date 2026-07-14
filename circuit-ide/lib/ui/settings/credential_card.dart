import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../agent/config/config.dart';
import '../../state/theme_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../enums/ai_provider.dart';
import '../../enums/connection_status.dart';

class CredentialCard extends ConsumerStatefulWidget {
  /// Studio settings use the focused Circuit API form, while the legacy
  /// settings surface can continue to expose its GitHub token control.
  final bool includeGithub;

  const CredentialCard({super.key, this.includeGithub = true});

  @override
  ConsumerState<CredentialCard> createState() => _CredentialCardState();
}

class _CredentialCardState extends ConsumerState<CredentialCard> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _appKeyController = TextEditingController();
  final _githubPatController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  bool _isHydrating = true;
  Timer? _autosaveTimer;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    for (final controller in _credentialControllers) {
      controller.addListener(_scheduleAutosave);
    }
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
      if (config.githubPat != null) {
        _githubPatController.text = config.githubPat!;
      }
      _isHydrating = false;
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    for (final controller in _credentialControllers) {
      controller.removeListener(_scheduleAutosave);
    }
    unawaited(_persistCredentialsOnly());
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _appKeyController.dispose();
    _githubPatController.dispose();
    super.dispose();
  }

  List<TextEditingController> get _credentialControllers => [
    _clientIdController,
    _clientSecretController,
    _appKeyController,
    _githubPatController,
  ];

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
          // Circuit section
          _SectionLabel(
            label: 'Circuit Company AI',
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

          if (widget.includeGithub) ...[
            // Divider
            Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),
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
          ],

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

    final values = _credentialValues();
    final hasCisco = values.hasCisco;
    final hasAnySavedValue =
        values.hasCisco || (widget.includeGithub && values.githubPat != null);

    if (!hasAnySavedValue) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please enter Circuit credentials.';
      });
      return;
    }

    try {
      await _persistCredentialsOnly(values);

      if (!hasCisco) {
        ref
            .read(connectionStatusProvider.notifier)
            .set(ConnectionStatus.disconnected);
        setState(() {
          _successMessage =
              'Credentials saved. Fill all Circuit fields to connect.';
        });
        return;
      }

      // Update connection status to connecting
      ref
          .read(connectionStatusProvider.notifier)
          .set(ConnectionStatus.connecting);

      // Try to connect
      final service = ref.read(agentServiceProvider);
      final workingDir =
          ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;

      final success = await service.connect(
        providerType: AIProviderType.cisco,
        credentials: {
          'client_id': values.ciscoClientId!,
          'client_secret': values.ciscoClientSecret!,
          'app_key': values.ciscoAppKey!,
        },
        workingDir: workingDir,
      );
      final studioSuccess = await ref
          .read(studioAgentConnectionProvider.notifier)
          .connect(
            providerType: AIProviderType.cisco,
            credentials: {
              'client_id': values.ciscoClientId!,
              'client_secret': values.ciscoClientSecret!,
              'app_key': values.ciscoAppKey!,
            },
          );

      if (success && studioSuccess) {
        ref
            .read(connectionStatusProvider.notifier)
            .set(ConnectionStatus.connected);
        setState(() {
          _successMessage = 'Connected to Circuit Company AI';
        });
      } else {
        ref.read(connectionStatusProvider.notifier).set(ConnectionStatus.error);
        // Surface the actual error from the agent service
        final serviceError = service.state.error;
        setState(() {
          _errorMessage = serviceError != null
              ? serviceError.replaceFirst('Exception: ', '')
              : studioSuccess
              ? 'Connection failed. Check credentials and try again.'
              : 'Studio AI connection failed. Check credentials and try again.';
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

  void _scheduleAutosave() {
    if (_isHydrating) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_persistCredentialsOnly());
    });
  }

  Future<void> _persistCredentialsOnly([_CredentialValues? values]) async {
    values ??= _credentialValues();
    final config = AgentConfig(
      ciscoClientId: values.ciscoClientId,
      ciscoClientSecret: values.ciscoClientSecret,
      ciscoAppKey: values.ciscoAppKey,
      githubPat: values.githubPat,
    );
    await config.save();
  }

  _CredentialValues _credentialValues() {
    String? clean(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return _CredentialValues(
      ciscoClientId: clean(_clientIdController.text),
      ciscoClientSecret: clean(_clientSecretController.text),
      ciscoAppKey: clean(_appKeyController.text),
      githubPat: clean(_githubPatController.text),
    );
  }
}

class _CredentialValues {
  final String? ciscoClientId;
  final String? ciscoClientSecret;
  final String? ciscoAppKey;
  final String? githubPat;

  const _CredentialValues({
    required this.ciscoClientId,
    required this.ciscoClientSecret,
    required this.ciscoAppKey,
    required this.githubPat,
  });

  bool get hasCisco =>
      ciscoClientId != null && ciscoClientSecret != null && ciscoAppKey != null;

  bool get hasAny =>
      hasCisco ||
      ciscoClientId != null ||
      ciscoClientSecret != null ||
      ciscoAppKey != null ||
      githubPat != null;
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
            letterSpacing: 0,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        ),
      ),
    );
  }
}
