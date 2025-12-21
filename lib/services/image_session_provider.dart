import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/image_session.dart';
import 'image_history_service.dart';
import 'shared_prefs_service.dart';

final imageHistoryServiceProvider = Provider((ref) => ImageHistoryService());

class ImageSessionNotifier extends StateNotifier<List<ImageSession>> {
  final ImageHistoryService _service;

  ImageSessionNotifier(this._service) : super([]) {
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    state = await _service.getSessions();
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
    state = [
      for (final session in state)
        if (session.id == updatedSession.id) updatedSession else session
    ];
    await _service.saveSessions(state);
  }

  Future<void> updateSessionTitle(String id, String newTitle) async {
    state = [
      for (final session in state)
        if (session.id == id) session.copyWith(title: newTitle) else session
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
    state = _prefsService.getCurrentImageSessionId();
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