import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import '../models/chat_session.dart';
import '../models/llm_configs.dart';
import 'llm_storage_service.dart';

abstract class LLMProvider {
  Stream<String> generateStream(List<Message> history, String prompt, {List<Map<String, dynamic>>? userContentParts, String? systemPrompt});
}

class OpenAILLMProvider implements LLMProvider {
  final String baseUrl;
  final String apiKey;
  final String modelId;
  final double? temperature;

  const OpenAILLMProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
    this.temperature,
  });

  static Stream<String> parseSSE(Stream<List<int>> byteStream) async* {
    final decoder = const Utf8Decoder();
    final splitter = const LineSplitter();
    print('LLMProvider: Starting SSE parse...');
    try {
      await for (final line in byteStream.transform(decoder).transform(splitter)) {
        if (line.isEmpty) continue;
        if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          if (dataStr.isEmpty || dataStr == '[DONE]') continue;
          try {
            final parsed = json.decode(dataStr);
            final content = parsed['choices']?[0]?['delta']?['content'];
            if (content != null) yield content as String;
          } catch (e) {
            print('LLMProvider: SSE decode error: $e. Line: $line');
          }
        } else if (!line.startsWith(':')) {
          if (line.contains('"content"')) {
            print('LLMProvider: Suspicious non-data line: $line');
          }
        }
      }
    } catch (e) {
      print('LLMProvider: Byte stream error: $e');
      rethrow;
    }
    print('LLMProvider: SSE parse finished.');
  }

  String _normalizeUrl(String url) {
    var uri = url.trim();
    if (uri.endsWith('/')) {
      uri = uri.substring(0, uri.length - 1);
    }
    
    if (uri.endsWith('/chat/completions')) {
      return uri;
    }
    
    if (uri.endsWith('/v1')) {
      return '$uri/chat/completions';
    }
    
    return '$uri/v1/chat/completions';
  }

  @override
  Stream<String> generateStream(List<Message> history, String prompt, {List<Map<String, dynamic>>? userContentParts, String? systemPrompt}) async* {
    List<dynamic> messages = [];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in history) {
      final role = m.isUser ? 'user' : 'assistant';
      dynamic content = m.contentParts ?? m.text;
      messages.add({'role': role, 'content': content});
    }
    dynamic userContent = userContentParts ?? prompt;
    messages.add({'role': 'user', 'content': userContent});

    final requestBody = {
      'model': modelId,
      'messages': messages,
      'stream': true,
      if (temperature != null) 'temperature': temperature!,
    };

    final client = http.Client();
    final url = _normalizeUrl(baseUrl);
    final request = http.Request('POST', Uri.parse(url))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode(requestBody);

    final streamedResponse = await request.send().timeout(const Duration(seconds: 120));

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      yield '错误: ${streamedResponse.statusCode} $errorBody';
      client.close();
      return;
    }

    await for (final delta in parseSSE(streamedResponse.stream)) {
      if (delta.isNotEmpty) {
        yield delta;
      }
    }

    client.close();
  }
}

// Manages the LLM configurations and persistence
class ConfigNotifier extends AsyncNotifier<Map<String, ProviderConfig>> {
  final _storage = LLMStorageService();

  Map<String, ProviderConfig> _parseProviders(Map<String, dynamic> data) {
    if (data.containsKey('providers')) {
      final Map<String, dynamic> provJson = data['providers'] as Map<String, dynamic>;
      return provJson.map((key, value) => MapEntry(key, ProviderConfig.fromJson(key, value as Map<String, dynamic>)));
    } else {
      // legacy migration
      return _parseLegacy(data);
    }
  }

  Map<String, ProviderConfig> _parseLegacy(Map<String, dynamic> data) {
    final List<dynamic> modelsJson = data['models'] ?? [];
    final Map<String, ProviderConfig> providers = {};
    for (final modelJson in modelsJson) {
      final Map<String, dynamic> oldJson = modelJson as Map<String, dynamic>;
      final String name = oldJson['name'] as String;
      final List<String> parts = name.split('/');
      final String providerName = parts.isNotEmpty ? parts.first : 'legacy';
      final String modelName = parts.length > 1 ? parts.sublist(1).join('/') : name;
      final String baseUrl = oldJson['baseUrl'] as String? ?? '';
      final String apiKey = oldJson['apiKey'] as String? ?? '';
      final String modelId = oldJson['model'] as String? ?? '';
      final double? temperature = (oldJson['temperature'] as num?)?.toDouble();
      final bool supportsVision = oldJson['supportsVision'] as bool? ?? false;
      final bool supportsImageGen = oldJson['supportsImageGen'] as bool? ?? false;
      final Set<ModelType> types = {ModelType.llm};
      if (supportsVision) {
        types.add(ModelType.vl);
      }
      if (supportsImageGen) {
        types.add(ModelType.imageGen);
      }
      final ModelConfig modelConfig = ModelConfig(
        name: modelName,
        modelId: modelId,
        temperature: temperature,
        types: types,
        isEnabled: oldJson['isEnabled'] as bool? ?? true,
      );
      ProviderConfig? provider = providers[providerName];
      List<ModelConfig> newModels;
      if (provider == null) {
        newModels = [modelConfig];
      } else {
        newModels = provider.models
            .where((m) => m.name != modelName)
            .toList()
          ..add(modelConfig);
      }
      providers[providerName] = ProviderConfig(
        name: providerName,
        baseUrl: baseUrl,
        apiKey: apiKey,
        models: newModels,
      );
    }
    return providers;
  }

