import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/security/audit_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/design_tokens.dart';
import '../../models/settings_model.dart';
import '../../models/studio_failure_slo_report.dart';
import '../../models/studio_turn_trace.dart';
import '../../services/privacy_crash_reporter.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_settings_view.dart' show StudioSettingsToggle;

/// Retains, inspects, deletes, and exports locally redacted diagnostics.
class StudioDiagnosticRetentionPanel extends ConsumerStatefulWidget {
  const StudioDiagnosticRetentionPanel({super.key});

  @override
  ConsumerState<StudioDiagnosticRetentionPanel> createState() =>
      _DiagnosticRetentionPanelState();
}

class _DiagnosticRetentionPanelState
    extends ConsumerState<StudioDiagnosticRetentionPanel> {
  List<AuditLogSession> _sessions = const [];
  bool _isLoading = false;
  String? _statusMessage;

  AuditLogger _auditLogger() => AuditLogger(
    retention: Duration(
      days: ref.read(settingsProvider).diagnosticRetentionDays,
    ),
  );

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final auditLogger = _auditLogger();
      await auditLogger.purgeExpired();
      final sessions = await auditLogger.listSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoading = false;
        _statusMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to load retained diagnostics.';
      });
    }
  }

  Future<void> _inspect(AuditLogSession session) async {
    final content = await _auditLogger().inspectSession(session.id);
    if (!mounted) return;
    final tokens = ref.read(themeProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: tokens.studioPanel,
        title: Text(
          'Redacted diagnostics',
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.md),
        ),
        content: SizedBox(
          width: 640,
          height: 380,
          child: SingleChildScrollView(
            child: SelectableText(
              content ??
                  'This retained diagnostic record is no longer available.',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(AuditLogSession session) async {
    final deleted = await _auditLogger().deleteSession(session.id);
    if (!mounted || !deleted) return;
    setState(
      () => _sessions = _sessions
          .where((candidate) => candidate.id != session.id)
          .toList(growable: false),
    );
  }

  Future<void> _export() async {
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Export redacted CircuitCode support bundle',
      fileName: 'circuitcode-support-bundle.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (destination == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final settings = ref.read(settingsProvider);
      await _auditLogger().exportSupportBundle(
        destination,
        metadata: _supportMetadata(ref, settings),
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Redacted support bundle exported.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to export the support bundle.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final retentionDays = ref.watch(
      settingsProvider.select((settings) => settings.diagnosticRetentionDays),
    );
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Retained diagnostics are redacted before storage and automatically expire after $retentionDays days.',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              height: 1.35,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              PopupMenuButton<int>(
                tooltip: 'Choose diagnostics retention period',
                onSelected: (days) {
                  ref
                      .read(settingsProvider.notifier)
                      .setDiagnosticRetentionDays(days);
                  unawaited(_load());
                },
                itemBuilder: (context) => [
                  for (final days in [7, 14, 30])
                    CheckedPopupMenuItem<int>(
                      value: days,
                      checked: days == retentionDays,
                      child: Text('Keep for $days days'),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: tokens.studioDivider),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        StudioIcons.scheduleOutlined,
                        size: 15,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Text(
                        'Retention: $retentionDays days',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_export()),
                icon: const Icon(StudioIcons.iosShareOutlined, size: 15),
                label: const Text('Export redacted bundle'),
              ),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              _statusMessage!,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          if (_sessions.isEmpty) ...[
            Text(
              'Load records only when you want to inspect or delete them.',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
            TextButton(
              onPressed: () => unawaited(_load()),
              child: const Text('Load retained diagnostics'),
            ),
          ] else
            for (final session in _sessions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      StudioIcons.shieldOutlined,
                      size: 14,
                      color: tokens.success,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        '${session.modifiedAt.toLocal().toString().split('.').first} · ${_formatBytes(session.byteLength)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_inspect(session)),
                      child: const Text('Inspect'),
                    ),
                    StudioChromeIconButton(
                      tooltip: 'Delete diagnostics record',
                      onTap: () => unawaited(_delete(session)),
                      icon: StudioIcons.deleteOutline,
                      iconSize: 17,
                    ),
                  ],
                ),
              ),
          if (_sessions.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => unawaited(_load()),
                child: const Text('Refresh retained diagnostics'),
              ),
            ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Configures and exports local-only redacted crash reports.
class StudioCrashReportingPanel extends ConsumerStatefulWidget {
  const StudioCrashReportingPanel({super.key});

  @override
  ConsumerState<StudioCrashReportingPanel> createState() =>
      _CrashReportingPanelState();
}

class _CrashReportingPanelState
    extends ConsumerState<StudioCrashReportingPanel> {
  bool _isExporting = false;
  String? _statusMessage;

  PrivacyCrashReporter _reporter() => PrivacyCrashReporter(
    isEnabled: () => ref.read(settingsProvider).crashReportingEnabled,
  );

  Future<void> _export() async {
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Export local CircuitCode crash reports',
      fileName: 'circuitcode-crash-reports.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (destination == null || !mounted) return;
    setState(() => _isExporting = true);
    try {
      await _reporter().export(File(destination));
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _statusMessage = 'Redacted crash reports exported locally.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _statusMessage = 'Unable to export local crash reports.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final enabled = ref.watch(
      settingsProvider.select((settings) => settings.crashReportingEnabled),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local crash reports',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Off by default. Reports stay on this device and are never uploaded automatically.',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              StudioSettingsToggle(
                value: enabled,
                semanticLabel: 'Keep local crash reports',
                tooltip: enabled
                    ? 'Stop keeping local crash reports'
                    : 'Keep redacted crash reports on this device',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setCrashReportingEnabled(value),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Prompts, source, tokens, credentials, and diagnostic bodies are redacted before writing. Export only when you choose to share it with support.',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              height: 1.35,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            onPressed: _isExporting ? null : () => unawaited(_export()),
            icon: const Icon(StudioIcons.iosShareOutlined, size: 15),
            label: Text(
              _isExporting
                  ? 'Exporting local reports…'
                  : 'Export local reports',
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              _statusMessage!,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ],
        ],
      ),
    );
  }
}

Map<String, dynamic> _supportMetadata(WidgetRef ref, SettingsModel settings) {
  final thread = ref.read(studioThreadProvider).selectedThread;
  final rootPath = ref.read(fileTreeProvider).rootPath;
  return {
    'product': 'CircuitCode',
    'appVersion': AppConstants.appVersion,
    'selectedModel': settings.ciscoModel,
    'retentionDays': settings.diagnosticRetentionDays,
    'projectPath': rootPath,
    'connectorHealth': {
      'status': settings.connectorHealthStatus.name,
      'endpoint': settings.connectorHealthEndpoint,
      if (settings.connectorHealthProtocolVersion > 0)
        'protocolVersion': settings.connectorHealthProtocolVersion,
      if (settings.connectorHealthLatencyMs > 0)
        'latencyMs': settings.connectorHealthLatencyMs,
      'lastErrorCategory': settings.connectorHealthErrorCategory.name,
      if (settings.connectorHealthRetryAdvice.isNotEmpty)
        'retryAdvice': settings.connectorHealthRetryAdvice,
    },
    if (thread != null) ...{
      'threadId': thread.id,
      'requestId': thread.requestId,
      'taskId': thread.taskId,
      'threadStatus': thread.status.name,
      'traces': [
        for (final turn in thread.turns)
          StudioTurnTraceBuilder.build(thread: thread, turn: turn).toJson(),
      ],
      'sourceArtifactIds': thread.sourceArtifacts
          .map((item) => item.id)
          .toList(),
      'failureSlo': StudioFailureSloReport.fromTurns(thread.turns).toJson(),
    },
  };
}
