import '../core/config/studio_feature_flags.dart';
import '../models/computer_use.dart';

enum ComputerUseDecisionVerdict { requiresUserReview, deny }

enum ComputerUseDecisionReason {
  featureDisabled,
  missingSessionIdentity,
  missingActionIdentity,
  actionPreviewExpired,
  sessionInactive,
  sessionNotVisible,
  sessionHalted,
  wrongSession,
  missingVisibleTarget,
  missingVisibleElementTarget,
  missingDomain,
  applicationNotAllowed,
  domainNotAllowed,
  sensitiveField,
  invalidTypedInput,
  unsafePreviewTarget,
  targetNotNativeInspection,
  userConfirmationRequired,
}

class ComputerUseActionDecision {
  final ComputerUseDecisionVerdict verdict;
  final ComputerUseDecisionReason reason;
  final String message;

  const ComputerUseActionDecision({
    required this.verdict,
    required this.reason,
    required this.message,
  });

  bool get denied => verdict == ComputerUseDecisionVerdict.deny;
  bool get requiresUserReview =>
      verdict == ComputerUseDecisionVerdict.requiresUserReview;
}

/// Fail-closed approval contract for a future computer-use executor.
///
/// The production feature flag remains false, and this class intentionally
/// has no method that dispatches a desktop action. Its enabled branch exists
/// only so the future isolated worker has a tested, review-first contract.
class ComputerUseSafetyPolicy {
  final bool featureEnabled;
  final DateTime Function()? _clock;
  final Duration maximumPreviewAge;

  const ComputerUseSafetyPolicy({
    this.featureEnabled = StudioFeatureFlags.computerUse,
    DateTime Function()? clock,
    this.maximumPreviewAge = const Duration(minutes: 2),
  }) : _clock = clock;

  ComputerUseActionDecision evaluate({
    required ComputerUseSession session,
    required ComputerUseActionPreview preview,
  }) {
    if (!featureEnabled) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.featureDisabled,
        message:
            'Computer use is disabled. Studio does not expose desktop-control tools.',
      );
    }
    if (session.id.trim().isEmpty || preview.sessionId.trim().isEmpty) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.missingSessionIdentity,
        message:
            'Computer-use sessions and action previews require a non-empty session identity.',
      );
    }
    if (preview.id.trim().isEmpty) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.missingActionIdentity,
        message:
            'Computer-use action previews require a non-empty action identity.',
      );
    }
    if (!_hasFreshPreview(preview)) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.actionPreviewExpired,
        message:
            'Computer-use action preview expired. Reinspect the visible target and request a new review.',
      );
    }
    if (session.hasEmergencyStop) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.sessionHalted,
        message:
            'Computer-use session was stopped. Start a new visible session.',
      );
    }
    if (session.status != ComputerUseSessionStatus.active) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.sessionInactive,
        message: 'Computer-use actions require an active separate session.',
      );
    }
    if (!session.isVisible) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.sessionNotVisible,
        message:
            'Computer-use actions require a visible user-controlled session.',
      );
    }
    if (preview.sessionId != session.id) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.wrongSession,
        message: 'Action preview does not belong to the visible session.',
      );
    }
    if (!preview.target.hasVisibleTarget) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.missingVisibleTarget,
        message: 'Action preview must name a visible application and target.',
      );
    }
    if (preview.kind != ComputerUseActionKind.launchApplication &&
        !preview.target.hasVisibleElementTarget) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.missingVisibleElementTarget,
        message:
            'Computer-use action previews require an exact visible target role and label.',
      );
    }
    if (preview.kind == ComputerUseActionKind.navigateUrl &&
        (preview.target.domain == null ||
            preview.target.domain!.trim().isEmpty)) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.missingDomain,
        message:
            'Computer-use navigation previews require an exact allowlisted domain.',
      );
    }
    if (!session.policy.allowsApplication(preview.target.applicationId)) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.applicationNotAllowed,
        message: 'The target application is not allowlisted for this session.',
      );
    }
    if (!session.policy.allowsDomain(preview.target.domain)) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.domainNotAllowed,
        message: 'The target domain is not allowlisted for this session.',
      );
    }
    if (preview.target.isSensitiveField) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.sensitiveField,
        message:
            'Computer use refuses sensitive fields such as passwords, tokens, and payment data.',
      );
    }
    if (preview.kind == ComputerUseActionKind.typeText &&
        preview.inputCharacterCount <= 0) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.invalidTypedInput,
        message:
            'Computer-use typing previews require a positive character count.',
      );
    }
    if (!preview.target.hasSafeDisplayDetails) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.unsafePreviewTarget,
        message:
            'Computer-use previews refuse unbounded, secret-shaped, or path-shaped target details.',
      );
    }
    if (!preview.target.hasNativeInspection) {
      return const ComputerUseActionDecision(
        verdict: ComputerUseDecisionVerdict.deny,
        reason: ComputerUseDecisionReason.targetNotNativeInspection,
        message:
            'Computer-use actions require a target freshly inspected by the visible isolated session.',
      );
    }
    return const ComputerUseActionDecision(
      verdict: ComputerUseDecisionVerdict.requiresUserReview,
      reason: ComputerUseDecisionReason.userConfirmationRequired,
      message:
          'Show this action preview and require an explicit user confirmation before any isolated worker could act.',
    );
  }

  bool _hasFreshPreview(ComputerUseActionPreview preview) {
    final now = (_clock?.call() ?? DateTime.now()).toUtc();
    final createdAt = preview.createdAt.toUtc();
    if (createdAt.isAfter(now)) return false;
    return now.difference(createdAt) <= maximumPreviewAge;
  }
}
