import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../services/llm_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: FScaffold(
        header: FHeader.nested(
          title: const Text('设置'),
          prefixes: [
            FButton.icon(
              onPress: () => Navigator.of(context).pop(),
              child: const Icon(Icons.chevron_left, size: 20),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
               const TabBar(
                tabs: [
                  Tab(text: '通用'),
                  Tab(text: '模型设置'),
                ],
                labelColor: Colors.black, // Adjust for theme if needed
                unselectedLabelColor: Colors.grey,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    const GeneralSettings(),
                    const LLMSettings(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GeneralSettings extends StatelessWidget {
  const GeneralSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '通用设置 (暂无)',
        style: FTheme.of(context).typography.base,
      ),
    );
  }
}

class LLMSettings extends ConsumerWidget {
  const LLMSettings({super.key});

  void _showConfigDialog(BuildContext context, WidgetRef ref, {LLMConfig? existingConfig}) {
    final nameController = TextEditingController(text: existingConfig?.name);
    final modelController = TextEditingController(text: existingConfig?.model);
    final urlController = TextEditingController(text: existingConfig?.baseUrl);
    final keyController = TextEditingController(text: existingConfig?.apiKey);
    
    // Track original name to handle renames
    final originalName = existingConfig?.name;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingConfig == null ? '添加模型' : '编辑模型'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FTextField(controller: nameController, hint: '显示名称 (Name)'),
              const SizedBox(height: 8),
              FTextField(controller: modelController, hint: '模型ID (Model ID)'),
              const SizedBox(height: 8),
              FTextField(controller: urlController, hint: 'Base URL (e.g. https://api.openai.com/v1)'),
              const SizedBox(height: 8),
              FTextField(controller: keyController, hint: 'API Key', obscureText: true),
            ],
          ),
        ),
        actions: [
          FButton(
            onPress: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () {
              if (nameController.text.isNotEmpty &&
                  modelController.text.isNotEmpty &&
                  urlController.text.isNotEmpty &&
                  keyController.text.isNotEmpty) {
                
                final newConfig = LLMConfig(
                  name: nameController.text,
                  model: modelController.text,
                  baseUrl: urlController.text,
                  apiKey: keyController.text,
                );

                // If editing and name changed, remove old one first
                if (existingConfig != null && originalName != newConfig.name && originalName != null) {
                   ref.read(configProvider.notifier).removeModel(originalName);
                }

                ref.read(configProvider.notifier).addModel(newConfig);
                Navigator.of(context).pop();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(configProvider);

    return configsAsync.when(
      data: (configs) {
        final list = configs.values.toList();
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FButton(
                onPress: () => _showConfigDialog(context, ref),
                child: const Text('添加模型'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final config = list[index];
                    return FCard(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    config.name,
                                    style: FTheme.of(context).typography.lg.copyWith(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FButton.icon(
                                      onPress: () => _showConfigDialog(context, ref, existingConfig: config),
                                      child: const Icon(Icons.edit, size: 20),
                                    ),
                                    const SizedBox(width: 8),
                                    FButton.icon(
                                      onPress: () {
                                        ref.read(configProvider.notifier).removeModel(config.name);
                                      },
                                      child: const Icon(Icons.delete, size: 20),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Model: ${config.model}', style: FTheme.of(context).typography.sm),
                            Text('URL: ${config.baseUrl}', style: FTheme.of(context).typography.sm),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
