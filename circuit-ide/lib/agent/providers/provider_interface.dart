import '../../models/chat_message.dart';
import '../../models/agent_workspace.dart';
import '../../models/provider_lifecycle_event.dart';

/// Wire contract shared by CircuitCode and model-provider adapters.
///
/// New optional fields must be added behind a newer protocol version; callers
/// never guess whether an endpoint understands a changed payload shape.
class ProviderProtocol {
  static const currentVersion = 1;
  static const minimumCompatibleVersion = 1;

  final int version;
  final int minimumCompatible;

  const ProviderProtocol({
    this.version = currentVersion,
    this.minimumCompatible = minimumCompatibleVersion,
  });

  Map<String, dynamic> toRequestJson() => {
    'version': version,
    'minimumCompatible': minimumCompatible,
  };

  /// Treat endpoints that predate the acknowledgement header as protocol 1.
  /// Once an endpoint does send the header, an incompatible or malformed
  /// acknowledgement is a hard, actionable failure rather than a best guess.
  int negotiateResponseVersion(String? responseHeader) {
    if (responseHeader == null) return minimumCompatible;
    final raw = responseHeader.trim();
    if (raw.isEmpty) {
      throw const ProviderProtocolCompatibilityException(
        'Circuit provider returned an empty protocol acknowledgement. Update the provider or contact your administrator.',
      );
    }
    final serverVersion = int.tryParse(raw);
    if (serverVersion == null) {
      throw const ProviderProtocolCompatibilityException(
        'Circuit provider returned an invalid protocol acknowledgement. Update the provider or contact your administrator.',
      );
    }
    if (serverVersion < minimumCompatible || serverVersion > version) {
      throw ProviderProtocolCompatibilityException(
        'Circuit provider protocol $serverVersion is incompatible with this app (supported $minimumCompatible-$version). Update CircuitCode or the provider, then retry.',
      );
    }
    return serverVersion;
  }
}

class ProviderProtocolCompatibilityException implements Exception {
  final String message;

  const ProviderProtocolCompatibilityException(this.message);

  @override
  String toString() => message;
}

/// A typed, locally-created lifecycle failure whose message has already been
/// selected from CircuitCode's fixed diagnostic vocabulary. Streaming code uses
/// this instead of a generic [Exception] so an outer transport boundary can
/// preserve known-safe state without ever reflecting an arbitrary provider or
/// socket exception.
class ProviderLifecycleException implements Exception {
  final String message;

  const ProviderLifecycleException(this.message);

  @override
  String toString() => message;
}

enum ProviderTokenSemantics {
  aggregateOnly,
  inputAndOutput,
  inputCachedOutputReasoningTool,
}

class ModelInfo {
  final String id;
  final String displayName;
  final int contextWindow;
  final double inputCostPer1k;
  final double outputCostPer1k;
  final bool supportsTools;
  final bool supportsImageInput;
  final bool supportsJsonSchema;
  final bool supportsReasoning;
  final ProviderTokenSemantics tokenSemantics;

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.contextWindow,
    this.inputCostPer1k = 0,
    this.outputCostPer1k = 0,
    this.supportsTools = true,
    this.supportsImageInput = false,
    this.supportsJsonSchema = false,
    this.supportsReasoning = false,
    this.tokenSemantics = ProviderTokenSemantics.inputAndOutput,
  });
}

ProviderCapabilities capabilitiesForSelectedModel(
  ProviderCapabilities provider,
  ModelInfo? model,
) => ProviderCapabilities(
  supportsStreaming: provider.supportsStreaming,
  supportsNativeToolCalls:
      provider.supportsNativeToolCalls && (model?.supportsTools ?? false),
  supportsModelRefresh: provider.supportsModelRefresh,
  supportsCancellation: provider.supportsCancellation,
  supportsImageInput:
      provider.supportsImageInput && (model?.supportsImageInput ?? false),
  supportsJsonSchema:
      provider.supportsJsonSchema && (model?.supportsJsonSchema ?? false),
  supportsReasoning:
      provider.supportsReasoning && (model?.supportsReasoning ?? false),
  supportedImageMimeTypes: provider.supportedImageMimeTypes,
  maxImageBytes: provider.maxImageBytes,
  maxImageDimension: provider.maxImageDimension,
  tokenSemantics: model?.tokenSemantics ?? ProviderTokenSemantics.aggregateOnly,
);

enum ConnectorHealthStatus {
  unknown,
  credentialsMissing,
  connecting,
  connected,
  degraded,
  tokenFailed,
  modelUnavailable,
  requestFailed,
}

