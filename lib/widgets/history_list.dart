import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/chat_session.dart';
import '../services/chat_history_service.dart';
import '../services/session_provider.dart';
import '../services/notification_provider.dart';
import '../theme/theme.dart';

class HistoryList extends ConsumerStatefulWidget {
  final bool collapsed;
  const HistoryList({super.key, required this.collapsed});

  @override
  ConsumerState<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<HistoryList> {
  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionListProvider);
    final currentId = ref.watch(currentSessionIdProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => ref.read(rightSidebarCollapsedProvider.notifier).state = true,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
        if (!widget.collapsed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '历史记录',
              style: FTheme.of(context).typography.xs.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final isSelected = currentId == session.id;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: GestureDetector(
                  onSecondaryTapDown: (details) => _showSessionContextMenu(context, ref, session, details.globalPosition),
                  child: FSidebarItem(
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: widget.collapsed
                        ? const SizedBox.shrink()
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(Icons.edit_outlined, size: 12, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                                ),
                            ],
                          ),
                    selected: isSelected,
                    onPress: () {
                      ref.read(currentSessionIdProvider.notifier).setSessionId(session.id);
                    },
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
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
            leading: Icon(Icons.edit_outlined, size: 16),
            title: Text('重命名'),
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.download_rounded, size: 16),
            title: Text('导出 Markdown'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 16, color: Colors.red),
            title: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    ).then((value) {
      if (value == 'rename') {
        _showRenameDialog(context, ref, session);
      } else if (value == 'export') {
        _exportToMarkdown(context, ref, session);
      } else if (value == 'delete') {
        ref.read(sessionListProvider.notifier).deleteSession(session.id);
        if (ref.read(currentSessionIdProvider) == session.id) {
          ref.read(currentSessionIdProvider.notifier).setSessionId(null);
        }
      }
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

  void _exportToMarkdown(BuildContext context, WidgetRef ref, ChatSession session) async {
    final md = ref.read(chatHistoryServiceProvider).convertToMarkdown(session);
    final safeName = session.title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '保存聊天记录',
      fileName: '${safeName}.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (outputFile != null && context.mounted) {
      await File(outputFile).writeAsString(md);
      if (context.mounted) {
        ref.read(notificationServiceProvider).showSuccess('导出成功，已保存到: $outputFile');
      }
    }
  }
}