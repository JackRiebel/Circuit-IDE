import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../services/macos_update_service.dart';
import '../../state/macos_update_provider.dart';
import '../../state/studio_thread_provider.dart';
import 'studio_chrome.dart';
import 'studio_settings_view.dart' show StudioSettingsToggle;

/// User-owned controls for the signed Sparkle release path. This panel does
/// not expose feed URLs or raw installers, so Studio tasks cannot redirect an
/// application update toward arbitrary hosts or packages.
class StudioUpdateSettingsPanel extends ConsumerWidget {
  const StudioUpdateSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The app-shell listener owns the native Sparkle gate. Watching the same
    // state here keeps this visible control truthful while a request changes,
    // rather than waiting for a native status refresh.
    final activeMutation = ref.watch(
      studioThreadProvider.select(
        (state) => state.threads.any((thread) => thread.isActive),
      ),
    );
    final update = ref.watch(macosUpdateStatusProvider);
    final controller = ref.read(macosUpdateStatusProvider.notifier);
    return update.when(
      loading: () => const _UpdateStatusRow(detail: 'Checking update status…'),
      error: (_, _) => const _UpdateStatusRow(
        detail: 'Update status could not be loaded for this build.',
      ),
      data: (status) {
        final mutationActive = status.mutationActive || activeMutation;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UpdateStatusRow(
              detail: _detailFor(status),
              trailing: OutlinedButton.icon(
                onPressed:
                    status.configured && status.canCheck && !mutationActive
                    ? controller.checkForUpdates
                    : null,
                icon: const Icon(StudioIcons.refresh, size: 16),
                label: const Text('Check now'),
              ),
            ),
            if (status.configured) ...[
              const SizedBox(height: Spacing.sm),
              _UpdateControlRow(
                title: 'Release channel',
                detail:
                    'Stable receives general releases. Beta also receives reviewed preview releases.',
                trailing: PopupMenuButton<CircuitUpdateChannel>(
                  tooltip:
                      'Release channel: ${_channelLabel(status.channel)}. Choose update channel',
                  onSelected: controller.setChannel,
                  itemBuilder: (context) => CircuitUpdateChannel.values
                      .map(
                        (channel) => PopupMenuItem(
                          value: channel,
                          child: Text(_channelLabel(channel)),
                        ),
                      )
                      .toList(growable: false),
                  child: StudioMiniChip(label: _channelLabel(status.channel)),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              _UpdateControlRow(
                title: 'Check automatically',
                detail:
                    'Off by default. Enabling it permits signed background appcast checks.',
                trailing: StudioSettingsToggle(
                  value: status.automaticChecks,
                  semanticLabel: 'Check for signed app updates automatically',
                  tooltip: status.automaticChecks
                      ? 'Stop checking for signed app updates automatically'
                      : 'Check for signed app updates automatically',
                  onChanged: controller.setAutomaticChecks,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              _UpdateControlRow(
                title: 'Download automatically',
                detail:
                    'Only signed updates from the selected channel are downloaded.',
                trailing: StudioSettingsToggle(
                  value: status.automaticDownloads,
                  enabled: status.allowsAutomaticDownloads,
                  semanticLabel: 'Download signed app updates automatically',
                  tooltip: status.allowsAutomaticDownloads
                      ? status.automaticDownloads
                            ? 'Stop downloading signed app updates automatically'
                            : 'Download signed app updates automatically'
                      : 'Automatic downloads require automatic update checks',
                  onChanged: status.allowsAutomaticDownloads
                      ? controller.setAutomaticDownloads
                      : null,
                ),
              ),
            ],
            if (status.installDeferred || mutationActive) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Updates wait until active Studio work is finished, so no patch, command, or active request is interrupted.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _UpdateStatusRow extends StatelessWidget {
  final String detail;
  final Widget? trailing;

  const _UpdateStatusRow({required this.detail, this.trailing});

  @override
  Widget build(BuildContext context) => _UpdateControlRow(
    title: 'App updates',
    detail: detail,
    trailing: trailing,
  );
}

class _UpdateControlRow extends StatelessWidget {
  final String title;
  final String detail;
  final Widget? trailing;

  const _UpdateControlRow({
    required this.title,
    required this.detail,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: Spacing.md), trailing!],
      ],
    );
  }
}

String _channelLabel(CircuitUpdateChannel channel) => switch (channel) {
  CircuitUpdateChannel.stable => 'Stable',
  CircuitUpdateChannel.beta => 'Beta',
};

String _detailFor(CircuitUpdateStatus status) {
  if (!status.configured) {
    return status.message ??
        'This build does not include a signed update feed.';
  }
  if (status.checkInProgress) {
    return 'A signed update check is already in progress.';
  }
  if (status.lastCheckedAt != null) {
    final checked = status.lastCheckedAt!.toLocal();
    return 'Last checked ${checked.year}-${checked.month.toString().padLeft(2, '0')}-${checked.day.toString().padLeft(2, '0')}.';
  }
  return 'Only signed updates from the selected channel can be installed.';
}
