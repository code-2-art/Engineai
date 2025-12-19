import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import 'chat_history_service.dart';

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
}

final sessionListProvider = StateNotifierProvider<SessionNotifier, List<ChatSession>>((ref) {
  return SessionNotifier(ref.watch(chatHistoryServiceProvider));
});

final currentSessionIdProvider = StateProvider<String?>((ref) => null);

final currentSessionProvider = Provider<ChatSession?>((ref) {
  final id = ref.watch(currentSessionIdProvider);
  if (id == null) return null;
  final sessions = ref.watch(sessionListProvider);
  return sessions.firstWhere((s) => s.id == id, orElse: () => throw Exception('Session not found'));
});
