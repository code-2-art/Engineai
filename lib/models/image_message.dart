import 'dart:typed_data';
import 'dart:convert';

/// 图片消息元数据（不含图片数据）
/// 用于快速加载历史记录，图片数据按需加载
class ImageMessage {
  final String prompt;
  final String? imageRef; // 图片引用ID，不包含实际图片数据
  final String? aiDescription;
  final DateTime timestamp;
  final bool isSeparator;

  ImageMessage({
    required this.prompt,
    this.imageRef,
    this.aiDescription,
    DateTime? timestamp,
    this.isSeparator = false,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 创建包含图片数据的完整消息（用于显示时）
  ImageMessage withImageData(Uint8List imageData) {
    return ImageMessage(
      prompt: prompt,
      imageRef: imageRef,
      aiDescription: aiDescription,
      timestamp: timestamp,
      isSeparator: isSeparator,
    ).._cachedImageData = imageData;
  }

  /// 缓存的图片数据（仅用于显示时）
  Uint8List? _cachedImageData;

  /// 获取缓存的图片数据
  Uint8List? get cachedImageData => _cachedImageData;

  /// 设置缓存的图片数据
  void setCachedImageData(Uint8List data) {
    _cachedImageData = data;
  }

  /// 清除缓存的图片数据
  void clearCachedImageData() {
    _cachedImageData = null;
  }

  /// 从JSON创建元数据（不含图片数据）
  factory ImageMessage.fromJson(Map<String, dynamic> json) {
    return ImageMessage(
      prompt: json['prompt'] as String,
      imageRef: json['imageRef'] as String?,
      aiDescription: json['aiDescription'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isSeparator: (json['isSeparator'] as bool?) ?? false,
    );
  }

  /// 从旧格式JSON创建（兼容性，用于数据迁移）
  factory ImageMessage.fromLegacyJson(Map<String, dynamic> json) {
    final prompt = json['prompt'] as String;
    final imageBase64 = json['imageBase64'] as String?;
    final aiDescription = json['aiDescription'] as String?;
    final timestampStr = json['timestamp'] as String;
    final timestamp = DateTime.parse(timestampStr);
    final isSeparator = (json['isSeparator'] as bool?) ?? false;

    // 旧格式包含图片数据，需要迁移
    Uint8List? imageData;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        imageData = base64Decode(imageBase64) as Uint8List;
      } catch (e) {
        print('Error decoding legacy image data: $e');
      }
    }

    return ImageMessage(
      prompt: prompt,
      imageRef: null, // 旧格式没有imageRef，需要后续迁移
      aiDescription: aiDescription,
      timestamp: timestamp,
      isSeparator: isSeparator,
    ).._cachedImageData = imageData;
  }

  /// 转换为JSON（只包含元数据）
  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'imageRef': imageRef,
      'aiDescription': aiDescription,
      'timestamp': timestamp.toIso8601String(),
      'isSeparator': isSeparator,
    };
  }

  /// 检查是否有图片
  bool get hasImage => imageRef != null && imageRef!.isNotEmpty;

  /// 检查是否有缓存的图片数据
  bool get hasCachedImageData => _cachedImageData != null;

  /// 复制消息
  ImageMessage copyWith({
    String? prompt,
    String? imageRef,
    String? aiDescription,
    DateTime? timestamp,
    bool? isSeparator,
    bool clearCache = false,
  }) {
    // 深拷贝缓存的图片数据
    Uint8List? copiedImageData;
    if (!clearCache && _cachedImageData != null) {
      copiedImageData = Uint8List.fromList(_cachedImageData!);
    }
    
    return ImageMessage(
      prompt: prompt ?? this.prompt,
      imageRef: imageRef ?? this.imageRef,
      aiDescription: aiDescription ?? this.aiDescription,
      timestamp: timestamp ?? this.timestamp,
      isSeparator: isSeparator ?? this.isSeparator,
    ).._cachedImageData = copiedImageData;
  }
}
