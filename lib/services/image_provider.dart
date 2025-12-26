import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/llm_configs.dart';
import 'llm_provider.dart';

class ImageGenerationResult {
  final Uint8List? imageBytes;
  final String description;

  const ImageGenerationResult({
    this.imageBytes,
    this.description = '',
  });
}

abstract class ImageGenerator {
  Future<ImageGenerationResult> generateImage(String prompt, {List<String>? base64Images});
}

class CustomImageGenerator implements ImageGenerator {
  final String baseUrl;
  final String apiKey;
  final String modelId;
  final double? temperature;

  const CustomImageGenerator(this.baseUrl, this.apiKey, this.modelId, this.temperature);

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
  Future<ImageGenerationResult> generateImage(String prompt, {List<String>? base64Images}) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('请在设置页面配置有效的 API Key');
    }

    final url = Uri.parse(_normalizeUrl(baseUrl));
    List<Map<String, dynamic>> contentParts = [];
    if (base64Images != null && base64Images.isNotEmpty) {
      for (final base64 in base64Images) {
        contentParts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,$base64'}
        });
      }
    }
    contentParts.add({'type': 'text', 'text': prompt});

    final body = {
      'model': modelId,
      'messages': [
        {'role': 'system', 'content': '你是一个图像生成器。根据用户提示生成图像，并严格以以下格式响应：content 是一个列表，第一个元素必须是 {"type": "image_url", "image_url": {"url": "data:image/png;base64,BASE64_ENCODED_IMAGE"}} 或远程图像URL。不要输出任何其他文本描述或解释。'},
        {'role': 'user', 'content': contentParts}
      ],
      'stream': false,
      'modalities': ['image', 'text'],
      'max_tokens': 4096,
      if (temperature != null) 'temperature': temperature!,
    };

    print('ImageGenerator: Request URL: $url');
    print('ImageGenerator: Request model: $modelId');
    final bodyStr = json.encode(body);
    print('ImageGenerator: Request body preview: ${bodyStr.length < 1000 ? bodyStr : bodyStr.substring(0, 1000)}...');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );

    print('ImageGenerator: Response status: ${response.statusCode}');
    print('ImageGenerator: Response body preview: ${response.body.length < 500 ? response.body : response.body.substring(0, 500)}...');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices[0]['message'];
        Uint8List? imageBytes;
        String description = '';
        dynamic contentRaw = message['content'];
        List<dynamic> parts = [];
        if (message['images'] is List) {
          parts = List<dynamic>.from(message['images']);
        } else if (contentRaw is List) {
          parts = List<dynamic>.from(contentRaw);
        }
        if (parts.isNotEmpty) {
          final imagePart = parts.first;
          if (imagePart['type'] == 'image_url') {
            final imageUrlObj = imagePart['image_url'];
            if (imageUrlObj is Map<String, dynamic> && imageUrlObj['url'] is String) {
              final imageUrl = imageUrlObj['url'] as String;
              if (imageUrl.startsWith('data:image')) {
                final base64Str = imageUrl.split(',')[1];
                imageBytes = base64Decode(base64Str);
              } else {
                final imgResponse = await http.get(Uri.parse(imageUrl));
                if (imgResponse.statusCode == 200) {
                  imageBytes = imgResponse.bodyBytes;
                } else {
                  description = '下载远程图像失败: ${imgResponse.statusCode}';
                }
              }
            }
          }
          for (var part in parts.skip(1)) {
            if (part['type'] == 'text' && part['text'] is String) {
              description += '${part['text']}\n';
            }
          }
        } else if (contentRaw is String) {
          description = contentRaw;
          if (description.startsWith('data:image/')) {
            final strParts = description.split(',');
            if (strParts.length > 1) {
              imageBytes = base64Decode(strParts[1]);
            }
          }
        } else {
          description = '响应格式不支持: ${contentRaw.runtimeType}';
        }
        if (imageBytes == null) {
          throw Exception('图像生成失败：模型未返回有效图像数据。详情 - description: "$description", content: "$contentRaw", images: "${message['images']}"');
        }
        return ImageGenerationResult(imageBytes: imageBytes, description: description);
      }
    }
    print('ImageGenerator: HTTP Error ${response.statusCode}: ${response.body.length < 500 ? response.body : response.body.substring(0, 500)}...');
    throw Exception('图像生成失败: HTTP ${response.statusCode}\n${response.body}');
  }
}

final imageGeneratorProvider = FutureProvider<ImageGenerator>((ref) async {
  final currentModel = ref.watch(imageCurrentModelProvider);
  final providers = await ref.watch(configProvider.future);
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
  if (model == null || !model.isEnabled || !model.types.contains(ModelType.imageGen)) {
    String reason;
    if (model == null) {
      reason = '未找到';
    } else if (!model.isEnabled) {
      reason = '已禁用';
    } else {
      reason = '不支持图像生成 (types: ${model.types.map((t) => t.name).join(', ')})';
    }
    throw Exception('模型不可用: $currentModel ($reason)');
  }
  return CustomImageGenerator(provider.baseUrl, provider.apiKey, model.modelId, model.temperature);
});
