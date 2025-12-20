import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../services/shared_prefs_service.dart';

final List<FThemeData> availableThemes = [
  FThemes.zinc.light,
  FThemes.zinc.dark,
  FThemes.slate.light,
  FThemes.slate.dark,
  FThemes.violet.light,
  FThemes.violet.dark,
];

final List<String> themeNames = [
  'Zinc Light',
  'Zinc Dark',
  'Slate Light',
  'Slate Dark',
  'Violet Light',
  'Violet Dark',
];

class ThemeNotifier extends Notifier<int> {
  static const _key = 'theme_index';

  @override
  int build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getInt(_key) ?? 1; // Default to Zinc Dark (index 1)
  }

  void set(int index) {
    if (index >= 0 && index < availableThemes.length) {
      state = index;
      ref.read(sharedPreferencesProvider).setInt(_key, index);
    }
  }
}

final currentThemeIndexProvider = NotifierProvider<ThemeNotifier, int>(ThemeNotifier.new);

class SidebarNotifier extends Notifier<bool> {
  static const _key = 'sidebar_collapsed';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_key) ?? false;
  }

  void toggle() {
    state = !state;
    ref.read(sharedPreferencesProvider).setBool(_key, state);
  }

  void set(bool value) {
    state = value;
    ref.read(sharedPreferencesProvider).setBool(_key, state);
  }
}

final sidebarCollapsedProvider = NotifierProvider<SidebarNotifier, bool>(SidebarNotifier.new);

class RightSidebarNotifier extends Notifier<bool> {
  @override
  bool build() => true; // 默认隐藏右侧栏，不存储状态

  void toggle() {
    state = !state;
  }
}

final rightSidebarCollapsedProvider = NotifierProvider<RightSidebarNotifier, bool>(RightSidebarNotifier.new);