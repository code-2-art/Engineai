import 'package:uuid/uuid.dart';

class SystemPrompt {
  final String id;
  final String name;
  final String content;
  final DateTime createdAt;
  final bool isEnabled;
  final bool isBuiltin;
  final String? path;

  SystemPrompt({
    String? id,
    required this.name,
    required this.content,
    DateTime? createdAt,
    this.isEnabled = true,
    this.isBuiltin = false,
    this.path,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    return SystemPrompt(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isEnabled: json['isEnabled'] as bool? ?? true,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      path: json['path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'isEnabled': isEnabled,
      'isBuiltin': isBuiltin,
      'path': path,
    };
  }

  /// Export to Markdown format with YAML frontmatter
  String toMarkdown() {
    return '''---
name: $name
created: ${createdAt.toIso8601String()}
enabled: $isEnabled
---

$content''';
  }

  /// Import from Markdown format with YAML frontmatter
  factory SystemPrompt.fromMarkdown(String markdown) {
    // Parse frontmatter and content
    final lines = markdown.split('\n');
    
    if (lines.isEmpty || lines[0] != '---') {
      // No frontmatter, treat entire content as prompt
      return SystemPrompt(
        name: 'Imported Prompt',
        content: markdown.trim(),
      );
    }

    // Find end of frontmatter
    int endIndex = -1;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i] == '---') {
        endIndex = i;
        break;
      }
    }

    if (endIndex == -1) {
      // Invalid frontmatter, treat as plain content
      return SystemPrompt(
        name: 'Imported Prompt',
        content: markdown.trim(),
      );
    }

    // Parse frontmatter
    String name = 'Imported Prompt';
    DateTime? createdAt;
    bool isEnabled = true;

    for (int i = 1; i < endIndex; i++) {
      final line = lines[i].trim();
      if (line.startsWith('name:')) {
        name = line.substring(5).trim();
      } else if (line.startsWith('created:')) {
        try {
          createdAt = DateTime.parse(line.substring(8).trim());
        } catch (_) {}
      } else if (line.startsWith('enabled:')) {
        isEnabled = line.substring(8).trim().toLowerCase() == 'true';
      }
    }

    // Get content after frontmatter
    final content = lines.sublist(endIndex + 1).join('\n').trim();

    return SystemPrompt(
      name: name,
      content: content,
      createdAt: createdAt,
      isEnabled: isEnabled,
    );
  }

  SystemPrompt copyWith({
    String? id,
    String? name,
    String? content,
    DateTime? createdAt,
    bool? isEnabled,
    bool? isBuiltin,
    String? path,
  }) {
    return SystemPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isEnabled: isEnabled ?? this.isEnabled,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      path: path ?? this.path,
    );
  }
}
