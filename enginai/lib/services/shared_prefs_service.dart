import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This provider will be overridden in main.dart with the initialized instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

class SharedPrefsService {
  static const String _currentSessionIdKey = 'current_session_id';

  final SharedPreferences _prefs;

  SharedPrefsService(this._prefs);

  Future<void> saveCurrentSessionId(String? sessionId) async {
    if (sessionId == null) {
      await _prefs.remove(_currentSessionIdKey);
    } else {
      await _prefs.setString(_currentSessionIdKey, sessionId);
    }
  }

  String? getCurrentSessionId() {
    return _prefs.getString(_currentSessionIdKey);
  }
}

final sharedPrefsServiceProvider = Provider<SharedPrefsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SharedPrefsService(prefs);
});
