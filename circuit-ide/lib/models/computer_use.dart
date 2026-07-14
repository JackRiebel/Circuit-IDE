/// The computer-use contract is intentionally separate from Studio turns and
/// browser previews. It contains only user-visible proposals; no desktop
/// automation backend is enabled or exposed to a model.
enum ComputerUseSessionStatus { idle, active, halted, ended }

enum ComputerUseActionKind {
  pointerMove,
  click,
  typeText,
  keyPress,
  launchApplication,
  navigateUrl,
}

/// A future executor must distinguish a target observed in its own visible
/// native session from an untrusted model proposal. A model may suggest an
/// action, but it cannot make its own target eligible for confirmation.
enum ComputerUseTargetEvidence { unverifiedProposal, nativeInspection }

class ComputerUseTarget {
  final String applicationId;
  final String applicationLabel;
  final String? domain;
  final String elementRole;
  final String elementLabel;
  final ComputerUseTargetEvidence evidence;

  const ComputerUseTarget({
    required this.applicationId,
    required this.applicationLabel,
    this.domain,
    this.elementRole = '',
    this.elementLabel = '',
    this.evidence = ComputerUseTargetEvidence.unverifiedProposal,
  });

  bool get hasVisibleTarget =>
      applicationId.trim().isNotEmpty && applicationLabel.trim().isNotEmpty;

  /// Pointer, key, typing, and navigation proposals need an exact visible
  /// element as well as an application. A future worker must not receive an
  /// ambiguous "click somewhere in this app" review result.
  bool get hasVisibleElementTarget =>
      elementRole.trim().isNotEmpty && elementLabel.trim().isNotEmpty;

  bool get hasNativeInspection =>
      evidence == ComputerUseTargetEvidence.nativeInspection;

  /// Visible target details must be bounded and free of credential/path-shaped
  /// strings before a future preview can be reviewed. The display getters
  /// below are the only safe way a future UI should render this model-owned
  /// proposal; the raw fields remain available solely for a future isolated
  /// native worker to compare against its own inspected element.
  bool get hasSafeDisplayDetails => [
    applicationLabel,
    elementRole,
    elementLabel,
    ?domain,
  ].every(_isSafeDisplayText);

  String get displayApplicationLabel =>
      _safeDisplayText(applicationLabel, fallback: 'selected application');

  String get displayElementRole =>
      _safeDisplayText(elementRole, fallback: 'selected control');

  String get displayElementLabel =>
      _safeDisplayText(elementLabel, fallback: 'redacted target');

  String? get displayDomain =>
      domain == null || !_isSafeDisplayText(domain!) ? null : domain!.trim();

  bool get isSensitiveField {
    final combined = '$elementRole $elementLabel'.toLowerCase();
    return const [
      'password',
      'passcode',
      'one-time code',
      'otp',
      'mfa',
      '2fa',
      'verification code',
      'security code',
      'credit card',
      'card number',
      'cvv',
      'cvc',
      'social security',
      'ssn',
      'secret',
      'api key',
      'api-key',
      'access token',
      'bearer token',
      'auth token',
      'private key',
      'seed phrase',
      'recovery phrase',
      'bank account',
      'account number',
      'routing number',
    ].any(combined.contains);
  }

