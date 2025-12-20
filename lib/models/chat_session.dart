import 'dart:convert';
import 'package:uuid/uuid.dart';

class Message {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final String? sender;
  final bool isSystem;

  Message({
    String? id,
    required this.isUser,
    required this.text,
    DateTime? timestamp,
    this.sender,
    this.isSystem = false,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String? ?? const Uuid().v4(),
      isUser: json['isUser'] as bool,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sender: json['sender'] as String?,
      isSystem: (json['isSystem'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isUser': isUser,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'sender': sender,
      'isSystem': isSystem,
    };
  }
}

class ChatSession {
  final String id;
  final String title;
  final String? systemPrompt;
  final List<Message> messages;
  final DateTime createdAt;

  ChatSession({
    required this.id,
    required this.title,
    this.systemPrompt,
    required this.messages,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
      systemPrompt: json['systemPrompt'] as String?,
      messages: (json['messages'] as List<dynamic>)
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'systemPrompt': systemPrompt,
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  ChatSession copyWith({
    String? id,
    String? title,
    String? systemPrompt,
    List<Message>? messages,
    DateTime? createdAt,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
