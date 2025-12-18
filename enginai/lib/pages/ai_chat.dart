import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../services/llm_provider.dart';

final llmProvider = Provider<LLMProvider>((ref) => const CustomOpenAILLMProvider(
  apiKey: 'sk-989a1e9f90304b20af20f98a5815d37c',
  baseUrl: 'https://api.deepseek.com/v1/chat/completions',
  model: 'deepseek-chat',
));

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
    if (prompt.isEmpty) return;

    ref.read(historyProvider.notifier).add(Message(isUser: true, text: prompt));
    _controller.clear();
    _scrollToBottom();

    ref.read(currentResponseProvider.notifier).state = '';

    final llm = ref.read(llmProvider);
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
                        color: message.isUser ? Colors.blue[500] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        message.text,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
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
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        currentResponse.isEmpty ? 'AI 正在思考...' : currentResponse,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[900],
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