import 'dart:convert';

class Message {
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final String? sender;

  Message({
    required this.isUser,
    required this.text,
    DateTime? timestamp,
    this.sender,
  }) : timestamp = timestamp ?? DateTime.now();

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      isUser: json['isUser'] as bool,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sender: json['sender'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isUser': isUser,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'sender': sender,
    };
  }
}

class ChatSession {
  final String id;
  final String title;
  final List<Message> messages;
  final DateTime createdAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
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
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  ChatSession copyWith({
    String? id,
    String? title,
    List<Message>? messages,
    DateTime? createdAt,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
