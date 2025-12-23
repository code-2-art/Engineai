import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as services;
import '../services/llm_provider.dart';
import '../services/image_provider.dart';
import '../services/image_session_provider.dart';
import '../models/image_message.dart';
import '../models/image_session.dart';


class ImagePage extends ConsumerStatefulWidget {
  const ImagePage({super.key});

  @override
  ConsumerState<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends ConsumerState<ImagePage> {
  final TextEditingController _promptController = TextEditingController();
    final ScrollController _scrollController = ScrollController();
    final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Widget _buildModelSelector(BuildContext context, WidgetRef ref) {
    final namesAsync = ref.watch(imageModelNamesProvider);
    final currentModel = ref.watch(imageCurrentModelProvider);
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
                  ref.read(imageCurrentModelProvider.notifier).setModel(name);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sessionOpt = ref.read(currentImageSessionProvider);
      if (sessionOpt != null && sessionOpt.messages.isNotEmpty && sessionOpt.messages.last.image.isEmpty) {
        _performBackgroundGeneration(sessionOpt);
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
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

  Future<void> _startImageGeneration() async {
    final prompt = _promptController.text.trim();
    final currentSessionOpt = ref.read(currentImageSessionProvider);
    final isGenerating = currentSessionOpt != null && currentSessionOpt.messages.isNotEmpty && currentSessionOpt.messages.last.image.isEmpty;
    if (prompt.isEmpty || isGenerating) return;
  
    ImageSession currentSession;
    if (currentSessionOpt == null) {
      final newSession = await ref.read(imageSessionListProvider.notifier).createNewSession();
      await ref.read(currentImageSessionIdProvider.notifier).setSessionId(newSession.id);
      currentSession = newSession;
    } else {
      currentSession = currentSessionOpt;
    }
  
    final messagePrompt = currentSession.messages.isNotEmpty ? '编辑：$prompt' : prompt;
    final loadingMsg = ImageMessage(messagePrompt, Uint8List(0), null);
    final updatedWithLoading = currentSession.copyWith(messages: [...currentSession.messages, loadingMsg]);
    await ref.read(imageSessionListProvider.notifier).updateSession(updatedWithLoading);
    _promptController.clear();
    _scrollToBottom();
  
    // Start background generation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performBackgroundGeneration(updatedWithLoading);
    });
  }
  
  Future<void> _performBackgroundGenerationAsync(ImageSession sessionWithLoading) async {
    try {
      final prompt = sessionWithLoading.messages.last.prompt;
      final generator = await ref.read(imageGeneratorProvider.future);
      String? base64Image;
      String? mimeType;
      if (sessionWithLoading.messages.length > 1) {
        final prevMsg = sessionWithLoading.messages[sessionWithLoading.messages.length - 2];
        base64Image = base64Encode(prevMsg.image);
        mimeType = 'image/png';
      }
      final result = await generator.generateImage(prompt, base64Image: base64Image, mimeType: mimeType);
      if (result.imageBytes != null) {
        final realMsg = ImageMessage(prompt, result.imageBytes!, result.description);
        final newMessages = List<ImageMessage>.from(sessionWithLoading.messages);
        newMessages[newMessages.length - 1] = realMsg;
        final updatedSession = sessionWithLoading.copyWith(messages: newMessages);
        await ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
        if (mounted) {
          _scrollToBottom();
        }
      } else {
        throw Exception('No image bytes returned');
      }
    } catch (e) {
      debugPrint('Background image generation error: $e');
      // Remove the loading message on error
      final newMessages = sessionWithLoading.messages.sublist(0, sessionWithLoading.messages.length - 1);
      final updatedSession = sessionWithLoading.copyWith(messages: newMessages);
      await ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
      if (mounted) {
        final errorMsg = e.toString();
        services.Clipboard.setData(services.ClipboardData(text: errorMsg));
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
                      e.toString(),
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
    }
  }
  
  void _performBackgroundGeneration(ImageSession sessionWithLoading) {
    _performBackgroundGenerationAsync(sessionWithLoading);
  }

  Future<void> _uploadImage() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List bytes;
        if (file.bytes != null) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        } else {
          return;
        }
        final name = file.name.isNotEmpty ? file.name : 'image.${file.extension ?? 'jpg'}';
        final message = ImageMessage('上传：$name', bytes, null);

        final currentSessionOpt = ref.read(currentImageSessionProvider);
        ImageSession currentSession;
        if (currentSessionOpt == null) {
          final newSession = await ref.read(imageSessionListProvider.notifier).createNewSession();
          await ref.read(currentImageSessionIdProvider.notifier).setSessionId(newSession.id);
          currentSession = newSession;
        } else {
          currentSession = currentSessionOpt;
        }
        final updatedSession = currentSession.copyWith(messages: [...currentSession.messages, message]);
        await ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
        _promptController.clear();
        _scrollToBottom();
      }
    }

  Future<void> _editImage(int index) async {
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession == null) return;
    final originalBytes = Uint8List.fromList(currentSession.messages[index].image);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('编辑图像')),
        body: ProImageEditor.memory(
          originalBytes,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List newBytes) async {
              Navigator.pop(context);
              final editedPrompt = '${currentSession.messages[index].prompt} (编辑)';
              final editedMessage = ImageMessage(editedPrompt, newBytes, null);
              final updatedSession = currentSession.copyWith(messages: [...currentSession.messages, editedMessage]);
              await ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
              _scrollToBottom();
            },
          ),
        ),
      ),
    ));
  }

  Future<void> _downloadImage(int index) async {
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession == null) return;
    final bytes = currentSession.messages[index].image;
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
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession == null) return;
    final newMessages = List<ImageMessage>.from(currentSession.messages)..removeAt(index);
    final updatedSession = currentSession.copyWith(messages: newMessages);
    ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
  }

  void _showImageViewer(int index) {
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession == null) return;
    final bytes = currentSession.messages[index].image;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black54,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          body: GestureDetector(
            onDoubleTap: () => Navigator.of(dialogContext).pop(),
            child: Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionsDrawer(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(imageSessionListProvider);
    return Drawer(
      child: Column(
        children: [
          const DrawerHeader(
            child: Text(
              '图像会话历史',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final lastPrompt = session.messages.isNotEmpty
                  ? session.messages.last.prompt
                  : '空会话';
                final timeStr = '${session.createdAt.hour.toString().padLeft(2, '0')}:${session.createdAt.minute.toString().padLeft(2, '0')}';
                final currentId = ref.read(currentImageSessionIdProvider);
                final isCurrent = session.id == currentId;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(session.title),
                  subtitle: Text(
                    lastPrompt.length > 40
                      ? '${lastPrompt.substring(0, 40)}...'
                      : lastPrompt,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: () async {
                      await ref.read(imageSessionListProvider.notifier).deleteSession(session.id);
                      if (isCurrent) {
                        ref.read(currentImageSessionIdProvider.notifier).setSessionId(null);
                      }
                      Navigator.pop(context);
                    },
                  ),
                  selected: isCurrent,
                  selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  onTap: () {
                    ref.read(currentImageSessionIdProvider.notifier).setSessionId(session.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建会话'),
            onTap: () async {
              final newSession = await ref.read(imageSessionListProvider.notifier).createNewSession();
              ref.read(currentImageSessionIdProvider.notifier).setSessionId(newSession.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = ref.watch(currentImageSessionProvider);
    final messages = currentSession?.messages ?? <ImageMessage>[];
    final bool isGenerating = messages.isNotEmpty && messages.last.image.isEmpty;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildSessionsDrawer(context, ref),
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建会话',
                  onPressed: () async {
                    final newSession = await ref.read(imageSessionListProvider.notifier).createNewSession();
                    ref.read(currentImageSessionIdProvider.notifier).setSessionId(newSession.id);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: '会话历史',
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ],
            ),
          ),
          Expanded(
            child: messages.isEmpty
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
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final reversedIndex = messages.length - 1 - index;
                      final msg = messages[reversedIndex];
                      final timeStr = "${msg.timestamp.year}-${msg.timestamp.month.toString().padLeft(2, '0')}-${msg.timestamp.day.toString().padLeft(2, '0')} ${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}";
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
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
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded, size: 14),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 20,
                                            maxWidth: 20,
                                            minHeight: 20,
                                            maxHeight: 20,
                                          ),
                                          onPressed: () {
                                            services.Clipboard.setData(services.ClipboardData(text: msg.prompt));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('已复制到剪贴板'),
                                                behavior: SnackBarBehavior.floating,
                                                width: 200,
                                              ),
                                            );
                                          },
                                          tooltip: '复制',
                                          style: IconButton.styleFrom(
                                            foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, size: 14),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 20,
                                            maxWidth: 20,
                                            minHeight: 20,
                                            maxHeight: 20,
                                          ),
                                          onPressed: () => _deleteImage(reversedIndex),
                                          tooltip: '删除',
                                          style: IconButton.styleFrom(
                                            foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
                                        child: msg.image.isEmpty
                                            ? Container(
                                                height: 240,
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Center(
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child: CircularProgressIndicator(strokeWidth: 2),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        '图像生成中...',
                                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : GestureDetector(
                                                 onTap: () => _showImageViewer(reversedIndex),
                                                 onDoubleTap: () => _showImageViewer(reversedIndex),
                                                 child: Image.memory(
                                                   msg.image,
                                                   height: 320,
                                                   fit: BoxFit.cover,
                                                 ),
                                               ),
                                      ),
                                    ),
                                    if (msg.aiDescription != null && msg.aiDescription!.isNotEmpty && msg.image.isNotEmpty)
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
                                    if (msg.image.isNotEmpty)
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
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    decoration: InputDecoration(
                      hintText: isGenerating ? '生成中...' : (messages.isEmpty ? '描述图像' : '编辑最后一张图片'),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Consumer(
                              builder: (context, ref, child) {
                                final namesAsync = ref.watch(imageModelNamesProvider);
                                final currentModel = ref.watch(imageCurrentModelProvider);
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
                                              ref.read(imageCurrentModelProvider.notifier).setModel(name);
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
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.upload_file, size: 14),
                              tooltip: '上传图像',
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                maxWidth: 32,
                                minHeight: 32,
                                maxHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                shape: const CircleBorder(),
                                hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                              ),
                              onPressed: _uploadImage,
                            ),
                          ],
                        ),
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _promptController,
                        builder: (context, value, child) {
                          return value.text.isNotEmpty && !isGenerating
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
                    onSubmitted: (_) => _startImageGeneration(),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: isGenerating ? null : _startImageGeneration,
                  icon: isGenerating
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