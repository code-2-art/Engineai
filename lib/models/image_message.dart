import 'dart:typed_data';
import 'dart:convert';

class ImageMessage {
  final String prompt;
  final Uint8List image;
  final String? aiDescription;
  final DateTime timestamp;
  final bool isSeparator;

  ImageMessage(this.prompt, this.image, this.aiDescription, [DateTime? timestamp, this.isSeparator = false]) : timestamp = timestamp ?? DateTime.now();

  factory ImageMessage.fromJson(Map<String, dynamic> json) {
    final prompt = json['prompt'] as String;
    final imageBase64 = json['imageBase64'] as String;
    final image = base64Decode(imageBase64) as Uint8List;
    final aiDescription = json['aiDescription'] as String?;
    final timestampStr = json['timestamp'] as String;
    final timestamp = DateTime.parse(timestampStr);
    final isSeparator = (json['isSeparator'] as bool?) ?? false;
    return ImageMessage(prompt, image, aiDescription, timestamp, isSeparator);
  }

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'imageBase64': base64Encode(image),
      'aiDescription': aiDescription,
      'timestamp': timestamp.toIso8601String(),
      'isSeparator': isSeparator,
    };
  }
}