import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import 'llm_storage_service.dart';

abstract class LLMProvider {
  Stream<String> generateStream(List<Message> history, String prompt, {String? systemPrompt});
}

class LLMConfig {
  final String name;
  final String apiKey;
  final String baseUrl;
  final String model;
  final bool isEnabled;
  final String? extraBodyJson;
  final double? temperature;
  const LLMConfig({
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.isEnabled = true,
    this.extraBodyJson,
    this.temperature,
  });

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      name: json['name'] as String,
      apiKey: json['apiKey'] as String,
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String,
      isEnabled: json['isEnabled'] as bool? ?? true,
      extraBodyJson: json['extraBodyJson'] as String?,
      temperature: (json['temperature'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'isEnabled': isEnabled,
      if (extraBodyJson != null) 'extraBodyJson': extraBodyJson,
      if (temperature != null) 'temperature': temperature,
    };
  }

  LLMConfig copyWith({
    String? name,
    String? apiKey,
    String? baseUrl,
    String? model,
    bool? isEnabled,
    String? extraBodyJson,
    double? temperature,
  }) {
    return LLMConfig(
      name: name ?? this.name,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      isEnabled: isEnabled ?? this.isEnabled,
      extraBodyJson: extraBodyJson ?? this.extraBodyJson,
      temperature: temperature ?? this.temperature,
    );
  }
}

// Manages the LLM configurations and persistence
class ConfigNotifier extends AsyncNotifier<Map<String, LLMConfig>> {
  final _storage = LLMStorageService();

  @override
  Future<Map<String, LLMConfig>> build() async {
    print('ConfigNotifier: build() started');
    final data = await _storage.readConfig();
    print('ConfigNotifier: config data read from storage');
    final List<dynamic> models = data['models'] ?? [];
    final Map<String, LLMConfig> configs = {};
    for (final modelJson in models) {
      final config = LLMConfig.fromJson(modelJson as Map<String, dynamic>);
      configs[config.name] = config;
    }
    print('ConfigNotifier: ${configs.length} models parsed');
    
    // Set default model if not set (optional side effect, careful with loop)
    if (state.hasValue) {
       // already loaded
    } else {
        final defaultModel = data['defaultModel'] as String?;
        if (defaultModel != null && configs.containsKey(defaultModel)) {
            print('ConfigNotifier: Scheduling default model update: $defaultModel');
            Future.microtask(() {
               ref.read(currentModelProvider.notifier).state = defaultModel;
               print('ConfigNotifier: Default model updated in provider');
            });
        }
    }
    print('ConfigNotifier: build() finished');
    return configs;
  }

  Future<void> addModel(LLMConfig config) async {
    final current = state.valueOrNull ?? {};
    final newConfigs = Map<String, LLMConfig>.from(current);
    newConfigs[config.name] = config;
    
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
  }

  Future<void> removeModel(String name) async {
    final current = state.valueOrNull ?? {};
    if (!current.containsKey(name)) return;
    
    final newConfigs = Map<String, LLMConfig>.from(current);
    newConfigs.remove(name);
    
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
  }

  Future<void> _save(Map<String, LLMConfig> configs) async {
    final currentModel = ref.read(currentModelProvider);
    
    final data = {
      'defaultModel': currentModel,
      'models': configs.values.map((e) => e.toJson()).toList(),
    };
    await _storage.saveConfig(data);
  }

  Future<void> updateDefaultModel(String newModel) async {
    // 1. Update the UI state
    // We access the notifier directly here. 
    // Since we are inside ConfigNotifier, using ref is fine.
    ref.read(currentModelProvider.notifier).state = newModel;

    // 2. Save entire config to persist this change
    final currentConfigs = state.valueOrNull ?? {};
    await _save(currentConfigs);
  }

  Future<void> toggleModel(String name) async {
    final current = state.valueOrNull ?? {};
    if (!current.containsKey(name)) return;
    
    final newConfigs = Map<String, LLMConfig>.from(current);
    final config = newConfigs[name]!;
    newConfigs[name] = config.copyWith(isEnabled: !config.isEnabled);
    
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
  }

  /// Export current configurations to JSON format compatible with assets/config/llm.json
  Map<String, dynamic> exportToJson() {
    final current = state.valueOrNull ?? {};
    final currentModel = ref.read(currentModelProvider);
    
    return {
      'defaultModel': currentModel,
      'models': current.values.map((e) => e.toJson()).toList(),
    };
  }

