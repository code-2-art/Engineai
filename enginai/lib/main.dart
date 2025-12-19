import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'pages/ai_chat.dart';
import 'pages/settings_page.dart';
import 'services/llm_provider.dart';
import 'services/session_provider.dart';
import 'models/chat_session.dart';
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
            final theme = FTheme.of(context);
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: collapsed ? 72 : 260,
              child: FSidebar(
                header: Column(
                  children: [
                    const SizedBox(height: 12),
                    Icon(
                      Icons.bolt_rounded,
                      size: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    if (!collapsed) ...[
                      const SizedBox(height: 8),
                      Text(
                        'EngineAI',
                        style: theme.typography.lg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FDivider(),
                  ],
                ),
                children: [
                  FSidebarItem(
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    label: collapsed ? const SizedBox.shrink() : const Text('新对话'),
                    onPress: () async {
                      final session = await ref.read(sessionListProvider.notifier).createNewSession();
                      ref.read(currentSessionIdProvider.notifier).state = session.id;
                    },
                  ),
                  const SizedBox(height: 8),
                  if (!collapsed) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        '历史记录',
                        style: theme.typography.xs.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  ...ref.watch(sessionListProvider).map((session) {
                    final isSelected = ref.watch(currentSessionIdProvider) == session.id;
                    return GestureDetector(
                      onSecondaryTapDown: (details) => _showSessionContextMenu(context, ref, session, details.globalPosition),
                      child: FSidebarItem(
                        icon: const Icon(Icons.chat_bubble_outline, size: 20),
                        label: collapsed ? const SizedBox.shrink() : Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelected)
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 14),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showRenameDialog(context, ref, session),
                              ),
                          ],
                        ),
                        selected: isSelected,
                        onPress: () {
                          ref.read(currentSessionIdProvider.notifier).state = session.id;
                        },
                      ),
                    );
                  }),
                  // Removed Spacer() as it causes ParentDataWidget error in FSidebar
                  const SizedBox(height: 16),
                  FSidebarItem(
                    icon: const Icon(Icons.palette_outlined, size: 22),
                    label: collapsed ? const SizedBox.shrink() : const Text('外观设置'),
                    onPress: () => _showThemeDialog(context, ref),
                  ),
                  FSidebarItem(
                    icon: const Icon(Icons.smart_toy_outlined, size: 22),
                    label: collapsed ? const SizedBox.shrink() : const Text('切换模型'),
                    onPress: () => _showModelDialog(context, ref),
                  ),
                  FSidebarItem(
                    icon: const Icon(Icons.settings_outlined, size: 22),
                    label: collapsed ? const SizedBox.shrink() : const Text('管理模型'),
                    onPress: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
        child: const AiChat(),
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: themeNames.asMap().entries.map((entry) {
              return ListTile(
                title: Text(entry.value),
                onTap: () {
                  ref.read(currentThemeIndexProvider.notifier).set(entry.key);
                  Navigator.pop(context);
                },
                trailing: ref.watch(currentThemeIndexProvider) == entry.key
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showModelDialog(BuildContext context, WidgetRef ref) {
    ref.read(modelNamesProvider).whenData((names) {
      showDialog(
        context: context,
        builder: (context) {
          final current = ref.watch(currentModelProvider);
          return AlertDialog(
            title: const Text('切换模型'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: names.isEmpty
                    ? [const Text('无可用模型')]
                    : names.map((name) {
                        return ListTile(
                          title: Text(name),
                          onTap: () {
                            ref.read(configProvider.notifier).updateDefaultModel(name);
                            Navigator.pop(context);
                          },
                          trailing: current == name
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                        );
                      }).toList(),
              ),
            ),
          );
        },
      );
    });
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入新名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                ref.read(sessionListProvider.notifier).updateSessionTitle(session.id, newTitle);
              }
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showSessionContextMenu(BuildContext context, WidgetRef ref, ChatSession session, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined, size: 20),
            title: Text('重命名'),
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 20, color: Colors.red),
            title: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    ).then((value) {
      if (value == 'rename') {
        _showRenameDialog(context, ref, session);
      } else if (value == 'delete') {
        ref.read(sessionListProvider.notifier).deleteSession(session.id);
        if (ref.read(currentSessionIdProvider) == session.id) {
          ref.read(currentSessionIdProvider.notifier).state = null;
        }
      }
    });
  }
}