import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../agent/config/config.dart';
import '../core/utils/platform_utils.dart';
import '../models/accepted_plan_context.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/turn_intent.dart';
import '../state/file_tree_provider.dart';
import '../state/patch_proposal_provider.dart';
import '../state/studio_thread_provider.dart';
import '../state/studio_turn_provider.dart';
import 'crash_reporting_boundary.dart';
import 'privacy_crash_reporter.dart';

typedef PackagedStudioSmokeShellMount =
    FutureOr<void> Function(ProviderContainer container);

/// A release-bundle-only smoke scenario, selected by the CI environment rather
/// than any user or model action. It proves that the shipped executable can
/// run a bounded local Studio lifecycle without a provider, network access, or
/// user workspace: open a temporary project, register an accepted plan, apply
/// a patch, record verification, persist, reload, archive, and restore.
class PackagedStudioSmoke {
  static Future<PackagedStudioSmokeResult> run({
    PackagedStudioSmokeShellMount? onContainerReady,
    SecureCredentialStore? secureCredentialStore,
    bool verifySecureCredentialPersistence = false,
  }) async {
    final originalConfigDir = PlatformUtils.configDirOverride;
    final originalDebounce =
        StudioThreadController.debugPersistDebounceOverride;
    Directory? root;
    ProviderContainer? container;
    try {
      root = await Directory.systemTemp.createTemp('circuit-packaged-smoke-');
      final config = await Directory(p.join(root.path, 'config')).create();
      final project = await Directory(p.join(root.path, 'project')).create();
      PlatformUtils.configDirOverride = config.path;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      await _verifyRedactedCrashBoundary(root);
      if (verifySecureCredentialPersistence) {
        await _verifySecureCredentialPersistence(
          secureCredentialStore ?? const FlutterSecureCredentialStore(),
        );
      }

      final patchStore = PatchProposalStore(
        baseDir: p.join(root.path, 'patches'),
      );
      container = ProviderContainer(
        overrides: [patchProposalStoreProvider.overrideWithValue(patchStore)],
      );
      await onContainerReady?.call(container);
      await container
          .read(fileTreeProvider.notifier)
          .openDirectory(project.path);
      await container.read(studioThreadProvider.notifier).reload();

      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Packaged smoke task');
      const requestId = 'packaged-smoke-request';
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'packaged-smoke-plan',
        title: 'Packaged smoke plan',
        summary: 'Create a local marker and verify it.',
        markdown: '# Packaged smoke plan\n\n- Create lib/marker.dart\n- Verify',
        plannedTargets: [
          PlannedFileTarget(
            path: 'lib/marker.dart',
            intent: 'Create the smoke marker',
            operation: ProposedFileEditType.create,
          ),
        ],
        verificationRequested: true,
      );
      container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            userMessageId: 'packaged-smoke-message',
            prompt: 'Apply the accepted local smoke plan.',
            model: 'packaged-smoke',
            intent: TurnIntent.code,
            acceptedPlanState: AcceptedPlanState.accepted,
            acceptedPlanContext: acceptedPlan,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'Temporary packaged smoke project',
              includedItemCount: 0,
              estimatedTokens: 0,
            ),
          );
      final patch = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Create packaged smoke marker',
            runId: requestId,
            verificationRequested: true,
            edits: const [
              ProposedFileEdit(
                path: 'lib/marker.dart',
                type: ProposedFileEditType.create,
                after: 'const packagedStudioSmokeMarker = true;\n',
              ),
            ],
          );
      final apply = await container
          .read(patchProposalProvider.notifier)
          .apply(patch.id);
      _require(apply.applied, 'patch_apply');
      _require(
        await File(p.join(project.path, 'lib', 'marker.dart')).exists(),
        'patch_file',
      );

      container
          .read(studioTurnProvider.notifier)
          .recordCommandRunResult(
            requestId,
            commandRunId: 'packaged-smoke-verify',
            command: 'test -f lib/marker.dart',
            status: 'succeeded',
            output: 'marker present',
            exitCode: 0,
          );
      final verifiedTurn = _turnFor(
        container.read(studioThreadProvider),
        thread.id,
        requestId,
      );
      _require(
        verifiedTurn.steps.any(
          (step) =>
              step.step == TurnStep.verification &&
              step.status == TurnStepStatus.completed,
        ),
        'verification',
      );

      await container
          .read(studioThreadProvider.notifier)
          .flushPendingPersistence();
      final store = StudioThreadStore(
        baseDir: p.join(config.path, 'studio_threads'),
      );
      final reloaded = await store.load(project.path);
      _require(
        reloaded.any(
          (candidate) =>
              candidate.id == thread.id &&
              candidate.turns.any((turn) => turn.requestId == requestId),
        ),
        'restart_reload',
      );

      final threadController = container.read(studioThreadProvider.notifier);
      threadController.archiveThread(thread.id);
      _require(
        _threadFor(container.read(studioThreadProvider), thread.id).archived,
        'archive',
      );
      _require(threadController.restoreThread(thread.id), 'restore_action');
      _require(
        !_threadFor(container.read(studioThreadProvider), thread.id).archived,
        'restore',
      );
      await threadController.flushPendingPersistence();
      return const PackagedStudioSmokeResult.passed();
    } on _PackagedStudioSmokeFailure catch (error) {
      return PackagedStudioSmokeResult.failed(error.stage);
    } catch (_) {
      return const PackagedStudioSmokeResult.failed('unexpected');
    } finally {
      if (container != null) {
        try {
          await container
              .read(studioThreadProvider.notifier)
              .flushPendingPersistence();
        } finally {
          container.dispose();
        }
      }
      PlatformUtils.configDirOverride = originalConfigDir;
      StudioThreadController.debugPersistDebounceOverride = originalDebounce;
      if (root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  }

  static StudioTurn _turnFor(
    StudioThreadState state,
    String threadId,
    String requestId,
  ) {
    final thread = _threadFor(state, threadId);
    return thread.turns.singleWhere((turn) => turn.requestId == requestId);
  }

  static StudioThread _threadFor(StudioThreadState state, String threadId) {
    return state.threads.singleWhere((thread) => thread.id == threadId);
  }

  static Future<void> _verifyRedactedCrashBoundary(Directory root) async {
    const secret = 'packaged-smoke-private-token';
    final reporter = PrivacyCrashReporter(
      isEnabled: () => true,
      directoryPath: p.join(root.path, 'crash-audit'),
    );
    reporter.addBreadcrumb(
      CrashBreadcrumbEvent.turnFailed,
      metadata: {
        'prompt': 'Do not retain this packaged smoke customer request.',
        'authorization': 'Bearer $secret',
      },
    );
    final boundary = CrashReportingBoundary(
      reporter: reporter,
      presentFlutterError: (_) {},
    );
    final stack = StackTrace.fromString(
      '#0 packagedSmoke (/Users/example/private/project.dart:12:3) '
      'token=$secret prompt=private customer content',
    );
    boundary.handleFlutterError(
      FlutterErrorDetails(
        exception: StateError('prompt=private customer content'),
        stack: stack,
      ),
    );
    _require(
      !boundary.handlePlatformError(
        StateError('authorization=Bearer $secret'),
        stack,
      ),
      'privacy_platform_propagation',
    );
    final persisted = await File(reporter.filePath).readAsString();
    _require(persisted.contains('"source":"flutter"'), 'privacy_flutter');
    _require(persisted.contains('"source":"platform"'), 'privacy_platform');
    _require(persisted.contains('[PATH]'), 'privacy_path_redaction');
    _require(
      !persisted.contains('private customer content') &&
          !persisted.contains(secret),
      'privacy_secret_redaction',
    );
    _require((await reporter.load()).length == 2, 'privacy_record_count');
  }

  /// Proves the packaged executable can use the same credential-store route
  /// as Settings. The bounded probe never touches a user credential key and
  /// always removes its inert fixture before continuing the smoke lifecycle.
  static Future<void> _verifySecureCredentialPersistence(
    SecureCredentialStore store,
  ) async {
    const key = 'circuitcode_packaged_credential_probe';
    const value = 'packaged-credential-probe';
    try {
      await store.delete(key: key);
      await store.write(key: key, value: value);
      _require(
        await store.read(key: key) == value,
        'secure_credentials_readback',
      );
      await store.delete(key: key);
      _require(
        await store.read(key: key) == null,
        'secure_credentials_cleanup',
      );
    } catch (_) {
      // A retry cleanup is safe even when the first write/read failed.
      try {
        await store.delete(key: key);
      } catch (_) {}
      throw const _PackagedStudioSmokeFailure('secure_credentials');
    }
  }

  static void _require(bool condition, String stage) {
    if (!condition) throw _PackagedStudioSmokeFailure(stage);
  }
}

class PackagedStudioSmokeResult {
  final bool passed;
  final String stage;

  const PackagedStudioSmokeResult._({
    required this.passed,
    required this.stage,
  });

  const PackagedStudioSmokeResult.passed() : this._(passed: true, stage: 'ok');

  const PackagedStudioSmokeResult.failed(String stage)
    : this._(passed: false, stage: stage);
}

class _PackagedStudioSmokeFailure implements Exception {
  final String stage;

  const _PackagedStudioSmokeFailure(this.stage);
}
