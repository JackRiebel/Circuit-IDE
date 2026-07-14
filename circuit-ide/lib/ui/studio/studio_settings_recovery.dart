import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../services/studio_project_transfer_service.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';

/// Repairs and exports durable Studio thread-history recovery data.
class StudioThreadHistoryRecoveryPanel extends ConsumerStatefulWidget {
  const StudioThreadHistoryRecoveryPanel({super.key});

  @override
  ConsumerState<StudioThreadHistoryRecoveryPanel> createState() =>
      _ThreadHistoryRecoveryPanelState();
}

/// Imports and exports the redacted, portable project-history bundle.
class StudioProjectTransferPanel extends ConsumerStatefulWidget {
  const StudioProjectTransferPanel({super.key});

  @override
  ConsumerState<StudioProjectTransferPanel> createState() =>
      _ProjectTransferPanelState();
}

class _ProjectTransferPanelState
    extends ConsumerState<StudioProjectTransferPanel> {
  bool _isWorking = false;
  String? _status;

  Future<void> _export() async {
    final root = ref.read(fileTreeProvider).rootPath;
    if (root == null) return;
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Export CircuitCode project history',
      fileName: 'circuitcode-project-history.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (destination == null || !mounted) return;
    setState(() => _isWorking = true);
    try {
      final result = await StudioProjectTransferService().exportProject(
        root,
        destination,
      );
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status =
            'Exported ${result.taskCount} tasks and ${result.threadCount} conversations. Credentials were redacted; files and command logs remain references.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status = 'Unable to export this project history.';
      });
    }
  }

  Future<void> _import() async {
    final root = ref.read(fileTreeProvider).rootPath;
    if (root == null) return;
    final selection = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import CircuitCode project history',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final source = selection?.files.singleOrNull?.path;
    if (source == null || !mounted) return;
    setState(() => _isWorking = true);
    final service = StudioProjectTransferService();
    try {
      final result = await service.importProject(root, source);
      await _reloadAfterImport();
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status = _importStatus(result);
      });
    } on StateError catch (error) {
      if (!mounted) return;
      final merge = await _confirmMerge(error.message.toString());
      if (!merge || !mounted) {
        setState(() => _isWorking = false);
        return;
      }
      try {
        final result = await service.importProject(
          root,
          source,
          allowMerge: true,
        );
        await _reloadAfterImport();
        if (!mounted) return;
        setState(() {
          _isWorking = false;
          _status = _importStatus(result);
        });
      } catch (mergeError) {
        if (!mounted) return;
        setState(() {
          _isWorking = false;
          _status = 'Import was not applied: $mergeError';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status = 'Unable to import this project history.';
      });
    }
  }

  Future<void> _reloadAfterImport() async {
    await ref.read(agentWorkspaceProvider.notifier).reload();
    await ref.read(studioThreadProvider.notifier).reload();
  }

  Future<bool> _confirmMerge(String detail) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Merge project history?'),
        content: Text(
          '$detail\n\nCircuitCode will reject any task or conversation ID that would overwrite existing history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Merge safely'),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  String _importStatus(StudioProjectTransferImport result) {
    final missing = result.missingReferences.isEmpty
        ? ''
        : ' ${result.missingReferences.length} source reference${result.missingReferences.length == 1 ? '' : 's'} need relinking.';
    return 'Imported ${result.taskCount} tasks and ${result.threadCount} conversations.$missing';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final root = ref.watch(fileTreeProvider.select((state) => state.rootPath));
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Move readable tasks, plans, patches, and source references between installations. Secrets are redacted; source files, command logs, and raw artifact payloads are never copied.',
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
              OutlinedButton.icon(
                onPressed: _isWorking || root == null
                    ? null
                    : () => unawaited(_export()),
                icon: const Icon(StudioIcons.iosShareOutlined, size: 15),
                label: const Text('Export project'),
              ),
              OutlinedButton.icon(
                onPressed: _isWorking || root == null
                    ? null
                    : () => unawaited(_import()),
                icon: const Icon(StudioIcons.fileDownloadOutlined, size: 15),
                label: const Text('Import project'),
              ),
            ],
          ),
          if (root == null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Open the destination project before exporting or importing history.',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              _status!,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreadHistoryRecoveryPanelState
    extends ConsumerState<StudioThreadHistoryRecoveryPanel> {
  bool _isWorking = false;
  String? _status;

  Future<void> _repair() async {
    setState(() => _isWorking = true);
    try {
      final result = await ref
          .read(studioThreadProvider.notifier)
          .repairStorage();
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status = result?.message ?? 'Open a project before repairing history.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status =
            'Unable to repair thread history. Export recovery files before retrying.';
      });
    }
  }

  Future<void> _export() async {
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Export CircuitCode thread history recovery files',
      fileName: 'circuitcode-thread-history-recovery.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (destination == null || !mounted) return;
    setState(() => _isWorking = true);
    try {
      await ref
          .read(studioThreadProvider.notifier)
          .exportRecoveryBundle(destination);
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status = 'Thread history recovery files exported.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _status = 'Unable to export thread history recovery files.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(
      fileTreeProvider.select((state) => state.rootPath),
    );
    final recoveryMessage = ref.watch(
      studioThreadProvider.select((state) => state.recoveryMessage),
    );
    final status = _status ?? recoveryMessage;
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thread snapshots use checksums, a crash journal, rotating backups, and bounded journal compaction.',
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
              OutlinedButton.icon(
                onPressed: _isWorking || rootPath == null
                    ? null
                    : () => unawaited(_repair()),
                icon: const Icon(StudioIcons.buildOutlined, size: 15),
                label: const Text('Repair history'),
              ),
              OutlinedButton.icon(
                onPressed: _isWorking || rootPath == null
                    ? null
                    : () => unawaited(_export()),
                icon: const Icon(StudioIcons.folderZipOutlined, size: 15),
                label: const Text('Export recovery files'),
              ),
            ],
          ),
          if (rootPath == null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Open a project to repair or export its local thread history.',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              status,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ],
        ],
      ),
    );
  }
}
