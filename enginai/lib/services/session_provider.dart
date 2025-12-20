import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import 'chat_history_service.dart';
import 'shared_prefs_service.dart';

final chatHistoryServiceProvider = Provider((ref) => ChatHistoryService());

class SessionNotifier extends StateNotifier<List<ChatSession>> {
  final ChatHistoryService _service;

  SessionNotifier(this._service) : super([]) {
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    state = await _service.getSessions();
  }

  Future<ChatSession> createNewSession() async {
    final session = ChatSession(
      id: const Uuid().v4(),
      title: '新对话',
      messages: [],
    );
    state = [session, ...state];
    await _service.saveSessions(state);
    return session;
  }

  Future<void> updateSession(ChatSession updatedSession) async {
    state = [
      for (final session in state)
        if (session.id == updatedSession.id) updatedSession else session
    ];
    await _service.saveSessions(state);
  }

  Future<void> addSeparator(String id) async {
    final index = state.indexWhere((s) => s.id == id);
    if (index != -1) {
      final updated = state[index].copyWith(
        messages: [...state[index].messages, Message(isUser: false, text: '--- 上下文已清除 ---', isSystem: true)]
      );
      state = [...state.map((s) => s.id == id ? updated : s)];
      await _service.saveSessions(state);
    }
  }

  Future<void> deleteMessage(String sessionId, String messageId) async {
    final sessionIndex = state.indexWhere((s) => s.id == sessionId);
    if (sessionIndex != -1) {
      final updatedMessages = state[sessionIndex].messages.where((m) => m.id != messageId).toList();
      final updatedSession = state[sessionIndex].copyWith(messages: updatedMessages);
      state = [
        for (final session in state)
          if (session.id == sessionId) updatedSession else session
      ];
      await _service.saveSessions(state);
    }
  }

  Future<void> deleteSession(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _service.saveSessions(state);
  }

  Future<void> clearAll() async {
    state = [];
    await _service.saveSessions(state);
  }
  
  void updateSessionTitle(String id, String newTitle) {
    state = [
      for (final session in state)
        if (session.id == id) session.copyWith(title: newTitle) else session
    ];
    _service.saveSessions(state);
  }

  void updateSessionSystemPrompt(String id, String? systemPrompt) {
    state = [
      for (final session in state)
        if (session.id == id) session.copyWith(systemPrompt: systemPrompt) else session
    ];
    _service.saveSessions(state);
  }
}

final sessionListProvider = StateNotifierProvider<SessionNotifier, List<ChatSession>>((ref) {
  return SessionNotifier(ref.watch(chatHistoryServiceProvider));
});

class CurrentSessionNotifier extends StateNotifier<String?> {
  final SharedPrefsService _prefsService;

  CurrentSessionNotifier(this._prefsService) : super(null) {
    _loadCurrentSessionId();
  }

  void _loadCurrentSessionId() {
    state = _prefsService.getCurrentSessionId();
  }

  Future<void> setSessionId(String? sessionId) async {
    state = sessionId;
    await _prefsService.saveCurrentSessionId(sessionId);
  }
}

final currentSessionIdProvider = StateNotifierProvider<CurrentSessionNotifier, String?>((ref) {
  return CurrentSessionNotifier(ref.watch(sharedPrefsServiceProvider));
});

final currentSessionProvider = Provider<ChatSession?>((ref) {
  final id = ref.watch(currentSessionIdProvider);
  if (id == null) return null;
  final sessions = ref.watch(sessionListProvider);
  return sessions.firstWhere((s) => s.id == id, orElse: () => throw Exception('Session not found'));
});
