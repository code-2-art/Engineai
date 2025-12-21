import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../services/llm_provider.dart';
import '../services/image_provider.dart';
import '../services/session_provider.dart';
import 'package:flutter/services.dart' as services;

class ImageMessage {
  final String prompt;
  final Uint8List image;
  final String? aiDescription;
  final DateTime timestamp;

  ImageMessage(this.prompt, this.image, this.aiDescription, [DateTime? timestamp]) : timestamp = timestamp ?? DateTime.now();

  factory ImageMessage.fromJson(Map<String, dynamic> json) {
    final prompt = json['prompt'] as String;
    final imageBase64 = json['imageBase64'] as String;
    final image = base64Decode(imageBase64) as Uint8List;
    final aiDescription = json['aiDescription'] as String?;
    final timestampStr = json['timestamp'] as String;
    final timestamp = DateTime.parse(timestampStr);
    return ImageMessage(prompt, image, aiDescription, timestamp);
  }

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'imageBase64': base64Encode(image),
      'aiDescription': aiDescription,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class ImagePage extends ConsumerStatefulWidget {
  const ImagePage({super.key});

  @override
  ConsumerState<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends ConsumerState<ImagePage> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ImageMessage> _history = [];
  bool _isGenerating = false;

  Widget _buildModelSelector(BuildContext context, WidgetRef ref) {
    final namesAsync = ref.watch(imageModelNamesProvider);
    final currentModel = ref.watch(currentModelProvider);
    return namesAsync.when(
      data: (names) {
        if (names.isEmpty) {
          return const SizedBox(width: 32, height: 32);
        }
        return FPopoverMenu(
          menuAnchor: Alignment.topCenter,
          childAnchor: Alignment.bottomCenter,
          menu: [
            FItemGroup(
              children: names.map((name) => FItem(
                title: Text(name),
                suffix: currentModel == name
                  ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary)
                  : null,
                onPress: () {
                  ref.read(currentModelProvider.notifier).state = name;
                  ref.read(configProvider.notifier).updateDefaultModel(name);
                },
              )).toList(),
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
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _saveHistory();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/image_history.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final List<dynamic> list = json.decode(jsonStr);
        setState(() {
          _history = list.map((j) => ImageMessage.fromJson(j)).toList();
        });
      }
    } catch (e) {
      debugPrint('Load image history error: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/image_history.json');
      final List<Map<String, dynamic>> list = _history.map((m) => m.toJson()).toList();
      await file.writeAsString(json.encode(list));
    } catch (e) {
      debugPrint('Save image history error: $e');
    }
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

  Future<void> _generateImage() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isGenerating) return;

    setState(() => _isGenerating = true);

    try {
      final generator = await ref.read(imageGeneratorProvider.future);
      String? base64Image;
      String? mimeType;
      if (_history.isNotEmpty) {
        final lastBytes = _history.last.image;
        base64Image = base64Encode(lastBytes);
        mimeType = 'image/png';
      }
      final result = await generator.generateImage(prompt, base64Image: base64Image, mimeType: mimeType);
      if (result.imageBytes != null) {
        final messagePrompt = _history.isNotEmpty ? '编辑：$prompt' : prompt;
        final message = ImageMessage(messagePrompt, result.imageBytes!, result.description);
        setState(() {
          _history.add(message);
        });
        _promptController.clear();
        _scrollToBottom();
        _saveHistory();
      }
    } catch (e) {
      final errorMsg = e.toString();
      await services.Clipboard.setData(services.ClipboardData(text: errorMsg));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('生成失败，错误详情已复制到剪贴板'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '查看详情',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('错误详情'),
                    content: SelectableText(
                      errorMsg,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _uploadImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes != null) {
        final bytes = file.bytes!;
        final name = file.name.isNotEmpty ? file.name : 'image.${file.extension ?? 'jpg'}';
        final message = ImageMessage('上传：$name', bytes, null);
        setState(() {
          _history.add(message);
          _promptController.clear();
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _editImage(int index) async {
    final originalBytes = Uint8List.fromList(_history[index].image);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('编辑图像')),
        body: ProImageEditor.memory(
          originalBytes,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List newBytes) async {
              Navigator.pop(context);
              final editedPrompt = '${_history[index].prompt} (编辑)';
              final editedMessage = ImageMessage(editedPrompt, newBytes, null, DateTime.now());
              setState(() {
                _history.add(editedMessage);
              });
              _scrollToBottom();
            },
          ),
        ),
      ),
    ));
  }

  Future<void> _downloadImage(int index) async {
    final bytes = _history[index].image;
    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '保存图像',
      fileName: 'generated_image_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存成功: $outputFile')),
        );
      }
    }
  }

  void _deleteImage(int index) {
    setState(() {
      _history.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final modelNamesAsync = ref.watch(modelNamesProvider);
    final currentModel = ref.watch(currentModelProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 64, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text('生成你的第一张图像', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text('输入描述开始生成', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final reversedIndex = _history.length - 1 - index;
                      final msg = _history[reversedIndex];
                      final timeStr = '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                timeStr,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                                ),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Text(
                                    msg.prompt,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(
                                          msg.image,
                                          height: 240,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    if (msg.aiDescription != null && msg.aiDescription!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: Text(
                                          msg.aiDescription!,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                                            fontSize: 14,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, size: 18),
                                            onPressed: () => _editImage(reversedIndex),
                                            tooltip: '编辑',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.download, size: 18),
                                            onPressed: () => _downloadImage(reversedIndex),
                                            tooltip: '下载',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18),
                                            onPressed: () => _deleteImage(reversedIndex),
                                            tooltip: '删除',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.upload_file),
                  tooltip: '上传图像',
                  constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  ),
                  onPressed: _uploadImage,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    decoration: InputDecoration(
                      hintText: _isGenerating ? '生成中...' : (_history.isEmpty ? '描述图像，例如: \"一只可爱的猫在太空飞翔\"' : '编辑最后一张图片，例如: \"把猫的眼睛变成红色激光眼\"'),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Consumer(
                          builder: (context, ref, child) {
                            final namesAsync = ref.watch(modelNamesProvider);
                            final currentModel = ref.watch(currentModelProvider);
                            return namesAsync.when(
                              data: (names) {
                                if (names.isEmpty) {
                                  return const SizedBox(width: 32, height: 32);
                                }
                                return FPopoverMenu(
                                  menuAnchor: Alignment.topCenter,
                                  childAnchor: Alignment.bottomCenter,
                                  menu: [
                                    FItemGroup(
                                      children: names.map((name) => FItem(
                                        title: Text(name),
                                        suffix: currentModel == name
                                          ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary)
                                          : null,
                                        onPress: () {
                                          ref.read(currentModelProvider.notifier).state = name;
                                          ref.read(configProvider.notifier).updateDefaultModel(name);
                                        },
                                      )).toList(),
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
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _promptController,
                        builder: (context, value, child) {
                          return value.text.isNotEmpty && !_isGenerating
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  style: IconButton.styleFrom(
                                    shape: const CircleBorder(),
                                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                  ),
                                  onPressed: () => _promptController.clear(),
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _generateImage(),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _isGenerating ? null : _generateImage,
                  icon: _isGenerating
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    padding: const EdgeInsets.all(12),
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