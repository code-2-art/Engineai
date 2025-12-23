import 'package:collection/collection.dart';

enum ModelType {
  llm,
  vl,
  imageGen,
  embedding,
}

class ModelConfig {
  final String name;
  final String modelId;
  final double? temperature;
  final Set<ModelType> types;
  final bool isEnabled;

  const ModelConfig({
    required this.name,
    required this.modelId,
    this.temperature,
    required this.types,
    this.isEnabled = true,
  });

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      name: json['name'] as String,
      modelId: json['modelId'] as String? ?? json['model'] as String,
      temperature: (json['temperature'] as num?)?.toDouble(),
      types: (json['types'] as List<dynamic>?)?.map((dynamic name) {
        final String s = name.toString();
        return ModelType.values.firstWhereOrNull((e) => e.name == s);
      }).whereType<ModelType>().toSet() ?? {ModelType.llm},
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'modelId': modelId,
      'temperature': temperature,
      'types': types.map((e) => e.name).toList(),
      'isEnabled': isEnabled,
    };
  }

  ModelConfig copyWith({
    String? name,
    String? modelId,
    double? temperature,
    Set<ModelType>? types,
    bool? isEnabled,
  }) {
    return ModelConfig(
      name: name ?? this.name,
      modelId: modelId ?? this.modelId,
      temperature: temperature ?? this.temperature,
      types: types ?? this.types,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class ProviderConfig {
  final String name;
  final String baseUrl;
  final String apiKey;
  final List<ModelConfig> models;

  const ProviderConfig({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.models = const [],
  });

  factory ProviderConfig.fromJson(String providerName, Map<String, dynamic> json) {
    return ProviderConfig(
      name: providerName,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      models: (json['models'] as List<dynamic>?)
        ?.map((dynamic m) => ModelConfig.fromJson(m as Map<String, dynamic>))
        .toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'models': models.map((m) => m.toJson()).toList(),
    };
  }

  ProviderConfig copyWith({
    String? baseUrl,
    String? apiKey,
    List<ModelConfig>? models,
  }) {
    return ProviderConfig(
      name: name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
    );
  }

  ModelConfig? getModel(String modelName) => (models.firstWhereOrNull((m) => m.name == modelName));
}