  bool _isValidModel(Map<String, ProviderConfig> providers, String modelKey) {
    final parts = modelKey.split('/');
    if (parts.length < 2) return false;
    final providerName = parts[0];
    final modelName = parts.sublist(1).join('/');
    final provider = providers[providerName];
    final model = provider?.getModel(modelName);
    return model != null && model.isEnabled;
  }

  @override
  Future<Map<String, ProviderConfig>> build() async {
    print('ConfigNotifier: build() started');
    final data = await _storage.readConfig();
    print('ConfigNotifier: config data read from storage');
    final providers = _parseProviders(data);
    print('ConfigNotifier: ${providers.length} providers parsed');
    
    final defaultModel = data['defaultModel'] as String?;
    if (defaultModel != null && _isValidModel(providers, defaultModel)) {
      Future.microtask(() {
        ref.read(chatCurrentModelProvider.notifier).state = defaultModel;
        ref.read(imageCurrentModelProvider.notifier).state = defaultModel;
        print('ConfigNotifier: Default model updated for chat and image: $defaultModel');
      });
    }
    print('ConfigNotifier: build() finished');
    return providers;
  }

  Future<void> _save(Map<String, ProviderConfig> providers) async {
    final currentModel = ref.read(chatCurrentModelProvider);
    final Map<String, dynamic> provData = {
      for (final provider in providers.values) provider.name: provider.toJson()
    };
    final data = {
      'defaultModel': currentModel,
      'providers': provData,
    };
    await _storage.saveConfig(data);
  }

  Future<void> addProvider(ProviderConfig config) async {
    final current = state.valueOrNull ?? {};
    final newProviders = Map<String, ProviderConfig>.from(current);
    newProviders[config.name] = config;
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
  }

  Future<void> updateProvider(String name, ProviderConfig updated) async {
    final current = state.valueOrNull ?? {};
    if (!current.containsKey(name)) return;
    final newProviders = Map<String, ProviderConfig>.from(current);
    newProviders[name] = updated;
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
  }

  Future<void> removeProvider(String name) async {
    final current = state.valueOrNull ?? {};
    if (!current.containsKey(name)) return;
    final newProviders = Map<String, ProviderConfig>.from(current);
    newProviders.remove(name);
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
  }

  Future<void> addModel(String providerName, ModelConfig model) async {
    final current = state.valueOrNull ?? {};
    final provider = current[providerName];
    if (provider == null) return;
    final newModels = List<ModelConfig>.from(provider.models)..add(model);
    final updatedProvider = provider.copyWith(models: newModels);
    final newProviders = Map<String, ProviderConfig>.from(current);
    newProviders[providerName] = updatedProvider;
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
  }

  Future<void> updateModel(String providerName, String modelName, ModelConfig updatedModel) async {
    final current = state.valueOrNull ?? {};
    final provider = current[providerName];
    if (provider == null) return;
    final modelIndex = provider.models.indexWhere((m) => m.name == modelName);
    if (modelIndex == -1) return;
    final newModels = List<ModelConfig>.from(provider.models);
    newModels[modelIndex] = updatedModel;
    final updatedProvider = provider.copyWith(models: newModels);
    final newProviders = Map<String, ProviderConfig>.from(current);
    newProviders[providerName] = updatedProvider;
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
  }

  Future<void> removeModel(String providerName, String modelName) async {
    final current = state.valueOrNull ?? {};
    final provider = current[providerName];
    if (provider == null) return;
    final newModels = provider.models.where((m) => m.name != modelName).toList();
    final updatedProvider = provider.copyWith(models: newModels);
    final newProviders = Map<String, ProviderConfig>.from(current);
    newProviders[providerName] = updatedProvider;
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
  }

