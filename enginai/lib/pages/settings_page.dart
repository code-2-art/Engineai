import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../theme/theme.dart';
import '../models/system_prompt.dart';
import '../services/system_prompt_service.dart';
import '../services/llm_provider.dart';

final systemPromptServiceProvider = Provider((ref) => SystemPromptService());

final systemPromptsProvider = FutureProvider<List<SystemPrompt>>((ref) async {
  return await ref.watch(systemPromptServiceProvider).getAllPrompts();
});

final enabledSystemPromptsProvider = FutureProvider<List<SystemPrompt>>((ref) async {
  final prompts = await ref.watch(systemPromptsProvider.future);
  return prompts.where((p) => p.isEnabled).toList();
});

enum SettingsSection {
  general('通用', Icons.tune),
  models('模型', Icons.model_training),
  prompts('人设', Icons.description_outlined);

  final String label;
  final IconData icon;
  const SettingsSection(this.label, this.icon);
}

final selectedSectionProvider = StateProvider<SettingsSection>((ref) => SettingsSection.general);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSection = ref.watch(selectedSectionProvider);
    final theme = FTheme.of(context);

    return FScaffold(
      header: FHeader.nested(
        title: const Text(''),
        prefixes: [
          FButton.icon(
            onPress: () => Navigator.of(context).pop(),
            child: const Icon(Icons.chevron_left, size: 14),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            // Left Sidebar
            Container(
              width: 160,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: SettingsSection.values.map((section) {
                  final isSelected = selectedSection == section;
                  return ListTile(
                    leading: Icon(
                      section.icon,
                      size: 20,
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      section.label,
                      style: theme.typography.sm.copyWith(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onTap: () => ref.read(selectedSectionProvider.notifier).state = section,
                  );
                }).toList(),
              ),
            ),
            const FDivider(axis: Axis.vertical),
            // Right Content
            Expanded(
              child: _buildSectionContent(selectedSection),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent(SettingsSection section) {
    switch (section) {
      case SettingsSection.general:
        return const GeneralSettings();
      case SettingsSection.models:
        return const LLMSettings();
      case SettingsSection.prompts:
        return const SystemPromptSettings();
    }
  }
}

class GeneralSettings extends ConsumerWidget {
  const GeneralSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(currentThemeIndexProvider);
    final theme = FTheme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('通用设置', style: theme.typography.sm.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          FCard(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('外观设置', style: theme.typography.sm.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('选择主题', style: theme.typography.base),
                      const SizedBox(width: 16),
                      FPopoverMenu(
                        menuAnchor: Alignment.topCenter,
                        childAnchor: Alignment.bottomCenter,
                        menu: [
                          FItemGroup(
                            children: themeNames.asMap().entries.map((entry) {
                              return FItem(
                                title: Text(entry.value),
                                suffix: currentIndex == entry.key ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null, onPress: () {
                                  ref.read(currentThemeIndexProvider.notifier).set(entry.key);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                        builder: (context, controller, child) => SizedBox(
                          width: 140,
                          height: 36,
                          child: TextButton.icon(
                            onPressed: controller.toggle,
                            icon: const Icon(Icons.arrow_drop_down, size: 16),
                            label: Text(themeNames[currentIndex]),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
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
  }
}

class LLMSettings extends ConsumerWidget {
  const LLMSettings({super.key});

  void _showConfigDialog(BuildContext context, WidgetRef ref, {LLMConfig? existingConfig}) {
    final nameController = TextEditingController(text: existingConfig?.name);
    final modelController = TextEditingController(text: existingConfig?.model);
    final urlController = TextEditingController(text: existingConfig?.baseUrl);
    final keyController = TextEditingController(text: existingConfig?.apiKey);
    final extraBodyController = TextEditingController(text: existingConfig?.extraBodyJson ?? '');
    final temperatureController = TextEditingController(text: existingConfig?.temperature?.toString() ?? '');
    
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
              const SizedBox(height: 8),
              FTextField(
                controller: extraBodyController,
                hint: 'Extra Body JSON (例如 {"reasoning": {"enabled": true}})',
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              FTextField(
                controller: temperatureController,
                hint: 'Temperature (0.0-2.0)',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton(
                onPress: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
              FButton(
                onPress: () {
                  if (nameController.text.isNotEmpty &&
                      modelController.text.isNotEmpty &&
                      urlController.text.isNotEmpty &&
                      keyController.text.isNotEmpty) {
                    
                    String? extraBodyJson;
                    if (extraBodyController.text.trim().isNotEmpty) {
                      extraBodyJson = extraBodyController.text.trim();
                    }

                    double? temperature;
                    if (temperatureController.text.trim().isNotEmpty) {
                      temperature = double.tryParse(temperatureController.text.trim());
                      if (temperature == null || temperature < 0.0 || temperature > 2.0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Temperature 必须在 0.0 到 2.0 之间')),
                        );
                        return;
                      }
                    }
                    
                    final newConfig = LLMConfig(
                      name: nameController.text,
                      model: modelController.text,
                      baseUrl: urlController.text,
                      apiKey: keyController.text,
                      extraBodyJson: extraBodyJson,
                      temperature: temperature,
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
        ],
      ),
    );
  }

  Future<void> _handleExport(BuildContext context, WidgetRef ref) async {
    try {
      final jsonData = ref.read(configProvider.notifier).exportToJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      
      // Let user choose where to save the file
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存配置文件',
        fileName: 'llm_config_export.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsString(jsonString);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('配置已保存到硬盘')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _handleImport(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Show merge/overwrite dialog
      if (context.mounted) {
        final shouldMerge = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导入模式'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请选择如何导入配置：'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FButton(
                        onPress: () => Navigator.pop(context, true),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.merge_type, size: 32),
                            const SizedBox(height: 8),
                            const Text('合并', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              '保留现有配置\n添加新配置',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FButton(
                        onPress: () => Navigator.pop(context, false),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh, size: 32),
                            const SizedBox(height: 8),
                            const Text('覆盖', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              '删除现有配置\n仅使用导入',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              FButton(
                onPress: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        );
        
        if (shouldMerge != null) {
          await ref.read(configProvider.notifier).importFromJson(jsonData, merge: shouldMerge);
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(shouldMerge ? '配置已合并' : '配置已覆盖')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(configProvider);
    final theme = FTheme.of(context);

    return configsAsync.when(
      data: (configs) {
        final list = configs.values.toList();
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextButton.icon(
                      onPressed: () => _showConfigDialog(context, ref),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FButton.icon(
                    onPress: () => _handleImport(context, ref),
                    child: const Icon(Icons.upload_file, size: 16),
                  ),
                  const SizedBox(width: 8),
                  FButton.icon(
                    onPress: () => _handleExport(context, ref),
                    child: const Icon(Icons.download, size: 16),
                  ),
                ],
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
                                    Checkbox(
                                      value: config.isEnabled,
                                      onChanged: (value) {
                                        ref.read(configProvider.notifier).toggleModel(config.name);
                                      },
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      side: BorderSide.none,
                                    ),
                                    const SizedBox(width: 8),
                                    FButton.icon(
                                      onPress: () => _showConfigDialog(context, ref, existingConfig: config),
                                      child: const Icon(Icons.edit, size: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    FButton.icon(
                                      onPress: () {
                                        ref.read(configProvider.notifier).removeModel(config.name);
                                      },
                                      child: const Icon(Icons.delete, size: 16),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Model: ${config.model}', style: theme.typography.sm),
                            Text('URL: ${config.baseUrl}', style: theme.typography.sm),
                            if (config.temperature != null)
                              Text('Temperature: ${config.temperature}', style: theme.typography.sm),
                            if (config.extraBodyJson != null && config.extraBodyJson!.isNotEmpty)
                              Text('Extra Body: ${config.extraBodyJson!.length > 30 ? config.extraBodyJson!.substring(0, 30) + '...' : config.extraBodyJson!}', style: theme.typography.sm),
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
class SystemPromptSettings extends ConsumerStatefulWidget {
  const SystemPromptSettings({super.key});

  @override
  ConsumerState<SystemPromptSettings> createState() => _SystemPromptSettingsState();
}

class _SystemPromptSettingsState extends ConsumerState<SystemPromptSettings> {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton(
                onPress: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
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
        ],
      ),
    );
  }

  Future<void> _handleExportPrompt(SystemPrompt prompt) async {
    try {
      final markdown = prompt.toMarkdown();
      
      // Let user choose where to save the file
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出系统提示词',
        fileName: '${prompt.name}.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
      );
      
      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsString(markdown);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提示词已导出')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _handleImportPrompt() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final markdown = await file.readAsString();
      final prompt = SystemPrompt.fromMarkdown(markdown);
      
      final service = ref.read(systemPromptServiceProvider);
      await service.addPrompt(prompt);
      ref.invalidate(systemPromptsProvider);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提示词已导入')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final promptsAsync = ref.watch(systemPromptsProvider);
    final theme = FTheme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('系统提示词', style: theme.typography.sm.copyWith(fontWeight: FontWeight.bold)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FButton.icon(
                    onPress: _handleImportPrompt,
                    child: const Icon(Icons.upload_file, size: 16),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextButton.icon(
                      onPressed: () => _showEditDialog(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('新建'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: promptsAsync.when(
              data: (prompts) => ListView.builder(
                itemCount: prompts.length,
                itemBuilder: (context, index) {
                  final prompt = prompts[index];
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
                                    style: theme.typography.lg.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: prompt.isEnabled,
                                      onChanged: (value) async {
                                        await ref.read(systemPromptServiceProvider).togglePrompt(prompt.id);
                                        ref.invalidate(systemPromptsProvider);
                                      },
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      side: BorderSide.none,
                                    ),
                                    const SizedBox(width: 8),
                                    FButton.icon(
                                      onPress: () => _handleExportPrompt(prompt),
                                      child: const Icon(Icons.download, size: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    FButton.icon(
                                      onPress: () => _showEditDialog(prompt),
                                      child: const Icon(Icons.edit, size: 16),
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
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  FButton(
                                                    onPress: () => Navigator.pop(context, false),
                                                    child: const Text('取消'),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  FButton(
                                                    onPress: () => Navigator.pop(context, true),
                                                    child: const Text('删除'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          await ref.read(systemPromptServiceProvider).deletePrompt(prompt.id);
                                          ref.invalidate(systemPromptsProvider);
                                        }
                                      },
                                      child: const Icon(Icons.delete, size: 16),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              prompt.content,
                              style: theme.typography.xs.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                              maxLines: 2,
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
        ],
      ),
    );
  }
}
