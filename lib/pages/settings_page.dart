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
import '../models/llm_configs.dart';

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
                                suffix: currentIndex == entry.key ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null,
                                onPress: () {
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

  void _showProviderDialog(BuildContext context, WidgetRef ref, {ProviderConfig? existing}) {
    final nameController = TextEditingController(text: existing?.name);
    final baseUrlController = TextEditingController(text: existing?.baseUrl);
    final apiKeyController = TextEditingController(text: existing?.apiKey);
    final originalName = existing?.name;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '提供商' : '编辑提供商'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: '提供商名称 (e.g. deepseek)',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: baseUrlController,
              decoration: const InputDecoration(
                hintText: 'Base URL (e.g. https://api.deepseek.com/v1)',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'API Key',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
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
                  if (nameController.text.isNotEmpty && baseUrlController.text.isNotEmpty && apiKeyController.text.isNotEmpty) {
                    final newConfig = ProviderConfig(
                      name: nameController.text.trim(),
                      baseUrl: baseUrlController.text.trim(),
                      apiKey: apiKeyController.text.trim(),
                      models: existing?.models ?? const [],
                    );
                    if (existing != null && originalName != null && originalName != newConfig.name) {
                      ref.read(configProvider.notifier).removeProvider(originalName);
                    }
                    if (existing == null) {
                      ref.read(configProvider.notifier).addProvider(newConfig);
                    } else {
                      ref.read(configProvider.notifier).updateProvider(newConfig.name, newConfig);
                    }
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

  void _showModelDialog(BuildContext context, WidgetRef ref, String providerName, {ModelConfig? existing}) {
    final nameController = TextEditingController(text: existing?.name);
    final modelIdController = TextEditingController(text: existing?.modelId);
    final tempController = TextEditingController(text: existing?.temperature?.toString() ?? '');
    Set<ModelType> selectedTypes = existing?.types ?? {ModelType.llm};
    bool isEnabledLocal = existing?.isEnabled ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? '模型' : '编辑模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: '模型名称 (e.g. deepseek-chat)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: modelIdController,
                  decoration: const InputDecoration(
                    hintText: '模型 ID (e.g. deepseek-chat)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tempController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Temperature (0.0-2.0)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: ModelType.values.map((type) => CheckboxListTile(
                    title: Text(type.name.toUpperCase()),
                    value: selectedTypes.contains(type),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(type);
                        } else {
                          selectedTypes.remove(type);
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )).toList(),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('启用模型'),
                  value: isEnabledLocal,
                  onChanged: (bool? value) {
                    setState(() {
                      isEnabledLocal = value ?? true;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
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
                    double? temperature;
                    if (tempController.text.trim().isNotEmpty) {
                      temperature = double.tryParse(tempController.text.trim());
                      if (temperature == null || temperature < 0.0 || temperature > 2.0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Temperature 必须在 0.0 到 2.0 之间')),
                        );
                        return;
                      }
                    }
                    if (selectedTypes.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('必须选择至少一种模型类型')),
                      );
                      return;
                    }
                    if (nameController.text.isNotEmpty && modelIdController.text.isNotEmpty) {
                      final newModel = ModelConfig(
                        name: nameController.text.trim(),
                        modelId: modelIdController.text.trim(),
                        temperature: temperature,
                        types: selectedTypes,
                        isEnabled: isEnabledLocal,
                      );
                      if (existing != null) {
                        ref.read(configProvider.notifier).updateModel(providerName, existing.name, newModel);
                      } else {
                        ref.read(configProvider.notifier).addModel(providerName, newModel);
                      }
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleExport(BuildContext context, WidgetRef ref) async {
    try {
      final jsonData = ref.read(configProvider.notifier).exportToJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      
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
      data: (providers) {
        final providerList = providers.values.toList();
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextButton.icon(
                      onPressed: () => _showProviderDialog(context, ref),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('提供商'),
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
                child: providerList.isEmpty
                    ? const Center(child: Text('暂无提供商配置，点击“添加提供商”开始'))
                    : ListView.separated(
                        itemCount: providerList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final provider = providerList[index];
                          return FCard(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          provider.name,
                                          style: theme.typography.lg.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FButton.icon(
                                            onPress: () => _showProviderDialog(context, ref, existing: provider),
                                            child: const Icon(Icons.edit, size: 16),
                                          ),
                                          const SizedBox(width: 8),
                                          FButton.icon(
                                            onPress: () {
                                              ref.read(configProvider.notifier).removeProvider(provider.name);
                                            },
                                            child: const Icon(Icons.delete, size: 16),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 100,
                                            child: TextButton.icon(
                                              onPressed: () => _showModelDialog(context, ref, provider.name),
                                              icon: const Icon(Icons.add, size: 16),
                                              label: const Text('模型'),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Base URL: ${provider.baseUrl}', style: theme.typography.sm),
                                  Text('API Key: ${provider.apiKey.length > 10 ? provider.apiKey.substring(0, 10) + '...' : provider.apiKey}', style: theme.typography.sm),
                                  const SizedBox(height: 16),
                                  Text('模型列表:', style: theme.typography.sm.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  provider.models.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: Text('暂无模型，点击“添加模型”'),
                                        )
                                      : ListView.separated(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          itemCount: provider.models.length,
                                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                                          itemBuilder: (context, mIndex) {
                                            final model = provider.models[mIndex];
                                            return Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    flex: 2,
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(model.name, style: theme.typography.base.copyWith(fontWeight: FontWeight.w500)),
                                                        Text('ID: ${model.modelId}', style: theme.typography.sm),
                                                        if (model.temperature != null) Text('Temp: ${model.temperature}', style: theme.typography.sm),
                                                      ],
                                                    ),
                                                  ),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: model.types.map((t) {
                                                      IconData icon = Icons.help_outline;
                                                      switch (t) {
                                                        case ModelType.llm:
                                                          icon = Icons.chat_bubble_outline;
                                                          break;
                                                        case ModelType.vl:
                                                          icon = Icons.visibility_outlined;
                                                          break;
                                                        case ModelType.imageGen:
                                                          icon = Icons.image_outlined;
                                                          break;
                                                        case ModelType.embedding:
                                                          icon = Icons.layers_outlined;
                                                          break;
                                                      }
                                                      return Icon(
                                                        icon,
                                                        size: 16,
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      );
                                                    }).toList(),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Checkbox(
                                                    value: model.isEnabled,
                                                    onChanged: (_) => ref.read(configProvider.notifier).toggleModelEnabled(provider.name, model.name),
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  FButton.icon(
                                                    onPress: () => _showModelDialog(context, ref, provider.name, existing: model),
                                                    child: const Icon(Icons.edit, size: 16),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  FButton.icon(
                                                    onPress: () => ref.read(configProvider.notifier).removeModel(provider.name, model.name),
                                                    child: const Icon(Icons.delete, size: 16),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
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

// SystemPromptSettings remains the same as before
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
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: '标题 (例如: 翻译官)',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '提示词内容',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
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
