import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'pages/ai_chat.dart';
import 'pages/settings_page.dart';
import 'services/llm_provider.dart';
import 'theme/theme.dart';
 
import 'package:shared_preferences/shared_preferences.dart';
import 'services/shared_prefs_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const Application(),
    ),
  );
}
 
class Application extends ConsumerWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    /// Try changing this and hot reloading the application.
    ///
    /// To create a custom theme:
    /// ```shell
    /// dart forui theme create [theme template].
    /// ```
    final index = ref.watch(currentThemeIndexProvider);
    final theme = availableThemes[index];
 
    return MaterialApp(
      // TODO: replace with your application's supported locales.
      supportedLocales: FLocalizations.supportedLocales,
      // TODO: add your application's localizations delegates.
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      // MaterialApp's theme is also animated by default with the same duration and curve.
      // See https://api.flutter.dev/flutter/material/MaterialApp/themeAnimationStyle.html for how to configure this.
      //
      // There is a known issue with implicitly animated widgets where their transition occurs AFTER the theme's.
      // See https://github.com/forus-labs/forui/issues/670.
      theme: theme.toApproximateMaterialTheme(),
      builder: (_, child) => FAnimatedTheme(data: theme, child: child!),
      // You can also replace FScaffold with Material Scaffold.
      home: FScaffold(
        sidebar: Consumer(
          builder: (context, ref, child) {
            final collapsed = ref.watch(sidebarCollapsedProvider);
            if (collapsed) {
              return const SizedBox.shrink();
            }
            return FSidebar(
              header: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(
                        '设置',
                        style: FTheme.of(context).typography.sm.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    FDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '主题: ',
                            style: FTheme.of(context).typography.sm,
                          ),
                          Material(
                            color: Colors.transparent,
                            child: DropdownButton<int>(
                              value: ref.watch(currentThemeIndexProvider),
                              items: themeNames.asMap().entries.map((entry) {
                                return DropdownMenuItem<int>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                );
                              }).toList(),
                              onChanged: (int? value) {
                                if (value != null) {
                                  ref.read(currentThemeIndexProvider.notifier).set(value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '模型: ',
                            style: FTheme.of(context).typography.sm,
                          ),
                          Material(
                            color: Colors.transparent,
                            child: ref.watch(modelNamesProvider).when(
                              data: (names) {
                                var current = ref.watch(currentModelProvider);
                                if (!names.contains(current)) {
                                  if (names.isNotEmpty) {
                                    current = names.first;
                                    // Ensure state is updated to valid value
                                    Future.microtask(() => 
                                      ref.read(currentModelProvider.notifier).state = current
                                    );
                                  } else {
                                    return const Text('无模型');
                                  }
                                }
                                return DropdownButton<String>(
                                  value: current,
                                  items: names.map((name) => DropdownMenuItem<String>(
                                    value: name,
                                    child: Text(name),
                                  )).toList(),
                                  onChanged: (String? value) {
                                    if (value != null) {
                                      ref.read(configProvider.notifier).updateDefaultModel(value);
                                    }
                                  },
                                );
                              },
                              loading: () => const Text('加载中...'),
                              error: (error, stack) => Text('错误: $error'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              children: [
                FSidebarItem(
                  icon: const Icon(Icons.settings, size: 20),
                  label: const Text('管理模型'),
                  onPress: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
        child: const AiChat(),
      ),
    );
  }
}