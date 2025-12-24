import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'pages/ai_chat.dart';
import 'pages/settings_page.dart';
import 'pages/image_page.dart';
import 'pages/writing_page.dart';
import 'services/llm_provider.dart';
import 'services/session_provider.dart';
import 'models/chat_session.dart';
import 'theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/shared_prefs_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'services/chat_history_service.dart';
import 'widgets/history_list.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  
  // Pre-warm the configuration and LLM provider
  unawaited(container.read(configProvider.future));
  unawaited(container.read(chatLlmProvider.future));

  runApp(
    UncontrolledProviderScope(
      container: container,
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
      theme: theme.toApproximateMaterialTheme().copyWith(
        textTheme: theme.toApproximateMaterialTheme().textTheme.apply(
          fontSizeFactor: 0.875,
          fontFamilyFallback: const ['Microsoft YaHei', 'SimSun', 'PingFang SC', 'Hiragino Sans GB', 'Noto Sans CJK SC', 'Arial Unicode MS'],
        ),
      ),
      builder: (_, child) => FAnimatedTheme(data: theme, child: child!),
      // You can also replace FScaffold with Material Scaffold.
      home: FScaffold(
        child: Consumer(
          builder: (context, ref, child) {
            final rightCollapsed = ref.watch(rightSidebarCollapsedProvider);
            final theme = FTheme.of(context);
            final materialTheme = Theme.of(context);

            return Stack(
              children: [
                Row(
                  children: [
                    // 左侧纯图标栏，固定宽度36，紧凑精致样式
                    Container(
                      width: 36,
                      decoration: BoxDecoration(
                        color: materialTheme.colorScheme.surface,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Padding(
                            padding: EdgeInsets.zero,
                            child: IconButton(
                              icon: const Icon(Icons.chat_bubble_outline, size: 18),
                              onPressed: () {
                                ref.read(currentPageProvider.notifier).state = 'chat';
                              },
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.zero,
                            child: IconButton(
                              icon: const Icon(Icons.image_outlined, size: 18),
                              onPressed: () {
                                ref.read(currentPageProvider.notifier).state = 'image';
                              },
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.zero,
                            child: IconButton(
                              icon: const Icon(Icons.edit_note_outlined, size: 18),
                              onPressed: () {
                                ref.read(currentPageProvider.notifier).state = 'writing';
                              },
                            ),
                          ),
                          const Spacer(), // 预留中间空间
                          Padding(
                            padding: EdgeInsets.zero,
                            child: IconButton(
                              icon: const Icon(Icons.settings_outlined, size: 18),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const SettingsPage(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    // 中间聊天区域
                    const FDivider(axis: Axis.vertical),
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, child) {
                          final page = ref.watch(currentPageProvider);
                          final rightCollapsed = ref.watch(rightSidebarCollapsedProvider);
                          Widget pageWidget = const SizedBox.shrink();
                          if (page == 'chat') {
                            pageWidget = const AiChat();
                          } else if (page == 'image') {
                            pageWidget = const ImagePage();
                          } else if (page == 'writing') {
                            pageWidget = const WritingPage();
                          }
                          return GestureDetector(
                            onTap: () {
                              if (!rightCollapsed) {
                                ref.read(rightSidebarCollapsedProvider.notifier).state = true;
                              }
                            },
                            child: pageWidget,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  right: rightCollapsed ? -280.0 : 0.0,
                  top: 0,
                  bottom: 0,
                  width: 280,
                  child: Container(
                    decoration: BoxDecoration(
                      color: materialTheme.colorScheme.surfaceVariant,
                    ),
                    child: HistoryList(collapsed: false),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}