  Future<void> toggleModelEnabled(String providerName, String modelName) async {
    final current = state.valueOrNull ?? {};
    final provider = current[providerName];
    if (provider == null) return;
    final modelIndex = provider.models.indexWhere((m) => m.name == modelName);
    if (modelIndex == -1) return;
    final newModels = List<ModelConfig>.from(provider.models);
    final oldModel = newModels[modelIndex];
    newModels[modelIndex] = oldModel.copyWith(isEnabled: !oldModel.isEnabled);
    final updatedProvider = provider.copyWith(models: newModels);
    final newProviders = Map<String, ProviderConfig>.from(current);
    newProviders[providerName] = updatedProvider;
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
  }

  Future<void> updateDefaultModel(String newModel) async {
    final currentProviders = state.valueOrNull ?? {};
    await _save(currentProviders);
  }

  Map<String, dynamic> exportToJson() {
    final providers = state.valueOrNull ?? {};
    final currentModel = ref.read(chatCurrentModelProvider);
    final Map<String, dynamic> provData = {
      for (final provider in providers.values) provider.name: provider.toJson()
    };
    return {
      'defaultModel': currentModel,
      'providers': provData,
    };
  }

  Future<void> importFromJson(Map<String, dynamic> jsonData, {bool merge = true}) async {
    Map<String, ProviderConfig> newProviders;
    if (merge) {
      newProviders = Map<String, ProviderConfig>.from(state.valueOrNull ?? {});
    } else {
      newProviders = {};
    }
    final parsedProviders = _parseProviders(jsonData);
    newProviders.addAll(parsedProviders);
    state = AsyncValue.data(newProviders);
    await _save(newProviders);
    
    final defaultModel = jsonData['defaultModel'] as String?;
    if (defaultModel != null && _isValidModel(newProviders, defaultModel)) {
      ref.read(chatCurrentModelProvider.notifier).state = defaultModel;
      ref.read(imageCurrentModelProvider.notifier).state = defaultModel;
    }
  }
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, Map<String, ProviderConfig>>(ConfigNotifier.new);

final chatCurrentModelProvider = StateProvider<String>((ref) => 'deepseek/deepseek-chat');
final imageCurrentModelProvider = StateProvider<String>((ref) => '');

final chatLlmProvider = FutureProvider<LLMProvider>((ref) async {
  print('chatLlmProvider: initialization started');
  final currentModel = ref.watch(chatCurrentModelProvider);
  print('chatLlmProvider: currentModel is $currentModel');
  final providers = await ref.watch(configProvider.future);
  print('llmProvider: providers loaded, ${providers.length} entries');
  
  final parts = currentModel.split('/');
  if (parts.length != 2) {
    throw Exception('Invalid model format: $currentModel. Expected "provider/model"');
  }
  final providerName = parts[0];
  final modelName = parts.sublist(1).join('/');
  final provider = providers[providerName];
  if (provider == null) {
    throw Exception('Provider "$providerName" not found');
  }
  final model = provider.getModel(modelName);
  if (model == null || !model.isEnabled) {
    throw Exception('Model "$modelName" not found or disabled in provider "$providerName"');
  }
  print('llmProvider: using ${provider.name}/${model.name}');
  return OpenAILLMProvider(
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    modelId: model.modelId,
    temperature: model.temperature,
  );
});

final chatModelNamesProvider = FutureProvider<List<String>>((ref) async {
  final providers = await ref.watch(configProvider.future);
  final List<String> names = [];
  for (final provider in providers.values) {
    for (final model in provider.models.where((m) => m.isEnabled && (m.types.contains(ModelType.llm) || m.types.contains(ModelType.vl)))) {
      names.add('${provider.name}/${model.name}');
    }
  }
  return names;
});

final imageModelNamesProvider = FutureProvider<List<String>>((ref) async {
  final providers = await ref.watch(configProvider.future);
  final List<String> names = [];
  for (final provider in providers.values) {
    for (final model in provider.models.where((m) => m.isEnabled && m.types.contains(ModelType.imageGen))) {
      names.add('${provider.name}/${model.name}');
    }
  }
  return names;
});

final chatSupportsVisionProvider = FutureProvider<bool>((ref) async {
  final currentModel = ref.watch(chatCurrentModelProvider);
  final providers = await ref.watch(configProvider.future);
  final parts = currentModel.split('/');
  if (parts.length != 2) return false;
  final providerName = parts[0];
  final modelName = parts.sublist(1).join('/');
  final model = providers[providerName]?.getModel(modelName);
  return model?.types.contains(ModelType.vl) ?? false;
});