  static bool _isSafeDisplayText(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty || normalized.length > 160) return false;
    final lower = normalized.toLowerCase();
    return !RegExp(r'[\x00-\x1f\x7f]').hasMatch(normalized) &&
        !RegExp(
          r'(^|\s)(token|api[_-]?key|client[_-]?secret|password)\s*[=:]',
        ).hasMatch(lower) &&
        !RegExp(r'\bbearer\s+\S+').hasMatch(lower) &&
        !RegExp(r'(^|[^a-z])/(users|private|tmp|var|home)/').hasMatch(lower) &&
        !RegExp(r'^[a-z]:\\', caseSensitive: false).hasMatch(normalized);
  }

  static String _safeDisplayText(String value, {required String fallback}) {
    if (!_isSafeDisplayText(value)) return fallback;
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// A display-safe action proposal. Typed values and screen pixels do not
/// belong in this contract; a future backend must obtain any value directly
/// from an explicit user interaction after approval.
class ComputerUseActionPreview {
  final String id;
  final String sessionId;
  final ComputerUseActionKind kind;
  final ComputerUseTarget target;
  final String summary;
  final int inputCharacterCount;
  final DateTime createdAt;

  ComputerUseActionPreview({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.target,
    required String summary,
    this.inputCharacterCount = 0,
    required this.createdAt,
  }) : summary = _displaySafeSummary(
         kind: kind,
         target: target,
         inputCharacterCount: inputCharacterCount,
       );

  bool get requiresUserConfirmation => true;

  /// A typing proposal must never reveal the text it will enter. A future
  /// worker receives a separately protected input payload only after this
  /// review contract succeeds; the UI/model-facing preview gets a count.
  static String _displaySafeSummary({
    required ComputerUseActionKind kind,
    required ComputerUseTarget target,
    required int inputCharacterCount,
  }) {
    if (kind == ComputerUseActionKind.typeText) {
      final count = inputCharacterCount < 0 ? 0 : inputCharacterCount;
      if (count == 1) return 'Type 1 character into the selected target.';
      if (count > 1) {
        return 'Type $count characters into the selected target.';
      }
      return 'Type text into the selected target.';
    }
    final targetDescription = target.hasVisibleElementTarget
        ? '${target.displayElementRole} "${target.displayElementLabel}"'
        : 'the selected target';
    switch (kind) {
      case ComputerUseActionKind.pointerMove:
        return 'Move the pointer to $targetDescription in ${target.displayApplicationLabel}.';
      case ComputerUseActionKind.click:
        return 'Click $targetDescription in ${target.displayApplicationLabel}.';
      case ComputerUseActionKind.keyPress:
        return 'Press a reviewed key at $targetDescription in ${target.displayApplicationLabel}.';
      case ComputerUseActionKind.launchApplication:
        return 'Open ${target.displayApplicationLabel}.';
      case ComputerUseActionKind.navigateUrl:
        return 'Navigate ${target.displayApplicationLabel} to ${target.displayDomain ?? 'the approved site'}.';
      case ComputerUseActionKind.typeText:
        throw StateError(
          'Typing previews are handled before generic summaries.',
        );
    }
  }
}

/// Allowlisting is exact and only meaningful inside a visible, separate
/// computer-use session. Empty allowlists deny all targets.
class ComputerUseSessionPolicy {
  final Set<String> allowedApplicationIds;
  final Set<String> allowedDomains;

  ComputerUseSessionPolicy({
    Set<String> allowedApplicationIds = const {},
    Set<String> allowedDomains = const {},
  }) : allowedApplicationIds = Set.unmodifiable(
         _normalizedValues(allowedApplicationIds),
       ),
       allowedDomains = Set.unmodifiable(_normalizedDomains(allowedDomains));

  bool allowsApplication(String applicationId) =>
      allowedApplicationIds.contains(_normalizedValue(applicationId));

  bool allowsDomain(String? domain) {
    final normalized = _normalizedDomain(domain ?? '');
    if (normalized == null) return false;
    if (normalized.isEmpty) return true;
    return allowedDomains.contains(normalized);
  }

  static Set<String> _normalizedValues(Iterable<String> values) =>
      values.map(_normalizedValue).where((value) => value.isNotEmpty).toSet();

  static Set<String> _normalizedDomains(Iterable<String> values) => values
      .map(_normalizedDomain)
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet();

  /// Accept host names only. URLs, paths, ports, credentials, wildcard
  /// patterns, and malformed labels cannot turn into an allowlist entry.
  static String? _normalizedDomain(String value) {
    final normalized = _normalizedValue(value);
    if (normalized.isEmpty) return '';
    if (normalized.length > 253) return null;
    final labels = normalized.split('.');
    if (labels.length < 2 || labels.any((label) => label.isEmpty)) return null;
    final labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
    if (labels.any((label) => !labelPattern.hasMatch(label))) return null;
    return normalized;
  }

  static String _normalizedValue(String value) => value.trim().toLowerCase();
}

class ComputerUseSession {
  static const maxPendingActionPreviews = 1;

  final String id;
  final ComputerUseSessionStatus status;
  final bool isVisible;
  final ComputerUseSessionPolicy policy;
  final List<ComputerUseActionPreview> pendingActions;
  final DateTime createdAt;
  final DateTime? emergencyStoppedAt;

  ComputerUseSession({
    required this.id,
    this.status = ComputerUseSessionStatus.idle,
    this.isVisible = false,
    ComputerUseSessionPolicy? policy,
    List<ComputerUseActionPreview> pendingActions = const [],
    required this.createdAt,
    this.emergencyStoppedAt,
  }) : policy = policy ?? ComputerUseSessionPolicy(),
       pendingActions = List.unmodifiable(pendingActions) {
    if (pendingActions.length > maxPendingActionPreviews) {
      throw ArgumentError.value(
        pendingActions.length,
        'pendingActions',
        'Computer-use sessions allow one reviewed pending action at a time.',
      );
    }
    if ((status == ComputerUseSessionStatus.halted ||
            emergencyStoppedAt != null) &&
        pendingActions.isNotEmpty) {
      throw ArgumentError.value(
        pendingActions,
        'pendingActions',
        'A halted computer-use session cannot retain pending actions.',
      );
    }
    if (pendingActions.any(
      (preview) =>
          preview.sessionId.trim().isEmpty ||
          preview.sessionId != id ||
          preview.id.trim().isEmpty,
    )) {
      throw ArgumentError.value(
        pendingActions,
        'pendingActions',
        'Pending actions must have unique non-empty IDs bound to this session.',
      );
    }
    if (pendingActions.map((preview) => preview.id).toSet().length !=
        pendingActions.length) {
      throw ArgumentError.value(
        pendingActions,
        'pendingActions',
        'Pending computer-use action IDs must be unique.',
      );
    }
  }

  bool get hasEmergencyStop =>
      status == ComputerUseSessionStatus.halted || emergencyStoppedAt != null;

  ComputerUseSession copyWith({
    ComputerUseSessionStatus? status,
    bool? isVisible,
    ComputerUseSessionPolicy? policy,
    List<ComputerUseActionPreview>? pendingActions,
    DateTime? emergencyStoppedAt,
  }) {
    return ComputerUseSession(
      id: id,
      status: status ?? this.status,
      isVisible: isVisible ?? this.isVisible,
      policy: policy ?? this.policy,
      pendingActions: pendingActions ?? this.pendingActions,
      createdAt: createdAt,
      emergencyStoppedAt: emergencyStoppedAt ?? this.emergencyStoppedAt,
    );
  }

  ComputerUseSession emergencyStop(DateTime at) => copyWith(
    status: ComputerUseSessionStatus.halted,
    pendingActions: const [],
    emergencyStoppedAt: at,
  );
}
