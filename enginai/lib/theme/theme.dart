import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

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

final currentThemeIndexProvider = StateProvider<int>((ref) => 1);