/// A support-safe category for the most recent connector health failure.
///
/// This deliberately excludes raw transport text, request bodies, and
/// credentials so it can be retained and included in a redacted support
/// bundle.
enum ConnectorHealthErrorCategory {
  none,
  credentials,
  authentication,
  offline,
  timeout,
  rateLimited,
  server,
  malformedResponse,
  certificate,
  unknown,
}

class ProviderCapabilities {
  final bool supportsStreaming;
  final bool supportsNativeToolCalls;
  final bool supportsModelRefresh;
  final bool supportsCancellation;
  final bool supportsImageInput;
  final bool supportsJsonSchema;
  final bool supportsReasoning;
  final Set<String> supportedImageMimeTypes;
  final int maxImageBytes;
  final int maxImageDimension;
  final ProviderTokenSemantics tokenSemantics;

  const ProviderCapabilities({
    this.supportsStreaming = true,
    this.supportsNativeToolCalls = true,
    this.supportsModelRefresh = true,
    this.supportsCancellation = true,
    this.supportsImageInput = false,
    this.supportsJsonSchema = false,
    this.supportsReasoning = false,
    this.supportedImageMimeTypes = const {},
    this.maxImageBytes = 0,
    this.maxImageDimension = 0,
    this.tokenSemantics = ProviderTokenSemantics.aggregateOnly,
  });
}

class ProviderDescriptor {
  final String id;
  final String displayName;
  final String shortName;
  final ProviderCapabilities capabilities;
  final ProviderProtocol protocol;

  const ProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.shortName,
    this.capabilities = const ProviderCapabilities(),
    this.protocol = const ProviderProtocol(),
  });
}

class ConnectorModelInfo {
  final String id;
  final String displayName;
  final int contextWindow;
  final bool supportsTools;
  final bool supportsImageInput;
  final bool supportsJsonSchema;
  final bool supportsReasoning;
  final ProviderTokenSemantics tokenSemantics;
  final double inputCostPer1k;
  final double outputCostPer1k;

  const ConnectorModelInfo({
    required this.id,
    required this.displayName,
    this.contextWindow = 120000,
    this.supportsTools = true,
    this.supportsImageInput = false,
    this.supportsJsonSchema = false,
    this.supportsReasoning = false,
    this.tokenSemantics = ProviderTokenSemantics.inputAndOutput,
    this.inputCostPer1k = 0,
    this.outputCostPer1k = 0,
  });

  ModelInfo toModelInfo() => ModelInfo(
    id: id,
    displayName: displayName,
    contextWindow: contextWindow,
    supportsTools: supportsTools,
    supportsImageInput: supportsImageInput,
    supportsJsonSchema: supportsJsonSchema,
    supportsReasoning: supportsReasoning,
    tokenSemantics: tokenSemantics,
    inputCostPer1k: inputCostPer1k,
    outputCostPer1k: outputCostPer1k,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'contextWindow': contextWindow,
    'supportsTools': supportsTools,
    'supportsImageInput': supportsImageInput,
    'supportsJsonSchema': supportsJsonSchema,
    'supportsReasoning': supportsReasoning,
    'tokenSemantics': tokenSemantics.name,
    'inputCostPer1k': inputCostPer1k,
    'outputCostPer1k': outputCostPer1k,
  };

