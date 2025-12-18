import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../theme/theme.dart';
import '../services/llm_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

final historyProvider = StateNotifierProvider<HistoryNotifier, List<Message>>((ref) => HistoryNotifier());

final currentResponseProvider = StateProvider<String>((ref) => '');

class HistoryNotifier extends StateNotifier<List<Message>> {
  HistoryNotifier() : super([]);

  void add(Message message) {
    state = [...state, message];
  }

  void clear() {
    state = [];
  }
}

class AiChat extends ConsumerStatefulWidget {
  const AiChat({super.key});

  @override
  ConsumerState<AiChat> createState() => _AiChatState();
}

class _AiChatState extends ConsumerState<AiChat> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _autoCloseTimer;

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
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
    if (prompt.isEmpty) return;

    ref.read(historyProvider.notifier).add(Message(isUser: true, text: prompt));
    _controller.clear();
    _scrollToBottom();

    ref.read(currentResponseProvider.notifier).state = '';

    final llmFuture = ref.read(llmProvider.future);
    final llm = await llmFuture;
    final history = ref.read(historyProvider);
    final stream = llm.generateStream(history, prompt);

    await for (final delta in stream) {
      final current = ref.read(currentResponseProvider);
      ref.read(currentResponseProvider.notifier).state = current + delta;
      _scrollToBottom();
    }

    final fullResponse = ref.read(currentResponseProvider);
    if (fullResponse.isNotEmpty) {
      ref.read(historyProvider.notifier).add(Message(isUser: false, text: fullResponse));
      ref.read(currentResponseProvider.notifier).state = '';
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final currentResponse = ref.watch(currentResponseProvider);

    return Material(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    final isCurrentlyCollapsed = ref.read(sidebarCollapsedProvider);
                    _autoCloseTimer?.cancel();
                    ref.read(sidebarCollapsedProvider.notifier).state = !isCurrentlyCollapsed;
                    if (!ref.read(sidebarCollapsedProvider)) {
                      _autoCloseTimer = Timer(const Duration(seconds: 8), () {
                        if (mounted && !ref.read(sidebarCollapsedProvider)) {
                          ref.read(sidebarCollapsedProvider.notifier).state = true;
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.menu, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: history.length + (currentResponse.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < history.length) {
                  final message = history[index];
                  return Align(
                    alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: message.isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: MarkdownBody(
                          data: message.text,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              fontSize: 16,
                              color: message.isUser ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: MarkdownBody(
                          data: currentResponse.isEmpty ? 'AI 正在思考...' : currentResponse,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FButton(
                  onPress: _sendMessage,
                  child: const Text('发送'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}