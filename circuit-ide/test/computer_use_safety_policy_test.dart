import 'package:circuit_ide/models/computer_use.dart';
import 'package:circuit_ide/services/computer_use_safety_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final startedAt = DateTime.utc(2026, 7, 13);
  const safeTarget = ComputerUseTarget(
    applicationId: 'com.example.browser',
    applicationLabel: 'Example Browser',
    domain: 'example.test',
    elementRole: 'button',
    elementLabel: 'Open report',
    evidence: ComputerUseTargetEvidence.nativeInspection,
  );
  final activeSession = ComputerUseSession(
    id: 'session-1',
    status: ComputerUseSessionStatus.active,
    isVisible: true,
    createdAt: startedAt,
    policy: ComputerUseSessionPolicy(
      allowedApplicationIds: {'com.example.browser'},
      allowedDomains: {'example.test'},
    ),
  );
  ComputerUseActionPreview preview({
    ComputerUseTarget target = safeTarget,
    String sessionId = 'session-1',
    DateTime? createdAt,
  }) => ComputerUseActionPreview(
    id: 'action-1',
    sessionId: sessionId,
    kind: ComputerUseActionKind.click,
    target: target,
    summary: 'Select the visible Open report button.',
    createdAt: createdAt ?? startedAt,
  );

  ComputerUseSafetyPolicy enabledPolicy({DateTime? now}) =>
      ComputerUseSafetyPolicy(
        featureEnabled: true,
        clock: () => now ?? startedAt,
      );

  test('computer-use policy is disabled by default', () {
    final decision = const ComputerUseSafetyPolicy().evaluate(
      session: activeSession,
      preview: preview(),
    );

    expect(decision.denied, isTrue);
    expect(decision.reason, ComputerUseDecisionReason.featureDisabled);
  });

  test('future enabled policy keeps every action review-first', () {
    final decision = enabledPolicy().evaluate(
      session: activeSession,
      preview: preview(),
    );

    expect(decision.requiresUserReview, isTrue);
    expect(decision.reason, ComputerUseDecisionReason.userConfirmationRequired);
    expect(preview().requiresUserConfirmation, isTrue);
  });

  test(
    'policy denies invisible, unallowlisted, sensitive, and halted actions',
    () {
      final policy = enabledPolicy();
      final invisible = activeSession.copyWith(isVisible: false);
      expect(
        policy.evaluate(session: invisible, preview: preview()).reason,
        ComputerUseDecisionReason.sessionNotVisible,
      );

      final unallowlisted = activeSession.copyWith(
        policy: ComputerUseSessionPolicy(
          allowedApplicationIds: {'com.example.notes'},
        ),
      );
      expect(
        policy.evaluate(session: unallowlisted, preview: preview()).reason,
        ComputerUseDecisionReason.applicationNotAllowed,
      );

      final sensitive = preview(
        target: const ComputerUseTarget(
          applicationId: 'com.example.browser',
          applicationLabel: 'Example Browser',
          domain: 'example.test',
          elementRole: 'password field',
          elementLabel: 'Account password',
        ),
      );
      expect(
        policy.evaluate(session: activeSession, preview: sensitive).reason,
        ComputerUseDecisionReason.sensitiveField,
      );

      final halted = activeSession.emergencyStop(startedAt);
      expect(
        policy.evaluate(session: halted, preview: preview()).reason,
        ComputerUseDecisionReason.sessionHalted,
      );
      expect(halted.pendingActions, isEmpty);
    },
  );

  test('domain and session mismatches fail closed', () {
    final policy = enabledPolicy();
    final wrongDomain = preview(
      target: const ComputerUseTarget(
        applicationId: 'com.example.browser',
        applicationLabel: 'Example Browser',
        domain: 'attacker.example',
        elementRole: 'button',
        elementLabel: 'Open report',
      ),
    );
    expect(
      policy.evaluate(session: activeSession, preview: wrongDomain).reason,
      ComputerUseDecisionReason.domainNotAllowed,
    );
    expect(
      policy
          .evaluate(
            session: activeSession,
            preview: preview(sessionId: 'different-session'),
          )
          .reason,
      ComputerUseDecisionReason.wrongSession,
    );
  });

  test(
    'future enabled policy requires exact element and navigation targets',
    () {
      final policy = enabledPolicy();
      const applicationOnly = ComputerUseTarget(
        applicationId: 'com.example.browser',
        applicationLabel: 'Example Browser',
        domain: 'example.test',
      );
      expect(
        policy
            .evaluate(
              session: activeSession,
              preview: preview(target: applicationOnly),
            )
            .reason,
        ComputerUseDecisionReason.missingVisibleElementTarget,
      );
      final noDomain = ComputerUseActionPreview(
        id: 'action-navigate',
        sessionId: activeSession.id,
        kind: ComputerUseActionKind.navigateUrl,
        target: const ComputerUseTarget(
          applicationId: 'com.example.browser',
          applicationLabel: 'Example Browser',
          elementRole: 'address bar',
          elementLabel: 'Address',
        ),
        summary: 'Navigate the visible browser.',
        createdAt: startedAt,
      );
      expect(
        policy.evaluate(session: activeSession, preview: noDomain).reason,
        ComputerUseDecisionReason.missingDomain,
      );
    },
  );

  test('future enabled policy rejects empty typing and malformed domains', () {
    final policy = enabledPolicy();
    final emptyTyping = ComputerUseActionPreview(
      id: 'action-empty-type',
      sessionId: activeSession.id,
      kind: ComputerUseActionKind.typeText,
      target: safeTarget,
      summary: 'Type the approved value.',
      inputCharacterCount: 0,
      createdAt: startedAt,
    );
    expect(
      policy.evaluate(session: activeSession, preview: emptyTyping).reason,
      ComputerUseDecisionReason.invalidTypedInput,
    );

    final policyWithMalformedDomain = ComputerUseSessionPolicy(
      allowedApplicationIds: {safeTarget.applicationId},
      allowedDomains: {'https://example.test/path', safeTarget.domain!},
    );
    expect(policyWithMalformedDomain.allowedDomains, {safeTarget.domain});
    expect(
      policyWithMalformedDomain.allowsDomain('example.test/path'),
      isFalse,
    );
  });

  test('typed previews never expose model-supplied input text', () {
    final typed = ComputerUseActionPreview(
      id: 'action-type',
      sessionId: activeSession.id,
      kind: ComputerUseActionKind.typeText,
      target: safeTarget,
      summary: 'Type bearer token sk-live-sensitive-value into the field.',
      inputCharacterCount: 29,
      createdAt: startedAt,
    );

    expect(typed.summary, 'Type 29 characters into the selected target.');
    expect(typed.summary, isNot(contains('sk-live-sensitive-value')));
    expect(typed.summary, isNot(contains('bearer token')));
  });

  test('non-typing previews never reflect model-supplied summary text', () {
    final click = ComputerUseActionPreview(
      id: 'action-click-summary',
      sessionId: activeSession.id,
      kind: ComputerUseActionKind.click,
      target: safeTarget,
      summary: 'Click /Users/example/private.txt with Bearer seeded-secret.',
      createdAt: startedAt,
    );

    expect(click.summary, 'Click button "Open report" in Example Browser.');
    expect(click.summary, isNot(contains('seeded-secret')));
    expect(click.summary, isNot(contains('/Users/')));
  });

  test(
    'future enabled policy requires native target inspection and safe details',
    () {
      final policy = enabledPolicy();
      final unverified = preview(
        target: const ComputerUseTarget(
          applicationId: 'com.example.browser',
          applicationLabel: 'Example Browser',
          domain: 'example.test',
          elementRole: 'button',
          elementLabel: 'Open report',
        ),
      );
      expect(
        policy.evaluate(session: activeSession, preview: unverified).reason,
        ComputerUseDecisionReason.targetNotNativeInspection,
      );

      final unsafe = preview(
        target: ComputerUseTarget(
          applicationId: 'com.example.browser',
          applicationLabel: 'Example Browser',
          domain: 'example.test',
          elementRole: 'button',
          elementLabel: List<String>.filled(161, 'x').join(),
          evidence: ComputerUseTargetEvidence.nativeInspection,
        ),
      );
      expect(
        policy.evaluate(session: activeSession, preview: unsafe).reason,
        ComputerUseDecisionReason.unsafePreviewTarget,
      );
      expect(
        unsafe.summary,
        isNot(contains(List<String>.filled(161, 'x').join())),
      );
    },
  );

  test('computer-use sessions retain one bound pending review at a time', () {
    final pending = preview();
    final valid = activeSession.copyWith(pendingActions: [pending]);
    expect(valid.pendingActions, [pending]);

    expect(
      () => activeSession.copyWith(pendingActions: [pending, pending]),
      throwsArgumentError,
    );
    expect(
      () => activeSession.copyWith(
        pendingActions: [preview(sessionId: 'other-session')],
      ),
      throwsArgumentError,
    );
    expect(
      () => ComputerUseSession(
        id: activeSession.id,
        status: ComputerUseSessionStatus.halted,
        isVisible: true,
        policy: activeSession.policy,
        pendingActions: [pending],
        createdAt: startedAt,
        emergencyStoppedAt: startedAt,
      ),
      throwsArgumentError,
    );
  });

  test('sensitive verification and recovery fields remain denied', () {
    final policy = enabledPolicy();
    for (final label in const [
      'MFA verification code',
      'Recovery phrase',
      'Bank routing number',
    ]) {
      final sensitive = preview(
        target: ComputerUseTarget(
          applicationId: safeTarget.applicationId,
          applicationLabel: safeTarget.applicationLabel,
          domain: safeTarget.domain,
          elementRole: 'text field',
          elementLabel: label,
        ),
      );
      expect(
        policy.evaluate(session: activeSession, preview: sensitive).reason,
        ComputerUseDecisionReason.sensitiveField,
        reason: label,
      );
    }
  });

  test('session policy snapshots cannot be broadened after construction', () {
    final mutableApplications = <String>{safeTarget.applicationId};
    final mutableDomains = <String>{safeTarget.domain!};
    final policy = ComputerUseSessionPolicy(
      allowedApplicationIds: mutableApplications,
      allowedDomains: mutableDomains,
    );
    mutableApplications
      ..clear()
      ..add('com.attacker.desktop');
    mutableDomains
      ..clear()
      ..add('attacker.example');
    final session = activeSession.copyWith(policy: policy);

    expect(
      enabledPolicy()
          .evaluate(session: session, preview: preview())
          .requiresUserReview,
      isTrue,
    );
    expect(policy.allowedApplicationIds, {safeTarget.applicationId});
    expect(policy.allowedDomains, {safeTarget.domain});
  });

  test('missing session or action identities fail closed', () {
    final policy = enabledPolicy();
    final missingSession = ComputerUseSession(
      id: '',
      status: ComputerUseSessionStatus.active,
      isVisible: true,
      createdAt: startedAt,
      policy: ComputerUseSessionPolicy(
        allowedApplicationIds: {safeTarget.applicationId},
        allowedDomains: {safeTarget.domain!},
      ),
    );
    expect(
      policy.evaluate(session: missingSession, preview: preview()).reason,
      ComputerUseDecisionReason.missingSessionIdentity,
    );
    final missingAction = ComputerUseActionPreview(
      id: '',
      sessionId: activeSession.id,
      kind: ComputerUseActionKind.click,
      target: safeTarget,
      summary: 'Select the visible Open report button.',
      createdAt: startedAt,
    );
    expect(
      policy.evaluate(session: activeSession, preview: missingAction).reason,
      ComputerUseDecisionReason.missingActionIdentity,
    );
  });

  test('future enabled policy rejects stale or future-dated previews', () {
    final reviewTime = startedAt.add(const Duration(minutes: 2));
    final policy = enabledPolicy(now: reviewTime);

    expect(
      policy
          .evaluate(session: activeSession, preview: preview())
          .requiresUserReview,
      isTrue,
    );
    expect(
      policy
          .evaluate(
            session: activeSession,
            preview: preview(
              createdAt: reviewTime.subtract(
                const Duration(minutes: 2, seconds: 1),
              ),
            ),
          )
          .reason,
      ComputerUseDecisionReason.actionPreviewExpired,
    );
    expect(
      policy
          .evaluate(
            session: activeSession,
            preview: preview(
              createdAt: reviewTime.add(const Duration(seconds: 1)),
            ),
          )
          .reason,
      ComputerUseDecisionReason.actionPreviewExpired,
    );
  });
}
