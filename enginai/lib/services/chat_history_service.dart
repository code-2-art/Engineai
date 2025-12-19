import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/chat_session.dart';

class ChatHistoryService {
  static const String _boxName = 'chat_history';
  static const String _key = 'sessions';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<List<ChatSession>> getSessions() async {
    try {
      final box = await _getBox();
      final List<dynamic>? jsonList = box.get(_key);

      if (jsonList != null) {
        return jsonList
            .map((item) => ChatSession.fromJson(json.decode(item as String)))
            .toList();
      }
    } catch (e) {
      print('ChatHistoryService: Error reading sessions: $e');
    }
    return [];
  }

  Future<void> saveSessions(List<ChatSession> sessions) async {
    try {
      final box = await _getBox();
      final jsonList = sessions.map((s) => json.encode(s.toJson())).toList();
      await box.put(_key, jsonList);
    } catch (e) {
      print('ChatHistoryService: Error saving sessions: $e');
    }
  }

  String convertToMarkdown(ChatSession session) {
    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln('Created at: ${session.createdAt}');
    buffer.writeln();

    for (final message in session.messages) {
      final role = message.sender ?? (message.isUser ? 'User' : 'AI');
      final timeStr = "${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}";
      buffer.writeln('### $role ($timeStr)');
      buffer.writeln(message.text);
      buffer.writeln();
    }

    return buffer.toString();
  }
}
