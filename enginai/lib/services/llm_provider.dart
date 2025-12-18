import 'dart:async';
import 'dart:convert';
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

// 使用示例: final llm = CustomOpenAILLMProvider();
// llm.generateStream(history, prompt).listen((delta) => print(delta));