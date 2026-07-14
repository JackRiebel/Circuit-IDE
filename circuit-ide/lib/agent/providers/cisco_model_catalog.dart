import '../config/models_config.dart';
import 'provider_interface.dart';

/// Normalizes Circuit's optional remote model catalog without coupling it to
/// OAuth, HTTP, or streaming transport. Unknown catalog entries get safe,
/// conservative defaults; known built-in entries retain their declared
/// capability and token-accounting semantics.
abstract final class CiscoModelCatalog {
  static List<ConnectorModelInfo> bundled() {
    return ModelsConfig.ciscoModels
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
        .toList(growable: false);
  }

  static List<ConnectorModelInfo> parse(Object? data) {
    final items = switch (data) {
      {'data': final List<dynamic> models} => models,
      {'models': final List<dynamic> models} => models,
      final List<dynamic> models => models,
      _ => const <dynamic>[],
    };

    return items
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final id = json['id'] as String? ?? json['model'] as String?;
          if (id == null || id.trim().isEmpty) return null;
          final capabilities = json['capabilities'] as Map<String, dynamic>?;
          final supportsTools =
              capabilities?['tools'] as bool? ??
              capabilities?['tool_calls'] as bool? ??
              supportsToolsFor(id);
          final supportsImageInput =
              capabilities?['image_input'] as bool? ??
              capabilities?['vision'] as bool? ??
              capabilities?['images'] as bool? ??
              supportsImageInputFor(id);
          final supportsJsonSchema =
              capabilities?['json_schema'] as bool? ??
              capabilities?['structured_output'] as bool? ??
              supportsJsonSchemaFor(id);
          final supportsReasoning =
              capabilities?['reasoning'] as bool? ??
              capabilities?['thinking'] as bool? ??
              supportsReasoningFor(id);
          final contextWindow =
              json['contextWindow'] as int? ??
              json['context_window'] as int? ??
              120000;
          return ConnectorModelInfo(
            id: id,
            displayName:
                json['displayName'] as String? ??
                json['display_name'] as String? ??
                id,
            contextWindow: contextWindow,
            supportsTools: supportsTools,
            supportsImageInput: supportsImageInput,
            supportsJsonSchema: supportsJsonSchema,
            supportsReasoning: supportsReasoning,
            tokenSemantics: _tokenSemantics(
              capabilities?['token_semantics'] ?? json['token_semantics'],
            ),
            inputCostPer1k:
                (json['inputCostPer1k'] as num?)?.toDouble() ??
                (json['input_cost_per_1k'] as num?)?.toDouble() ??
                0,
            outputCostPer1k:
                (json['outputCostPer1k'] as num?)?.toDouble() ??
                (json['output_cost_per_1k'] as num?)?.toDouble() ??
                0,
          );
        })
        .whereType<ConnectorModelInfo>()
        .toList(growable: false);
  }

  static bool supportsToolsFor(String id) => ModelsConfig.ciscoModels.any(
    (model) => model.id == id && model.supportsTools,
  );

  static bool supportsImageInputFor(String id) => ModelsConfig.ciscoModels.any(
    (model) => model.id == id && model.supportsImageInput,
  );

  static bool supportsJsonSchemaFor(String id) => ModelsConfig.ciscoModels.any(
    (model) => model.id == id && model.supportsJsonSchema,
  );

  static bool supportsReasoningFor(String id) => ModelsConfig.ciscoModels.any(
    (model) => model.id == id && model.supportsReasoning,
  );

  static ProviderTokenSemantics _tokenSemantics(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'aggregate' || 'aggregate_only' => ProviderTokenSemantics.aggregateOnly,
      'input_output' ||
      'input-and-output' => ProviderTokenSemantics.inputAndOutput,
      'input_cached_output_reasoning_tool' ||
      'detailed' => ProviderTokenSemantics.inputCachedOutputReasoningTool,
      _ => ProviderTokenSemantics.inputAndOutput,
    };
  }
}