  /// Import configurations from JSON
  /// If [merge] is true, new models will be added and existing ones updated
  /// If [merge] is false, all existing models will be replaced
  Future<void> importFromJson(Map<String, dynamic> jsonData, {bool merge = true}) async {
    final List<dynamic> models = jsonData['models'] ?? [];
    final String? defaultModel = jsonData['defaultModel'] as String?;
    
    Map<String, LLMConfig> newConfigs;
    
    if (merge) {
      // Merge mode: keep existing configs and add/update from import
      newConfigs = Map<String, LLMConfig>.from(state.valueOrNull ?? {});
    } else {
      // Overwrite mode: start fresh
      newConfigs = {};
    }
    
    // Add/update models from import
    for (final modelJson in models) {
      final config = LLMConfig.fromJson(modelJson as Map<String, dynamic>);
      newConfigs[config.name] = config;
    }
    
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
    
    // Update default model if specified and exists
    if (defaultModel != null && newConfigs.containsKey(defaultModel)) {
      ref.read(currentModelProvider.notifier).state = defaultModel;
    }
  }
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, Map<String, LLMConfig>>(ConfigNotifier.new);

// Use a simple StateProvider, but we might want to listen to changes 
// and save them? 
// For now, let's keep it simple. The ConfigNotifier will handle saving when models change.
// When currentModel changes, we should probably save that too?
final currentModelProvider = StateProvider<String>((ref) => 'deepseek-chat');

final llmProvider = FutureProvider<LLMProvider>((ref) async {
  print('llmProvider: initialization started');
  final currentModel = ref.watch(currentModelProvider);
  print('llmProvider: currentModel is $currentModel');
  final configs = await ref.watch(configProvider.future);
  print('llmProvider: configs loaded, ${configs.length} entries');
  
  // Safety check: ensure currentModel exists in configs
  var config = configs[currentModel];
  
  if (config == null) {
    if (configs.isNotEmpty) {
      // Fallback to first available model if current is invalid
      config = configs.values.first;
      // Ideally update the state too so UI is consistent
      Future.microtask(() => ref.read(currentModelProvider.notifier).state = config!.name);
    } else {
      throw Exception('未找到任何模型配置，请检查设置');
    }
  }

  return CustomOpenAILLMProvider(config!);
});

final modelNamesProvider = FutureProvider<List<String>>((ref) async {
  final configs = await ref.watch(configProvider.future);
  return configs.values.where((c) => c.isEnabled).map((c) => c.name).toList();
});

class CustomOpenAILLMProvider implements LLMProvider {
  final LLMConfig config;

  const CustomOpenAILLMProvider(this.config);

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
          // OpenAI spec says to ignore everything else, but logging helps debug
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
    
    // Default assumption: if neither, append /v1/chat/completions
    // This allows inputting "https://api.example.com" -> "https://api.example.com/v1/chat/completions"
    return '$uri/v1/chat/completions';
  }

  @override
  Stream<String> generateStream(List<Message> history, String prompt, {String? systemPrompt}) async* {
    final messages = [
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => <String, dynamic>{
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      }),
      {'role': 'user', 'content': prompt},
    ];

    final requestBody = {
      'model': config.model,
      'messages': messages,
      'stream': true,
      if (config.temperature != null) 'temperature': config.temperature!,
    };

    if (config.extraBodyJson != null && config.extraBodyJson!.isNotEmpty) {
      try {
        requestBody['extra_body'] = json.decode(config.extraBodyJson!);
      } catch (e) {
        print('解析 extraBodyJson 失败: $e');
      }
    }

    final client = http.Client();
    final url = _normalizeUrl(config.baseUrl);
    final request = http.Request('POST', Uri.parse(url))
      ..headers['Authorization'] = 'Bearer ${config.apiKey}'
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode(requestBody);

    final streamedResponse = await request.send().timeout(const Duration(seconds: 30));

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

// 使用示例:
// final configs = ref.read(configProvider);
// final modelNames = ref.read(modelNamesProvider);
// ref.read(currentModelProvider.notifier).state = 'deepseek-chat';
// final llm = await ref.read(llmProvider.future);
// llm.generateStream(history, prompt).listen((delta) => print(delta));