  static ConnectorModelInfo? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.trim().isEmpty) return null;
    return ConnectorModelInfo(
      id: id,
      displayName: json['displayName'] as String? ?? id,
      contextWindow: json['contextWindow'] as int? ?? 120000,
      supportsTools: json['supportsTools'] as bool? ?? true,
      supportsImageInput: json['supportsImageInput'] as bool? ?? false,
      supportsJsonSchema: json['supportsJsonSchema'] as bool? ?? false,
      supportsReasoning: json['supportsReasoning'] as bool? ?? false,
      tokenSemantics: ProviderTokenSemantics.values.firstWhere(
        (value) => value.name == json['tokenSemantics'],
        orElse: () => ProviderTokenSemantics.inputAndOutput,
      ),
      inputCostPer1k: (json['inputCostPer1k'] as num?)?.toDouble() ?? 0,
      outputCostPer1k: (json['outputCostPer1k'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ConnectorHealth {
  final ConnectorHealthStatus status;
  final String message;
  final DateTime checkedAt;
  final String endpoint;
  final int protocolVersion;
  final Duration? latency;
  final ConnectorHealthErrorCategory errorCategory;
  final String retryAdvice;

  const ConnectorHealth({
    required this.status,
    required this.message,
    required this.checkedAt,
    this.endpoint = '',
    this.protocolVersion = 0,
    this.latency,
    this.errorCategory = ConnectorHealthErrorCategory.none,
    this.retryAdvice = '',
  });
}

enum ProviderStreamEventType { textDelta, toolCallDelta, usage, done, error }

class ProviderRequestError {
  final String message;
  final int? statusCode;
  final String? requestId;
  final String? modelId;
  final bool retryable;
  final String? rawSnippet;

  const ProviderRequestError({
    required this.message,
    this.statusCode,
    this.requestId,
    this.modelId,
    this.retryable = false,
    this.rawSnippet,
  });
}

class ProviderStreamEvent {
  final ProviderStreamEventType type;
  final String? textDelta;
  final ChatChunk? toolCallDelta;
  final int promptTokens;
  final int cachedInputTokens;
  final int completionTokens;
  final int reasoningTokens;
  final int toolTokens;
  final ProviderRequestError? error;

  const ProviderStreamEvent({
    required this.type,
    this.textDelta,
    this.toolCallDelta,
    this.promptTokens = 0,
    this.cachedInputTokens = 0,
    this.completionTokens = 0,
    this.reasoningTokens = 0,
    this.toolTokens = 0,
    this.error,
  });
}

class ProviderRequestHandle {
  bool _cancelRequested = false;

  bool get cancelRequested => _cancelRequested;

  void cancel() {
    _cancelRequested = true;
  }
}

class ChatChunk {
  final String? content;
  final String? toolCallId;
  final String? toolCallName;
  final String? toolCallArguments;
  final int? toolCallIndex;
  final int promptTokens;
  final int cachedInputTokens;
  final int completionTokens;
  final int reasoningTokens;
  final int toolTokens;
  final String? finishReason;
  final bool isDone;
  final ProviderLifecycleEventKind? lifecycleKind;
  final String? lifecycleDetail;

  const ChatChunk({
    this.content,
    this.toolCallId,
    this.toolCallName,
    this.toolCallArguments,
    this.toolCallIndex,
    this.promptTokens = 0,
    this.cachedInputTokens = 0,
    this.completionTokens = 0,
    this.reasoningTokens = 0,
    this.toolTokens = 0,
    this.finishReason,
    this.isDone = false,
    this.lifecycleKind,
    this.lifecycleDetail,
  });
}

/// A validated image payload. Pixels stay request-local and are never written
/// to Studio history, task titles, or diagnostic records.
class ProviderImageInput {
  final String id;
  final String label;
  final String mimeType;
  final String base64Data;
  final int byteLength;
  final int? width;
  final int? height;
  final int estimatedTokens;
  final bool wasResized;

  const ProviderImageInput({
    required this.id,
    required this.label,
    required this.mimeType,
    required this.base64Data,
    required this.byteLength,
    this.width,
    this.height,
    required this.estimatedTokens,
    this.wasResized = false,
  });

  Map<String, dynamic> toOpenAiContentPart() => {
    'type': 'image_url',
    'image_url': {'url': 'data:$mimeType;base64,$base64Data', 'detail': 'auto'},
  };
}

class ProviderChatRequest {
  final List<ChatMessage> messages;
  final String model;
  final List<ToolDefinition> tools;
  final String? systemPrompt;
  final double temperature;
  final int maxTokens;
  final List<ProviderImageInput> images;
  final bool reasoningEnabled;

  /// Request-local policy for the configured model connector. This is never
  /// serialized into the provider payload or retained in transcript history.
  final ProviderConnectorNetworkPolicy connectorNetworkPolicy;

  const ProviderChatRequest({
    required this.messages,
    required this.model,
    required this.tools,
    this.systemPrompt,
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.images = const [],
    this.reasoningEnabled = false,
    this.connectorNetworkPolicy = ProviderConnectorNetworkPolicy.unrestricted,
  });
}

enum ProviderConnectorNetworkDecision { allow, ask, deny }

/// An exact transport operation a configured provider must perform to serve a
/// Studio turn. It deliberately names an origin instead of accepting a model
/// supplied URL, so approval never grants arbitrary outbound destinations.
class ProviderConnectorNetworkRequirement {
  final String url;
  final String label;
  final String method;
  final bool usesWorkspaceUpload;
  final bool usesCredentials;
  final bool followsRedirects;

  const ProviderConnectorNetworkRequirement({
    required this.url,
    required this.label,
    this.method = 'POST',
    this.usesWorkspaceUpload = false,
    this.usesCredentials = false,
    this.followsRedirects = false,
  });

  Uri? get uri => Uri.tryParse(url);

  String? get approvalKey {
    final parsed = uri;
    final host = WorkspaceNetworkRule.normalizePublicDomain(parsed?.host ?? '');
    if (parsed == null ||
        parsed.scheme.toLowerCase() != 'https' ||
        host == null) {
      return null;
    }
    final port = parsed.hasPort && parsed.port != 443 ? ':${parsed.port}' : '';
    return 'https://$host$port';
  }
}

/// A policy result that the runtime can surface before a connector opens a
/// network socket. [ask] is intentionally resumable only for this request.
class ProviderConnectorNetworkAccess {
  final ProviderConnectorNetworkDecision decision;
  final String message;
  final String? approvalKey;

  const ProviderConnectorNetworkAccess({
    required this.decision,
    required this.message,
    this.approvalKey,
  });
}

/// Provider adapters opt in to connector policy preflight by declaring their
/// fixed OAuth/model origins and transport requirements.
abstract interface class ProviderConnectorNetworkPolicyAware {
  List<ProviderConnectorNetworkRequirement> get connectorNetworkRequirements;
}

/// Immutable snapshot of the active workspace policy for a configured model
/// connector. It prevents one concurrent Studio turn from mutating another
/// turn's outbound network authority.
class ProviderConnectorNetworkPolicy {
  final WorkspacePermissionDisposition networkDisposition;
  final List<WorkspaceNetworkRule> networkRules;
  final Set<String> approvedConnectorOrigins;

  static const unrestricted = ProviderConnectorNetworkPolicy();

  const ProviderConnectorNetworkPolicy({
    this.networkDisposition = WorkspacePermissionDisposition.review,
    this.networkRules = const [],
    this.approvedConnectorOrigins = const {},
  });

  /// Captures mutable persisted preferences before a Studio turn starts.
  /// Runtime callers use this so one request cannot alter another request's
  /// outbound connector authority.
  factory ProviderConnectorNetworkPolicy.snapshot({
    WorkspacePermissionDisposition networkDisposition =
        WorkspacePermissionDisposition.review,
    List<WorkspaceNetworkRule> networkRules = const [],
    Iterable<String> approvedConnectorOrigins = const [],
  }) => ProviderConnectorNetworkPolicy(
    networkDisposition: networkDisposition,
    networkRules: List.unmodifiable(networkRules),
    approvedConnectorOrigins: Set.unmodifiable(approvedConnectorOrigins),
  );

  /// Returns a new request-local snapshot after a user approves the exact
  /// configured origins that were presented in Studio's review surface.
  ProviderConnectorNetworkPolicy approveConnectorOrigins(
    Iterable<String> origins,
  ) => ProviderConnectorNetworkPolicy.snapshot(
    networkDisposition: networkDisposition,
    networkRules: networkRules,
    approvedConnectorOrigins: {...approvedConnectorOrigins, ...origins},
  );

  ProviderConnectorNetworkAccess evaluate(
    ProviderConnectorNetworkRequirement requirement,
  ) {
    // The legacy convenience API has no workspace context. Preserve its
    // transport behavior (including local HTTP test adapters) until a Studio
    // turn supplies an actual policy snapshot.
    if (networkDisposition != WorkspacePermissionDisposition.block &&
        networkRules.isEmpty) {
      return const ProviderConnectorNetworkAccess(
        decision: ProviderConnectorNetworkDecision.allow,
        message: 'No project connector policy applies to this request.',
      );
    }
    final parsed = requirement.uri;
    final host = WorkspaceNetworkRule.normalizePublicDomain(parsed?.host ?? '');
    final approvalKey = requirement.approvalKey;
    if (parsed == null ||
        parsed.scheme.toLowerCase() != 'https' ||
        host == null ||
        approvalKey == null) {
      return ProviderConnectorNetworkAccess(
        decision: ProviderConnectorNetworkDecision.deny,
        message: '${requirement.label} has an invalid configured HTTPS origin.',
      );
    }
    final matches = networkRules
        .where((rule) => _ruleMatchesHost(rule, host))
        .toList(growable: false);
    if (matches.any(
      (rule) => rule.disposition == WorkspaceNetworkRuleDisposition.deny,
    )) {
      return ProviderConnectorNetworkAccess(
        decision: ProviderConnectorNetworkDecision.deny,
        message:
            'Project network policy denies the ${requirement.label} origin $host.',
        approvalKey: approvalKey,
      );
    }
    final rule = matches.isEmpty
        ? null
        : (matches.toList()..sort(
                (left, right) =>
                    right.domain.length.compareTo(left.domain.length),
              ))
              .first;
    if (rule != null) {
      final method = requirement.method.trim().toUpperCase();
      if (!rule.methods.map((value) => value.toUpperCase()).contains(method)) {
        return _deniedOperation(
          requirement,
          host,
          approvalKey,
          '$method requests',
        );
      }
      if (requirement.usesWorkspaceUpload && !rule.allowUpload) {
        return _deniedOperation(
          requirement,
          host,
          approvalKey,
          'workspace uploads',
        );
      }
      if (requirement.usesCredentials && !rule.allowCredentials) {
        return _deniedOperation(
          requirement,
          host,
          approvalKey,
          'credential use',
        );
      }
      if (requirement.followsRedirects && !rule.allowRedirects) {
        return _deniedOperation(requirement, host, approvalKey, 'redirects');
      }
      if (rule.disposition == WorkspaceNetworkRuleDisposition.allow) {
        return ProviderConnectorNetworkAccess(
          decision: ProviderConnectorNetworkDecision.allow,
          message: 'Project network policy allows ${requirement.label}.',
          approvalKey: approvalKey,
        );
      }
      if (approvedConnectorOrigins.contains(approvalKey)) {
        return ProviderConnectorNetworkAccess(
          decision: ProviderConnectorNetworkDecision.allow,
          message: 'Turn approval allows ${requirement.label}.',
          approvalKey: approvalKey,
        );
      }
      return ProviderConnectorNetworkAccess(
        decision: ProviderConnectorNetworkDecision.ask,
        message:
            'Project network policy requires review for ${requirement.label} origin $host.',
        approvalKey: approvalKey,
      );
    }
    if (networkDisposition == WorkspacePermissionDisposition.block) {
      return ProviderConnectorNetworkAccess(
        decision: ProviderConnectorNetworkDecision.deny,
        message:
            'Project network policy blocks the ${requirement.label} origin $host. Add a matching allow or Require review rule before sending this turn.',
        approvalKey: approvalKey,
      );
    }
    return ProviderConnectorNetworkAccess(
      decision: ProviderConnectorNetworkDecision.allow,
      message: 'Project network policy allows ${requirement.label}.',
      approvalKey: approvalKey,
    );
  }

  ProviderConnectorNetworkAccess _deniedOperation(
    ProviderConnectorNetworkRequirement requirement,
    String host,
    String approvalKey,
    String operation,
  ) => ProviderConnectorNetworkAccess(
    decision: ProviderConnectorNetworkDecision.deny,
    message:
        'Project network policy denies $operation for ${requirement.label} origin $host.',
    approvalKey: approvalKey,
  );

  bool _ruleMatchesHost(WorkspaceNetworkRule rule, String host) {
    final pattern = WorkspaceNetworkRule.normalizePublicDomain(rule.domain);
    if (pattern == null) return false;
    return pattern == host ||
        (pattern.startsWith('*.') &&
            host.endsWith(pattern.substring(1)) &&
            host.length > pattern.length - 1);
  }
}

class ProviderConnectorNetworkPolicyException implements Exception {
  final String message;

  const ProviderConnectorNetworkPolicyException(this.message);

  @override
  String toString() => message;
}

class ProviderCapabilityException implements Exception {
  final String message;

  const ProviderCapabilityException(this.message);

  @override
  String toString() => message;
}

class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toOpenAIFormat() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

// ADR-0004: provider-specific data crosses this typed adapter boundary.
abstract class AIProvider {
  String get name;
  List<ModelInfo> get availableModels;
  ProviderDescriptor get descriptor;
  ProviderCapabilities get capabilities => descriptor.capabilities;
  bool get isConnected;

  Future<void> connect(Map<String, String> credentials);
  void disconnect();
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: isConnected
        ? ConnectorHealthStatus.connected
        : ConnectorHealthStatus.unknown,
    message: isConnected ? 'Connected' : 'Not connected',
    checkedAt: DateTime.now(),
  );

  Future<List<ConnectorModelInfo>> refreshModels() async {
    return availableModels
        .map(
          (model) => ConnectorModelInfo(
            id: model.id,
            displayName: model.displayName,
            contextWindow: model.contextWindow,
            supportsTools: model.supportsTools,
            supportsImageInput: model.supportsImageInput,
            supportsJsonSchema: model.supportsJsonSchema,
            supportsReasoning: model.supportsReasoning,
            tokenSemantics: model.tokenSemantics,
            inputCostPer1k: model.inputCostPer1k,
            outputCostPer1k: model.outputCostPer1k,
          ),
        )
        .toList();
  }

  void cancelActiveRequest() {}

  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  });
}

/// Optional adapter capability. Keeping this outside [AIProvider] preserves
/// compatibility for existing text-only provider implementations and fakes.
abstract interface class ImageCapableProvider {
  Stream<ChatChunk> chatWithRequest(ProviderChatRequest request);
}
