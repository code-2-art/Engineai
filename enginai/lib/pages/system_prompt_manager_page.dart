import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../models/system_prompt.dart';
import '../services/system_prompt_service.dart';

final systemPromptServiceProvider = Provider((ref) => SystemPromptService());

final systemPromptsProvider = FutureProvider<List<SystemPrompt>>((ref) async {
  return await ref.watch(systemPromptServiceProvider).getAllPrompts();
});

class SystemPromptManagerPage extends ConsumerStatefulWidget {
  const SystemPromptManagerPage({super.key});

  @override
  ConsumerState<SystemPromptManagerPage> createState() => _SystemPromptManagerPageState();
}

class _SystemPromptManagerPageState extends ConsumerState<SystemPromptManagerPage> {
  void _showEditDialog([SystemPrompt? prompt]) {
    final nameController = TextEditingController(text: prompt?.name);
    final contentController = TextEditingController(text: prompt?.content);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(prompt == null ? '新建系统提示词' : '编辑系统提示词'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FTextField(
              controller: nameController,
              hint: '标题 (例如: 翻译官)',
            ),
            const SizedBox(height: 16),
            FTextField(
              controller: contentController,
              hint: '提示词内容',
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          FButton(
            onPress: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () async {
              if (nameController.text.isEmpty || contentController.text.isEmpty) return;
              
              final service = ref.read(systemPromptServiceProvider);
              if (prompt == null) {
                await service.addPrompt(SystemPrompt(
                  name: nameController.text,
                  content: contentController.text,
                ));
              } else {
                await service.updatePrompt(prompt.copyWith(
                  name: nameController.text,
                  content: contentController.text,
                ));
              }
              ref.invalidate(systemPromptsProvider);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final promptsAsync = ref.watch(systemPromptsProvider);

    return FScaffold(
      header: FHeader.nested(
        title: const Text('系统提示词管理'),
        prefixes: [
          FButton.icon(
            onPress: () => Navigator.of(context).pop(),
            child: const Icon(Icons.chevron_left, size: 20),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: promptsAsync.when(
        data: (prompts) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: prompts.length + 1, // +1 for the "Add" button at the top
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FButton(
                  onPress: () => _showEditDialog(),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 20),
                      SizedBox(width: 8),
                      Text('新建系统提示词'),
                    ],
                  ),
                ),
              );
            }

            final prompt = prompts[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              prompt.name,
                              style: FTheme.of(context).typography.lg.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FButton.icon(
                                onPress: () => _showEditDialog(prompt),
                                child: const Icon(Icons.edit, size: 18),
                              ),
                              const SizedBox(width: 8),
                              FButton.icon(
                                onPress: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('确认删除'),
                                      content: Text('你确定要删除 "${prompt.name}" 吗？'),
                                      actions: [
                                        FButton(
                                          onPress: () => Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        FButton(
                                          onPress: () => Navigator.pop(context, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await ref.read(systemPromptServiceProvider).deletePrompt(prompt.id);
                                    ref.invalidate(systemPromptsProvider);
                                  }
                                },
                                child: const Icon(Icons.delete, size: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        prompt.content,
                        style: FTheme.of(context).typography.base.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('错误: $e')),
      ),
    ),
  );
}
}
