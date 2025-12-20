import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../theme/theme.dart';
import '../services/llm_provider.dart';
import '../models/chat_session.dart';
import '../services/session_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'settings_page.dart';
import '../models/system_prompt.dart';

final currentResponseProvider = StateProvider<String>((ref) => '');

class AiChat extends ConsumerStatefulWidget {
  const AiChat({super.key});

  @override
  ConsumerState<AiChat> createState() => _AiChatState();
}

class _AiChatState extends ConsumerState<AiChat> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _isSending) return;

    print('AiChat: _sendMessage started. Prompt: $prompt');
    // We don't lock immediately to allow retries during long provider initialization
    // if the user clicks again. We will lock just before the stream starts.

    try {
      var sessionId = ref.read(currentSessionIdProvider);
      print('AiChat: current sessionId: $sessionId');
    if (sessionId == null) {
      print('AiChat: Creating new session...');
      final newSession = await ref.read(sessionListProvider.notifier).createNewSession();
      sessionId = newSession.id;
      ref.read(currentSessionIdProvider.notifier).setSessionId(sessionId);
      print('AiChat: New session created: $sessionId');
    }

    final currentSession = ref.read(sessionListProvider).firstWhere((s) => s.id == sessionId);
    
    final currentModel = ref.read(currentModelProvider);
    final userMessage = Message(isUser: true, text: prompt, sender: '我');
    final updatedMessages = [...currentSession.messages, userMessage];
    
    String title = currentSession.title;
    if (currentSession.messages.isEmpty) {
      final now = DateTime.now();
      final timestamp = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final shortPrompt = prompt.length > 20 ? '${prompt.substring(0, 20)}...' : prompt;
      title = '$timestamp - $shortPrompt';
    }

    await ref.read(sessionListProvider.notifier).updateSession(
      currentSession.copyWith(messages: updatedMessages, title: title)
    );

    _controller.clear();
    _scrollToBottom();

    ref.read(currentResponseProvider.notifier).state = '';

    print('AiChat: Fetching LLM provider...');
    final llmFuture = ref.read(llmProvider.future);
    final llm = await llmFuture;
    print('AiChat: LLM provider ready.');

    if (mounted) {
      setState(() {
        _isSending = true;
      });
    }
    
    // Pass currentSession.messages (the history BEFORE the new user message) 
    // because generateStream adds the prompt itself.
    // Prune history based on separators
    final fullHistory = currentSession.messages;
    final lastClearIndex = fullHistory.lastIndexWhere((m) => m.isSystem);
    final effectiveHistory = lastClearIndex == -1 
        ? fullHistory 
        : fullHistory.sublist(lastClearIndex + 1);

    print('AiChat: Starting stream with ${effectiveHistory.length} messages in history...');
    final stream = llm.generateStream(effectiveHistory, prompt, systemPrompt: currentSession.systemPrompt);

    await for (final delta in stream) {
      if (delta.isEmpty) continue;
      final current = ref.read(currentResponseProvider);
      ref.read(currentResponseProvider.notifier).state = current + delta;
      _scrollToBottom();
    }
    print('AiChat: Stream finished.');

    final fullResponse = ref.read(currentResponseProvider);
    if (fullResponse.isNotEmpty) {
      final currentModel = ref.read(currentModelProvider);
      final aiMessage = Message(isUser: false, text: fullResponse, sender: currentModel);
      final sessionAfterStream = ref.read(sessionListProvider).firstWhere((s) => s.id == sessionId);
      await ref.read(sessionListProvider.notifier).updateSession(
        sessionAfterStream.copyWith(messages: [...sessionAfterStream.messages, aiMessage])
      );
      ref.read(currentResponseProvider.notifier).state = '';
      _scrollToBottom();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    }
    // Reset state on error so user can try again
    ref.read(currentResponseProvider.notifier).state = '';
  } finally {
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }
}

  Future<void> _exportToMarkdown() async {
    final sessionId = ref.read(currentSessionIdProvider);
    if (sessionId == null) return;
    final session = ref.read(sessionListProvider).firstWhere((s) => s.id == sessionId);
    if (session.messages.isEmpty) return;

    final md = ref.read(chatHistoryServiceProvider).convertToMarkdown(session);
    
    if (kIsWeb || !Platform.isMacOS) {
      // Fallback to share for web or other mobile/non-desktop platforms
      await Share.share(md, subject: '${session.title}.md');
    } else {
      // Direct save for Desktop
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '请选择保存位置',
        fileName: '${session.title}.md',
        type: FileType.any,
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(md);
        // Using a basic feedback mechanism
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('导出成功'),
              content: Text('已保存到: ${file.path}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final sessionId = ref.watch(currentSessionIdProvider);
    final currentResponse = ref.watch(currentResponseProvider);
    final sessions = ref.watch(sessionListProvider);
    
    final currentSession = sessionId != null 
        ? sessions.firstWhere((s) => s.id == sessionId, orElse: () => sessions.isNotEmpty ? sessions.first : ChatSession(id: '', title: '', messages: []))
        : null;
    final history = currentSession?.messages ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Spacer(),
                Consumer(
                  builder: (context, ref, child) {
                    final collapsed = ref.watch(rightSidebarCollapsedProvider);
                    if (collapsed) {
                      return IconButton(
                        onPressed: () {
                          ref.read(rightSidebarCollapsedProvider.notifier).toggle();
                        },
                        icon: const Icon(Icons.history, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: (currentSession == null && currentResponse.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text('开始新的对话吧', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: history.length + (currentResponse.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < history.length) {
                        final message = history[index];
                        if (message.isSystem) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(child: Divider(color: Theme.of(context).colorScheme.primary.withOpacity(0.2))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    '上下文已清除',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: Theme.of(context).colorScheme.primary.withOpacity(0.2))),
                              ],
                            ),
                          );
                        }
                        final timeStr = "${message.timestamp.year}-${message.timestamp.month.toString().padLeft(2, '0')}-${message.timestamp.day.toString().padLeft(2, '0')} ${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}";
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          child: Column(
                            crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                                child: Text(
                                  "${message.sender ?? (message.isUser ? '我' : 'AI')} • $timeStr",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: message.isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: MarkdownBody(
                                          data: message.text,
                                          styleSheet: MarkdownStyleSheet(
                                            p: TextStyle(
                                              fontSize: 16,
                                              color: message.isUser ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSecondaryContainer,
                                              fontFamilyFallback: const ['Microsoft YaHei', 'SimSun', 'PingFang SC', 'Hiragino Sans GB', 'Noto Sans CJK SC', 'Arial Unicode MS'],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.copy_rounded, size: 14),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: message.text));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('已复制到剪贴板'), behavior: SnackBarBehavior.floating, width: 200),
                                              );
                                            },
                                            tooltip: '复制',
                                            style: IconButton.styleFrom(
                                              foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 14),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              if (sessionId != null) {
                                                ref.read(sessionListProvider.notifier).deleteMessage(sessionId, message.id);
                                              }
                                            },
                                            tooltip: '删除',
                                            style: IconButton.styleFrom(
                                              foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        final currentModel = ref.watch(currentModelProvider);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4, left: 4),
                                child: Text(
                                  "$currentModel • 正在输入...",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                                  ),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: MarkdownBody(
                                    data: currentResponse.isEmpty ? 'AI 正在思考...' : currentResponse,
                                    styleSheet: MarkdownStyleSheet(
                                      p: TextStyle(
                                        fontSize: 16,
                                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                                        fontFamilyFallback: const ['Microsoft YaHei', 'SimSun', 'PingFang SC', 'Hiragino Sans GB', 'Noto Sans CJK SC', 'Arial Unicode MS'],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
          ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSending,
                    decoration: InputDecoration(
                      hintText: _isSending ? 'AI 正在回复...' : '输入消息...',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Consumer(
                              builder: (context, ref, child) {
                                final sessionId = ref.watch(currentSessionIdProvider);
                                final sessions = ref.watch(sessionListProvider);
                                ChatSession? currentSession;
                                if (sessionId != null) {
                                  try {
                                    currentSession = sessions.firstWhere((s) => s.id == sessionId);
                                  } catch (e) {
                                    currentSession = null;
                                  }
                                }
                                final hasPrompt = currentSession?.systemPrompt != null;
                                final currentPrompt = currentSession?.systemPrompt;
                                final promptsAsync = ref.watch(enabledSystemPromptsProvider);
                                return promptsAsync.when(
                                  data: (prompts) {
                                    return FPopoverMenu(
                                      menuAnchor: Alignment.topCenter,
                                      childAnchor: Alignment.bottomCenter,
                                      menu: [
                                        FItemGroup(
                                          children: [
                                            FItem(title: const Text('不使用系统提示词'), suffix: currentPrompt == null ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null, onPress: () async {
                                                var sid = ref.read(currentSessionIdProvider);
                                                if (sid == null) {
                                                  final session = await ref.read(sessionListProvider.notifier).createNewSession();
                                                  sid = session.id;
                                                  ref.read(currentSessionIdProvider.notifier).setSessionId(sid);
                                                }
                                                ref.read(sessionListProvider.notifier).updateSessionSystemPrompt(sid, null);
                                              },
                                            ),
                                            ...prompts.map((p) => FItem(
                                              title: Text(p.name), subtitle: Text(p.content, maxLines: 1, overflow: TextOverflow.ellipsis), suffix: currentPrompt == p.content ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null, onPress: () async {
                                                var sid = ref.read(currentSessionIdProvider);
                                                if (sid == null) {
                                                  final session = await ref.read(sessionListProvider.notifier).createNewSession();
                                                  sid = session.id;
                                                  ref.read(currentSessionIdProvider.notifier).setSessionId(sid);
                                                }
                                                ref.read(sessionListProvider.notifier).updateSessionSystemPrompt(sid, p.content);
                                              },
                                            )),
                                            FItem(
                                              prefix: const Icon(Icons.edit),
                                              title: const Text('管理提示词'),
                                              onPress: () {
                                                ref.read(selectedSectionProvider.notifier).state = SettingsSection.prompts;
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) => const SettingsPage(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                      builder: (context, controller, child) => IconButton(
                                        icon: Icon(
                                          hasPrompt ? Icons.description : Icons.description_outlined,
                                          size: 14,
                                          color: hasPrompt ? Theme.of(context).colorScheme.primary : null,
                                        ),
                                        tooltip: '设置系统提示词',
                                        constraints: const BoxConstraints(
                                          maxWidth: 32,
                                          maxHeight: 32,
                                        ),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: controller.toggle,
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(width: 32, height: 32),
                                  error: (err, stack) => IconButton(
                                    icon: const Icon(Icons.error_outline, size: 14, color: Colors.red),
                                    tooltip: '加载失败',
                                    constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                    padding: EdgeInsets.zero,
                                    onPressed: null,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.cleaning_services_outlined, size: 14),
                              tooltip: '清除上下文',
                              constraints: const BoxConstraints(
                                maxWidth: 32,
                                maxHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                shape: const CircleBorder(),
                                hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                              ),
                              onPressed: () async {
                                var localSessionId = ref.read(currentSessionIdProvider);
                                if (localSessionId == null) {
                                  final newSession = await ref.read(sessionListProvider.notifier).createNewSession();
                                  ref.read(currentSessionIdProvider.notifier).setSessionId(newSession.id);
                                  localSessionId = newSession.id;
                                }
                                ref.read(sessionListProvider.notifier).addSeparator(localSessionId!);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('上下文已清除'),
                                    behavior: SnackBarBehavior.floating,
                                    width: 200,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            Consumer(
                              builder: (context, ref, child) {
                                final namesAsync = ref.watch(modelNamesProvider);
                                final currentModel = ref.watch(currentModelProvider);
                                return namesAsync.when(
                                  data: (names) {
                                    if (names.isEmpty) {
                                      return IconButton(
                                        icon: const Icon(Icons.model_training, size: 14),
                                        tooltip: '无可用模型',
                                        constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: null,
                                      );
                                    }
                                    return FPopoverMenu(
                                      menuAnchor: Alignment.topCenter,
                                      childAnchor: Alignment.bottomCenter,
                                      menu: [
                                        FItemGroup(
                                          children: [
                                            ...names.map((name) => FItem(title: Text(name), suffix: currentModel == name ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null, onPress: () {
                                              ref.read(configProvider.notifier).updateDefaultModel(name);
                                            },
                                          )),
                                            FItem(
                                              prefix: const Icon(Icons.model_training),
                                              title: const Text('管理模型'),
                                              onPress: () {
                                                ref.read(selectedSectionProvider.notifier).state = SettingsSection.models;
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) => const SettingsPage(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                      builder: (context, controller, child) => IconButton(
                                        icon: const Icon(Icons.model_training, size: 14),
                                        tooltip: '切换模型',
                                        constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: controller.toggle,
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(width: 32, height: 32),
                                  error: (err, stack) => IconButton(
                                    icon: const Icon(Icons.error_outline, size: 14, color: Colors.red),
                                    tooltip: '加载模型失败',
                                    constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                    padding: EdgeInsets.zero,
                                    onPressed: null,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, child) {
                          return value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  style: IconButton.styleFrom(
                                    shape: const CircleBorder(),
                                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                  ),
                                  onPressed: () => _controller.clear(),
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: Icon(
                    Icons.send_rounded,
                    color: _isSending 
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                        : Theme.of(context).colorScheme.primary,
                  ),
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    padding: EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}