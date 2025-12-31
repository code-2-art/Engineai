import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/image_session.dart';
import '../models/image_message.dart';
import 'image_history_service.dart';
import 'shared_prefs_service.dart';

final imageHistoryServiceProvider = Provider((ref) => ImageHistoryService());

class ImageSessionNotifier extends StateNotifier<List<ImageSession>> {
  final ImageHistoryService _service;

  ImageSessionNotifier(this._service) : super([]) {
    // 异步加载会话，避免阻塞UI线程
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await _service.getSessions();
      state = sessions;
      print('ImageSessionNotifier: _loadSessions - 加载了 ${sessions.length} 个会话');
    } catch (e) {
      print('ImageSessionNotifier: Failed to load sessions: $e');
    }
  }

  Future<ImageSession> createNewSession() async {
    final session = ImageSession(
      id: const Uuid().v4(),
      title: '新图像会话',
      messages: [],
    );
    state = [session, ...state];
    await _service.saveSessions(state);
    return session;
  }

  Future<void> updateSession(ImageSession updatedSession) async {
    print('ImageSessionNotifier: updateSession - 会话ID: ${updatedSession.id}');
    print('ImageSessionNotifier: updateSession - 消息数量: ${updatedSession.messages.length}');
    for (int i = 0; i < updatedSession.messages.length; i++) {
      final msg = updatedSession.messages[i];
      print('ImageSessionNotifier: updateSession - 消息[$i] hasCached=${msg.hasCachedImageData}, cachedSize=${msg.cachedImageData?.length}');
    }
    state = [
      for (final session in state)
        if (session.id == updatedSession.id) updatedSession else session
    ];
    await _service.saveSessions(state);
    print('ImageSessionNotifier: updateSession - 更新完成，state消息数量: ${state.firstWhere((s) => s.id == updatedSession.id).messages.length}');
  }

  Future<void> updateSessionTitle(String id, String newTitle) async {
    state = [
      for (final session in state)
        if (session.id == id) session.copyWith(title: newTitle) else session
    ];
    await _service.saveSessions(state);
  }

  Future<void> addSeparator(String id) async {
    final index = state.indexWhere((s) => s.id == id);
    if (index != -1) {
      final separator = ImageMessage(
        prompt: '--- 上下文已清除 ---',
        timestamp: DateTime.now(),
        isSeparator: true,
      );
      final updated = state[index].copyWith(messages: [...state[index].messages, separator]);
      state = [...state.map((s) => s.id == id ? updated : s)];
      await _service.saveSessions(state);
    }
  }

  Future<void> deleteSession(String id) async {
    await _service.deleteSession(id);
    state = state.where((s) => s.id != id).toList();
  }

  Future<void> clearAll() async {
    await _service.clearAll();
    state = [];
  }
}

final imageSessionListProvider = StateNotifierProvider<ImageSessionNotifier, List<ImageSession>>((ref) {
  return ImageSessionNotifier(ref.watch(imageHistoryServiceProvider));
});

class CurrentImageSessionNotifier extends StateNotifier<String?> {
  final SharedPrefsService _prefsService;

  CurrentImageSessionNotifier(this._prefsService) : super(null) {
    _loadCurrentSessionId();
  }

  void _loadCurrentSessionId() {
    final sessionId = _prefsService.getCurrentImageSessionId();
    print('CurrentImageSessionNotifier: _loadCurrentSessionId - 加载的会话ID: $sessionId');
    state = sessionId;
  }

  Future<void> setSessionId(String? sessionId) async {
    state = sessionId;
    await _prefsService.saveCurrentImageSessionId(sessionId);
  }
}

final currentImageSessionIdProvider = StateNotifierProvider<CurrentImageSessionNotifier, String?>((ref) {
  return CurrentImageSessionNotifier(ref.watch(sharedPrefsServiceProvider));
});

final currentImageSessionProvider = Provider<ImageSession?>((ref) {
  final id = ref.watch(currentImageSessionIdProvider);
  if (id == null) return null;
  final sessions = ref.watch(imageSessionListProvider);
  for (final session in sessions) {
    if (session.id == id) {
      return session;
    }
  }
  return null;
});