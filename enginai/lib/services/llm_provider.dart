import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'llm_storage_service.dart';

class Message {
  final bool isUser;
  final String text;

  Message({
    required this.isUser,
    required this.text,
  });
}

abstract class LLMProvider {
  Stream<String> generateStream(List<Message> history, String prompt);
}

class LLMConfig {
  final String name;
  final String apiKey;
  final String baseUrl;
  final String model;

  const LLMConfig({
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      name: json['name'] as String,
      apiKey: json['apiKey'] as String,
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
    };
  }
}

// Manages the LLM configurations and persistence
class ConfigNotifier extends AsyncNotifier<Map<String, LLMConfig>> {
  final _storage = LLMStorageService();

  @override
  Future<Map<String, LLMConfig>> build() async {
    final data = await _storage.readConfig();
    final List<dynamic> models = data['models'];
    final Map<String, LLMConfig> configs = {};
    for (final modelJson in models) {
      final config = LLMConfig.fromJson(modelJson as Map<String, dynamic>);
      configs[config.name] = config;
    }
    
    // Set default model if not set (optional side effect, careful with loop)
    if (state.hasValue) {
       // already loaded
    } else {
        final defaultModel = data['defaultModel'] as String?;
        if (defaultModel != null && configs.containsKey(defaultModel)) {
            // We need to defer this update or handle it in the UI/ViewModel
            // ref.read(currentModelProvider.notifier).state = defaultModel;
            // Provide data for default model via a separate provider or return a wrapper object
        }
    }
    
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
    // preserve default model from current state or provider?
    // checking currentModelProvider is tricky inside here.
    // For now, just save models.
    final currentModel = ref.read(currentModelProvider);
    
    final data = {
      'defaultModel': currentModel,
      'models': configs.values.map((e) => e.toJson()).toList(),
    };
    await _storage.saveConfig(data);
  }
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, Map<String, LLMConfig>>(ConfigNotifier.new);

final currentModelProvider = StateProvider<String>((ref) => 'deepseek-chat');

final llmProvider = FutureProvider<LLMProvider>((ref) async {
  final currentModel = ref.watch(currentModelProvider);
  final configs = await ref.watch(configProvider.future);
  final config = configs[currentModel];
  if (config == null) {
    // If current model not found, try falling back to first available or throw
    if (configs.isNotEmpty) {
      return CustomOpenAILLMProvider(
        apiKey: configs.values.first.apiKey,
        baseUrl: configs.values.first.baseUrl,
        model: configs.values.first.model,
      );
    }
    throw Exception('模型 $currentModel 未找到，请检查配置文件');
  }
  return CustomOpenAILLMProvider(
    apiKey: config.apiKey,
    baseUrl: config.baseUrl,
    model: config.model,
  );
});

final modelNamesProvider = FutureProvider<List<String>>((ref) async {
  final configs = await ref.watch(configProvider.future);
  return configs.keys.toList();
});

class CustomOpenAILLMProvider implements LLMProvider {
  final String apiKey;
  final String baseUrl;
  final String model;

  const CustomOpenAILLMProvider({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  static Stream<String> parseSSE(Stream<List<int>> byteStream) async* {
    final decoder = const Utf8Decoder();
    final splitter = const LineSplitter();
    await for (final line in byteStream.transform(decoder).transform(splitter)) {
      if (line.startsWith('data: ')) {
        final dataStr = line.substring(6).trim();
        if (dataStr.isEmpty || dataStr == '[DONE]') continue;
        try {
          final parsed = json.decode(dataStr);
          final content = parsed['choices']?[0]?['delta']?['content'];
          if (content != null) yield content as String;
        } catch (_) {
          // ignore parse errors
        }
      }
    }
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
  Stream<String> generateStream(List<Message> history, String prompt) async* {
    final messages = [
      ...history.map((m) => <String, dynamic>{
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      }),
      {'role': 'user', 'content': prompt},
    ];

    final requestBody = {
      'model': model,
      'messages': messages,
      'stream': true,
      'temperature': 0.7,
    };

    final client = http.Client();
    final url = _normalizeUrl(baseUrl);
    final request = http.Request('POST', Uri.parse(url))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode(requestBody);

    final streamedResponse = await request.send();

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