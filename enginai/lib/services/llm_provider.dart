import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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
}

final configProvider = FutureProvider<Map<String, LLMConfig>>((ref) async {
  final configString = await rootBundle.loadString('assets/config/llm.json');
  final Map<String, dynamic> data = json.decode(configString);
  final List<dynamic> models = data['models'];
  final Map<String, LLMConfig> configs = {};
  for (final modelJson in models) {
    final config = LLMConfig.fromJson(modelJson as Map<String, dynamic>);
    configs[config.name] = config;
  }
  return configs;
});

final currentModelProvider = StateProvider<String>((ref) => 'deepseek-chat');

final llmProvider = FutureProvider<LLMProvider>((ref) async {
  final currentModel = ref.watch(currentModelProvider);
  final configs = await ref.read(configProvider.future);
  final config = configs[currentModel];
  if (config == null) {
    throw Exception('模型 $currentModel 未找到，请检查配置文件');
  }
  return CustomOpenAILLMProvider(
    apiKey: config.apiKey,
    baseUrl: config.baseUrl,
    model: config.model,
  );
});

final modelNamesProvider = FutureProvider<List<String>>((ref) async {
  final configs = await ref.read(configProvider.future);
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
    final request = http.Request('POST', Uri.parse(baseUrl))
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