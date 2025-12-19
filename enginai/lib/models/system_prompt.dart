import 'package:uuid/uuid.dart';

class SystemPrompt {
  final String id;
  final String name;
  final String content;
  final DateTime createdAt;

  SystemPrompt({
    String? id,
    required this.name,
    required this.content,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    return SystemPrompt(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  SystemPrompt copyWith({
    String? id,
    String? name,
    String? content,
    DateTime? createdAt,
  }) {
    return SystemPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
