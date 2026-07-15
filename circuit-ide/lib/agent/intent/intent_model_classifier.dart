import 'dart:async';
import 'dart:convert';

import '../../enums/message_role.dart';
import '../../models/chat_message.dart';
import '../../models/turn_intent.dart';
import '../providers/provider_interface.dart';

/// Resolves only the intentionally ambiguous remainder of intent routing.
///
/// The classifier has a narrow typed output contract and never receives
/// workspace context, conversation history, images, or tools. Deterministic
/// routing still owns every known safety boundary; unavailable, malformed, or
/// low-confidence model output remains Ask.
class IntentModelClassifier {
  const IntentModelClassifier();

  Future<IntentRoutingDecision> resolve({
    required IntentRoutingDecision deterministicDecision,
    required String prompt,
    required AIProvider? provider,
    required String model,
  }) async {
    if (!deterministicDecision.requiresModelClassifier) {
      return deterministicDecision;
    }
    if (provider == null || !provider.isConnected || model.trim().isEmpty) {
      return deterministicDecision.safeFallback(
        'Intent was ambiguous and the low-confidence classifier is unavailable; continuing as Ask.',
      );
    }

    final modelDecision = await classify(
      prompt: prompt,
      provider: provider,
      model: model,
    );
    if (modelDecision == null) {
      return deterministicDecision.safeFallback(
        'Intent was ambiguous and the classifier did not return valid typed output; continuing as Ask.',
      );
    }
    if (modelDecision.confidence < IntentClassifier.minimumModelConfidence) {
      return deterministicDecision.safeFallback(
        'Intent classifier reported ${_percent(modelDecision.confidence)} confidence, below the ${_percent(IntentClassifier.minimumModelConfidence)} routing threshold; continuing as Ask.',
      );
    }
    return deterministicDecision.resolvedByModel(
      intent: modelDecision.intent,
      confidence: modelDecision.confidence,
      reason: modelDecision.reason,
    );
  }

  Future<IntentModelClassification?> classify({
    required String prompt,
    required AIProvider provider,
    required String model,
  }) async {
    final response = StringBuffer();
    try {
      await provider
          .chat(
            [
              ChatMessage(
                id: 'intent-routing-request',
                role: MessageRole.user,
                content: prompt,
                timestamp: DateTime.now(),
              ),
            ],
            model: model,
            tools: const [],
            systemPrompt: _systemPrompt,
            temperature: 0,
            maxTokens: 160,
          )
          .forEach((chunk) {
            if (chunk.content != null) response.write(chunk.content);
          })
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
    return parse(response.toString());
  }

  /// Parses the exact schema above, including common fenced JSON wrapping.
  /// Invalid fields and extra keys are rejected instead of guessed.
  static IntentModelClassification? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(trimmed.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return null;
      const expectedKeys = {'intent', 'confidence', 'reason'};
      if (decoded.keys.length != expectedKeys.length ||
          !decoded.keys.toSet().containsAll(expectedKeys)) {
        return null;
      }
      final rawIntent = decoded['intent'];
      final rawConfidence = decoded['confidence'];
      final rawReason = decoded['reason'];
      if (rawIntent is! String ||
          rawConfidence is! num ||
          rawReason is! String ||
          rawReason.trim().isEmpty ||
          rawReason.trim().length > 240) {
        return null;
      }
      final intent = TurnIntent.values.where(
        (candidate) => candidate.name == rawIntent,
      );
      final confidence = rawConfidence.toDouble();
      if (intent.isEmpty || confidence < 0 || confidence > 1) return null;
      return IntentModelClassification(
        intent: intent.first,
        confidence: confidence,
        reason: rawReason.trim().replaceAll(RegExp(r'\s+'), ' '),
      );
    } catch (_) {
      return null;
    }
  }

  static String _percent(double confidence) => '${(confidence * 100).round()}%';

  static final _systemPrompt =
      '''
Classify this one CircuitCode user message into exactly one Studio intent.

Use chat for greetings/acknowledgements, ask for questions, research, discovery, or when unsure, plan for an explicitly requested implementation plan, code for an explicit implementation/file change, review for an explicit read-only diff/change review, and verify for a request to run checks or commands. Do not infer file changes or commands from vague language. Return ONLY a JSON object matching this schema, with no markdown:
${jsonEncode(IntentModelClassification.jsonSchema)}
''';
}
