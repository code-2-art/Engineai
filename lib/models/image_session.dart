import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'image_message.dart';

class ImageSession {
  final String id;
  final String title;
  final List<ImageMessage> messages;
  final DateTime createdAt;

  ImageSession({
    required this.id,
    required this.title,
    required this.messages,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ImageSession.fromJson(Map<String, dynamic> json) {
    return ImageSession(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List<dynamic>)
          .map((m) => ImageMessage.fromJson(m as Map<String, dynamic>))
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

  ImageSession copyWith({
    String? id,
    String? title,
    List<ImageMessage>? messages,
    DateTime? createdAt,
  }) {
    return ImageSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}