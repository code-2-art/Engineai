import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/chat_session.dart';

class ChatHistoryService {
  static const String _boxName = 'chat_history';
  static const String _key = 'sessions';
  
  Box? _cachedBox;

  Future<Box> _getBox() async {
    if (_cachedBox != null && _cachedBox!.isOpen) {
      return _cachedBox!;
    }
    if (!Hive.isBoxOpen(_boxName)) {
      _cachedBox = await Hive.openBox(_boxName);
    } else {
      _cachedBox = Hive.box(_boxName);
    }
    return _cachedBox!;
  }
  
  /// 清理资源，关闭 Hive box
  Future<void> dispose() async {
    try {
      if (_cachedBox != null && _cachedBox!.isOpen) {
        await _cachedBox!.close();
        _cachedBox = null;
        print('ChatHistoryService: Box closed');
      }
    } catch (e) {
      print('ChatHistoryService: Error closing box: $e');
    }
  }

  Future<List<ChatSession>> getSessions() async {
    print('=== CHAT HISTORY GET SESSIONS START ===');
    try {
      final box = await _getBox();
      final List<dynamic>? jsonList = box.get(_key);

      if (jsonList != null) {
        List<ChatSession> sessions = jsonList
            .map((item) => ChatSession.fromJson(json.decode(item as String)))
            .toList();
        sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        print('=== CHAT HISTORY GET SESSIONS DONE: ${sessions.length} sessions (all loaded) ===');
        return sessions;
      }
    } catch (e) {
      print('ChatHistoryService: Error reading sessions: $e');
    }
    print('=== CHAT HISTORY GET SESSIONS DONE: 0 sessions ===');
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

  static const String _summariesKey = 'history_summaries';

  Future<List<SessionSummary>> getSummaries() async {
    print('=== CHAT HISTORY GET SUMMARIES START ===');
    try {
      final box = await _getBox();
      final List<dynamic>? jsonList = box.get(_summariesKey);

      if (jsonList != null) {
        final summaries = jsonList.map((item) => SessionSummary.fromJson(item as Map<String, dynamic>)).toList();
        print('=== CHAT HISTORY GET SUMMARIES DONE: ${summaries.length} ===');
        return summaries;
      }
    } catch (e) {
      print('ChatHistoryService: Error reading summaries: $e');
    }
    print('=== CHAT HISTORY GET SUMMARIES DONE: 0 ===');
    return [];
  }

  Future<void> saveSummaries(List<SessionSummary> summaries) async {
    try {
      final jsonList = summaries.map((s) => s.toJson()).toList();
      final box = await _getBox();
      await box.put(_summariesKey, jsonList);
    } catch (e) {
      print('ChatHistoryService: Error saving summaries: $e');
    }
  }

  Future<ChatSession?> getSessionById(String id) async {
    print('=== CHAT HISTORY GET SESSION BY ID $id START ===');
    try {
      final box = await _getBox();
      final jsonString = box.get(id);
      if (jsonString != null) {
        final session = ChatSession.fromJson(json.decode(jsonString as String));
        print('=== CHAT HISTORY GET SESSION BY ID $id DONE ===');
        return session;
      }
    } catch (e) {
      print('ChatHistoryService: Error reading session $id: $e');
    }
    print('=== CHAT HISTORY GET SESSION BY ID $id NOT FOUND ===');
    return null;
  }

  Future<void> saveSession(ChatSession session) async {
    print('=== CHAT HISTORY SAVE SESSION ${session.id} START ===');
    try {
      final jsonString = json.encode(session.toJson());
      final box = await _getBox();
      await box.put(session.id, jsonString);
      print('=== CHAT HISTORY SAVE SESSION ${session.id} DONE ===');
    } catch (e) {
      print('ChatHistoryService: Error saving session ${session.id}: $e');
    }
  }

  String convertToMarkdown(ChatSession session) {
    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln('Created at: ${session.createdAt}');
    if (session.systemPrompt != null && session.systemPrompt!.isNotEmpty) {
      buffer.writeln('System Prompt: ${session.systemPrompt}');
    }
    buffer.writeln();

    for (final message in session.messages) {
      if (message.isSystem) {
        buffer.writeln('---');
        buffer.writeln('**${message.text}**');
        buffer.writeln('---');
        buffer.writeln();
        continue;
      }
      final role = message.sender ?? (message.isUser ? 'User' : 'AI');
      final timeStr = "${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}";
      buffer.writeln('### $role ($timeStr)');
      buffer.writeln(message.text);
      buffer.writeln();
    }

    return buffer.toString();
  }
}
