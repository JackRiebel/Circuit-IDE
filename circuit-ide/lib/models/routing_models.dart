import 'dart:convert';

enum TaskComplexity { simple, moderate, complex }

enum ModelTier { fast, balanced, powerful }

class RoutingDecision {
  final TaskComplexity complexity;
  final String selectedModel;
  final ModelTier tier;
  final String reason;
  final double estimatedSavings;

  const RoutingDecision({
    required this.complexity,
    required this.selectedModel,
    required this.tier,
    required this.reason,
    this.estimatedSavings = 0,
  });
}

class RoutingConfig {
  final bool enabled;
  final ModelTier minTier;
  final bool preferSpeed;
  final bool preferQuality;
  final double costSavings;
  final int routedRequests;

  const RoutingConfig({
    this.enabled = false,
    this.minTier = ModelTier.fast,
    this.preferSpeed = false,
    this.preferQuality = false,
    this.costSavings = 0,
    this.routedRequests = 0,
  });

  RoutingConfig copyWith({
    bool? enabled,
    ModelTier? minTier,
    bool? preferSpeed,
    bool? preferQuality,
    double? costSavings,
    int? routedRequests,
  }) {
    return RoutingConfig(
      enabled: enabled ?? this.enabled,
      minTier: minTier ?? this.minTier,
      preferSpeed: preferSpeed ?? this.preferSpeed,
      preferQuality: preferQuality ?? this.preferQuality,
      costSavings: costSavings ?? this.costSavings,
      routedRequests: routedRequests ?? this.routedRequests,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'min_tier': minTier.name,
        'prefer_speed': preferSpeed,
        'prefer_quality': preferQuality,
        'cost_savings': costSavings,
        'routed_requests': routedRequests,
      };

  factory RoutingConfig.fromJson(Map<String, dynamic> json) {
    return RoutingConfig(
      enabled: json['enabled'] as bool? ?? false,
      minTier: ModelTier.values.firstWhere(
        (t) => t.name == json['min_tier'],
        orElse: () => ModelTier.fast,
      ),
      preferSpeed: json['prefer_speed'] as bool? ?? false,
      preferQuality: json['prefer_quality'] as bool? ?? false,
      costSavings: (json['cost_savings'] as num?)?.toDouble() ?? 0,
      routedRequests: json['routed_requests'] as int? ?? 0,
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
