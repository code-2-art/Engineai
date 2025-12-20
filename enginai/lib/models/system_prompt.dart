import 'package:uuid/uuid.dart';

class SystemPrompt {
  final String id;
  final String name;
  final String content;
  final DateTime createdAt;
  final bool isEnabled;

  SystemPrompt({
    String? id,
    required this.name,
    required this.content,
    DateTime? createdAt,
    this.isEnabled = true,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    return SystemPrompt(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'isEnabled': isEnabled,
    };
  }

  SystemPrompt copyWith({
    String? id,
    String? name,
    String? content,
    DateTime? createdAt,
    bool? isEnabled,
  }) {
    return SystemPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
