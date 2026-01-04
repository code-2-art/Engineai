import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
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
import '../services/image_storage_service.dart';
import '../models/image_message.dart';
import '../models/image_session.dart';
import '../services/generation_task_manager.dart';
import '../models/generation_task.dart';
import '../services/notification_provider.dart';


class ImagePage extends ConsumerStatefulWidget {
  const ImagePage({super.key});

  @override
  ConsumerState<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends ConsumerState<ImagePage> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _currentTaskId;
  
  // 防抖定时器，用于UI更新
  Timer? _debounceTimer;
  static const _debounceDelay = Duration(milliseconds: 50);
  
  // 标志：是否已注册监听器
  bool _hasListener = false;
  
  // 标志：页面是否已经初始化过
  bool _initialized = false;

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
      _checkRunningTask();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 页面首次显示时，如果还没有初始化过，尝试自动选中会话并加载图片
    if (!_initialized) {
      _initialized = true;
      print('ImagePage: didChangeDependencies - 页面首次显示');
      // 延迟执行，确保provider已初始化
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _autoSelectSession();
        }
      });
    }
  }

  /// 自动选中会话（如果当前没有选中的会话）
  Future<void> _autoSelectSession() async {
    // 延迟读取，确保provider已完全初始化
    await Future.delayed(const Duration(milliseconds: 100));
    
    final currentSessionId = ref.read(currentImageSessionIdProvider);
    final sessions = ref.read(imageSessionListProvider);
    print('ImagePage: _autoSelectSession - 当前会话ID: $currentSessionId, 会话数量: ${sessions.length}');
    
    if (currentSessionId == null && sessions.isNotEmpty) {
      print('ImagePage: _autoSelectSession - 自动选中第一个会话: ${sessions.first.id}');
      await ref.read(currentImageSessionIdProvider.notifier).setSessionId(sessions.first.id);
      // 等待会话ID设置完成后再加载图片
      if (mounted) {
        _loadCurrentSessionImages();
      }
    } else if (currentSessionId != null && sessions.isEmpty) {
      print('ImagePage: _autoSelectSession - 会话列表为空，无法选中');
    } else {
      // 有当前会话ID，直接加载图片
      print('ImagePage: _autoSelectSession - 已有会话ID，直接加载图片');
      _loadCurrentSessionImages();
    }
  }

  void _checkRunningTask() {
    final taskManager = ref.read(taskManagerProvider);
    final runningTask = taskManager.getRunningTask(TaskType.image);
    if (runningTask != null) {
      _currentTaskId = runningTask.id;
      // 监听任务状态
      _listenToTask(runningTask.id);
    }
  }

  void _listenToTask(String taskId) {
    print('ImagePage: Start listening to task $taskId');
    final taskManager = ref.read(taskManagerProvider);
    taskManager.watchTask(taskId).listen((task) {
      print('ImagePage: Task $taskId update status: ${task.status}');
      if (!mounted) return;
      
      // 取消之前的防抖定时器
      _debounceTimer?.cancel();
      
      // 使用防抖延迟处理UI更新
      _debounceTimer = Timer(_debounceDelay, () {
        if (!mounted) return;
        
        // 处理任务完成
        if (task.status == TaskStatus.completed && task.generatedImage != null) {
          print('ImagePage: Task completed, updating session');
          _handleTaskCompleted(task);
        }
        
        // 处理任务失败
        if (task.status == TaskStatus.failed) {
          print('ImagePage: Task failed, error: ${task.error}');
          _handleTaskFailed(task);
        }
        
        // 处理任务取消
        if (task.status == TaskStatus.cancelled) {
          print('ImagePage: Task cancelled');
          _handleTaskCancelled();
        }
      });
    });
  }

  Future<void> _handleTaskCompleted(GenerationTask task) async {
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession != null) {
      final messagePrompt = currentSession.messages.last.prompt;
      // 保存图片到文件系统
      final imageStorage = ImageStorageService();
      final imageRef = await imageStorage.saveImage(task.generatedImage!);
      final realMsg = ImageMessage(
        prompt: messagePrompt,
        imageRef: imageRef,
        aiDescription: task.currentResponse,
      )..setCachedImageData(task.generatedImage!);
      final newMessages = List<ImageMessage>.from(currentSession.messages);
      newMessages[newMessages.length - 1] = realMsg;
      final updatedSession = currentSession.copyWith(messages: newMessages);
      ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
      
      // 使用PostFrameCallback确保UI更新后再滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom();
        }
      });
    }
    _currentTaskId = null;
  }

  void _handleTaskFailed(GenerationTask task) {
    // 移除加载消息，但保留提示词以便重试
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession != null) {
      final lastMessage = currentSession.messages.last;
      // 将 loading 消息的提示词恢复到输入框
      if (lastMessage.prompt.startsWith('编辑：')) {
        _promptController.text = lastMessage.prompt.substring(3);
      } else {
        _promptController.text = lastMessage.prompt;
      }
      
      // 移除 loading 消息
      final newMessages = currentSession.messages.sublist(0, currentSession.messages.length - 1);
      final updatedSession = currentSession.copyWith(messages: newMessages);
      ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
    }
    
    if (mounted) {
      services.Clipboard.setData(services.ClipboardData(text: task.error ?? ''));
      ref.read(notificationServiceProvider).showError('生成失败，错误详情已复制到剪贴板');
    }
    _currentTaskId = null;
  }

  void _handleTaskCancelled() {
    // 移除加载消息
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession != null && currentSession.messages.isNotEmpty) {
      final lastMessage = currentSession.messages.last;
      if (!lastMessage.hasCachedImageData && !lastMessage.hasImage) {
        final newMessages = currentSession.messages.sublist(0, currentSession.messages.length - 1);
        final updatedSession = currentSession.copyWith(messages: newMessages);
        ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
      }
    }
    _currentTaskId = null;
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    _hasListener = false;
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
    final isGenerating = currentSessionOpt != null && currentSessionOpt.messages.isNotEmpty &&
                         !currentSessionOpt.messages.last.hasCachedImageData && !currentSessionOpt.messages.last.hasImage;
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
    final loadingMsg = ImageMessage(
      prompt: messagePrompt,
    )..setCachedImageData(Uint8List(0)); // 空数据表示正在加载
    final updatedWithLoading = currentSession.copyWith(messages: [...currentSession.messages, loadingMsg]);
    await ref.read(imageSessionListProvider.notifier).updateSession(updatedWithLoading);
    _promptController.clear();
    _scrollToBottom();
  
    // 创建任务
    final taskManager = ref.read(taskManagerProvider);
    List<String> base64Images = [];
    
    // 使用更新后的消息，但排除loading消息
    final contextMessages = updatedWithLoading.messages.sublist(0, updatedWithLoading.messages.length - 1);
    final lastSeparatorIndex = contextMessages.lastIndexWhere((msg) => msg.isSeparator);
    
    // 只使用最后一个分隔符之后的图片
    final messagesToUse = lastSeparatorIndex == -1
        ? contextMessages
        : contextMessages.sublist(lastSeparatorIndex + 1);
    
    // 检查是否有通过上传按钮上传的多张图片
    // 上传的图片 prompt 以 "上传：" 开头
    final uploadedImages = messagesToUse.where((msg) => msg.hasCachedImageData && msg.prompt.startsWith('上传：')).toList();
    final hasMultipleUploadedImages = uploadedImages.length > 1;
    
    if (hasMultipleUploadedImages) {
      // 如果上传了多张图片，使用所有上传的图片
      for (final msg in uploadedImages) {
        if (msg.cachedImageData != null) {
          base64Images.add(base64Encode(msg.cachedImageData!));
        }
      }
    } else {
      // 否则只使用最后一张图片（无论是上传的还是生成的）
      for (int i = messagesToUse.length - 1; i >= 0; i--) {
        final msg = messagesToUse[i];
        if (msg.hasCachedImageData && msg.cachedImageData != null) {
          base64Images.add(base64Encode(msg.cachedImageData!));
          break; // 只添加最后一张
        }
      }
    }
    
    final taskId = await taskManager.createImageTaskPending(
      currentSession.id,
      messagePrompt,
      base64Images,
    );
    
    _currentTaskId = taskId;
    _listenToTask(taskId);
    await taskManager.startImageTask(taskId, ref);
  }

  Future<void> _uploadImage() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        List<ImageMessage> newMessages = [];
        for (final file in result.files) {
          Uint8List bytes;
          if (file.bytes != null) {
            bytes = file.bytes!;
          } else if (file.path != null) {
            bytes = await File(file.path!).readAsBytes();
          } else {
            continue;
          }
          final name = file.name.isNotEmpty ? file.name : 'image.${file.extension ?? 'png'}';
          // 保存上传的图片到文件系统
          final imageStorage = ImageStorageService();
          final imageRef = await imageStorage.saveImage(bytes);
          newMessages.add(ImageMessage(
            prompt: '上传：$name',
            imageRef: imageRef,
          )..setCachedImageData(bytes));
        }

        final currentSessionOpt = ref.read(currentImageSessionProvider);
        ImageSession currentSession;
        if (currentSessionOpt == null) {
          final newSession = await ref.read(imageSessionListProvider.notifier).createNewSession();
          await ref.read(currentImageSessionIdProvider.notifier).setSessionId(newSession.id);
          currentSession = newSession;
        } else {
          currentSession = currentSessionOpt;
        }
        final updatedSession = currentSession.copyWith(messages: [...currentSession.messages, ...newMessages]);
        await ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
        _promptController.clear();
        _scrollToBottom();
      }
    }

  Future<void> _editImage(int index) async {
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession == null) return;
    
    // 获取图片数据
    Uint8List originalBytes;
    final msg = currentSession.messages[index];
    if (msg.cachedImageData != null) {
      originalBytes = msg.cachedImageData!;
    } else if (msg.imageRef != null) {
      final imageStorage = ImageStorageService();
      final loadedBytes = await imageStorage.loadImage(msg.imageRef!);
      if (loadedBytes == null) {
        ref.read(notificationServiceProvider).showError('无法加载图片');
        return;
      }
      originalBytes = loadedBytes;
    } else {
      ref.read(notificationServiceProvider).showError('没有可编辑的图片');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('编辑图像')),
        body: ProImageEditor.memory(
          originalBytes,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List newBytes) async {
              Navigator.pop(context);
              final editedPrompt = '${currentSession.messages[index].prompt} (编辑)';
              // 保存编辑后的图片
              final imageStorage = ImageStorageService();
              final imageRef = await imageStorage.saveImage(newBytes);
              final editedMessage = ImageMessage(
                prompt: editedPrompt,
                imageRef: imageRef,
              )..setCachedImageData(newBytes);
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
    
    // 获取图片数据
    Uint8List bytes;
    final msg = currentSession.messages[index];
    if (msg.cachedImageData != null) {
      bytes = msg.cachedImageData!;
    } else if (msg.imageRef != null) {
      final imageStorage = ImageStorageService();
      final loadedBytes = await imageStorage.loadImage(msg.imageRef!);
      if (loadedBytes == null) {
        ref.read(notificationServiceProvider).showError('无法加载图片');
        return;
      }
      bytes = loadedBytes;
    } else {
      ref.read(notificationServiceProvider).showError('没有可下载的图片');
      return;
    }
    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '保存图像',
      fileName: 'generated_image_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
      if (mounted) {
        ref.read(notificationServiceProvider).showSuccess('保存成功: $outputFile');
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

  Future<void> _showImageViewer(int index) async {
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession == null) return;
    
    // 获取图片数据
    Uint8List bytes;
    final msg = currentSession.messages[index];
    if (msg.cachedImageData != null) {
      bytes = msg.cachedImageData!;
    } else if (msg.imageRef != null) {
      final imageStorage = ImageStorageService();
      final loadedBytes = await imageStorage.loadImage(msg.imageRef!);
      if (loadedBytes == null) {
        ref.read(notificationServiceProvider).showError('无法加载图片');
        return;
      }
      bytes = loadedBytes;
      // 缓存加载的图片
      currentSession.messages[index].setCachedImageData(bytes);
    } else {
      ref.read(notificationServiceProvider).showError('没有可显示的图片');
      return;
    }
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
                    },
                  ),
                  selected: isCurrent,
                  selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  onTap: () async {
                    ref.read(currentImageSessionIdProvider.notifier).setSessionId(session.id);
                    Navigator.pop(context);
                    // 加载选中会话的图片数据
                    await _loadCurrentSessionImages();
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

  /// 加载当前会话的图片数据
  Future<void> _loadCurrentSessionImages() async {
    final currentSession = ref.read(currentImageSessionProvider);
    if (currentSession == null) {
      print('ImagePage: _loadCurrentSessionImages - 当前会话为空，跳过加载');
      return;
    }

    print('ImagePage: _loadCurrentSessionImages - 开始加载会话 ${currentSession.id}');
    print('ImagePage: _loadCurrentSessionImages - 原始消息数量: ${currentSession.messages.length}');

    final historyService = ref.read(imageHistoryServiceProvider);
    final sessionWithImages = await historyService.loadSessionWithImages(currentSession);
    
    print('ImagePage: _loadCurrentSessionImages - 会话加载完成，消息数量: ${sessionWithImages.messages.length}');
    for (int i = 0; i < sessionWithImages.messages.length; i++) {
      final msg = sessionWithImages.messages[i];
      print('ImagePage: _loadCurrentSessionImages - 消息[$i] imageRef: ${msg.imageRef}, hasCached: ${msg.hasCachedImageData}, cachedSize: ${msg.cachedImageData?.length}');
    }
    
    if (mounted) {
      final sessions = ref.read(imageSessionListProvider);
      final index = sessions.indexWhere((s) => s.id == sessionWithImages.id);
      if (index != -1) {
        ref.read(imageSessionListProvider.notifier).updateSession(sessionWithImages);
        print('ImagePage: 会话已更新到列表');
      }
      
      // 检查是否有正在生成的任务，如果有，检查是否已经完成
      // 如果最后一条消息有图片数据，说明任务已完成，需要清除 _currentTaskId
      if (_currentTaskId != null) {
        final taskManager = ref.read(taskManagerProvider);
        final task = taskManager.getTask(_currentTaskId!);
        
        // 检查最后一条消息是否有图片
        final messages = sessionWithImages.messages;
        if (messages.isNotEmpty) {
          final lastMessage = messages.last;
          
          // 检查任务状态
          if (task != null && task.status == TaskStatus.failed) {
            // 任务已失败，需要检查图片是否已经生成
            print('ImagePage: 任务已失败，检查图片是否已生成');
             
            // 如果消息有 imageRef，说明图片已经生成并保存
            if (lastMessage.imageRef != null && lastMessage.imageRef!.isNotEmpty) {
              // 图片已经生成，尝试加载
              print('ImagePage: 图片已生成（有 imageRef），尝试加载');
              final imageStorage = ImageStorageService();
              final imageData = await imageStorage.loadImage(lastMessage.imageRef!);
              if (imageData != null) {
                // 图片文件存在，加载并缓存 - 创建新对象避免引用问题
                final updatedMessages = List<ImageMessage>.from(messages);
                final newMessage = ImageMessage(
                  prompt: lastMessage.prompt,
                  imageRef: lastMessage.imageRef,
                  aiDescription: lastMessage.aiDescription,
                  timestamp: lastMessage.timestamp,
                  isSeparator: lastMessage.isSeparator,
                )..setCachedImageData(imageData);
                updatedMessages[messages.length - 1] = newMessage;
                final updatedSession = sessionWithImages.copyWith(messages: updatedMessages);
                ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
                _currentTaskId = null;
                print('ImagePage: 图片加载成功，清除当前任务ID');
              } else {
                // 图片文件不存在，移除 loading 消息
                print('ImagePage: 图片文件不存在，移除 loading 消息');
                if (!lastMessage.hasCachedImageData || (lastMessage.cachedImageData != null && lastMessage.cachedImageData!.isEmpty)) {
                  final newMessages = messages.sublist(0, messages.length - 1);
                  final updatedSession = sessionWithImages.copyWith(messages: newMessages);
                  ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
                  _currentTaskId = null;
                  
                  // 显示错误提示
                  if (task.error != null && task.error!.isNotEmpty) {
                    ref.read(notificationServiceProvider).showError(task.error!);
                  }
                }
              }
            } else {
              // 没有 imageRef，说明图片没有生成，移除 loading 消息
              print('ImagePage: 没有 imageRef，移除 loading 消息');
              if (!lastMessage.hasCachedImageData || (lastMessage.cachedImageData != null && lastMessage.cachedImageData!.isEmpty)) {
                final newMessages = messages.sublist(0, messages.length - 1);
                final updatedSession = sessionWithImages.copyWith(messages: newMessages);
                ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
                _currentTaskId = null;
                
                // 显示错误提示
                if (task.error != null && task.error!.isNotEmpty) {
                  ref.read(notificationServiceProvider).showError(task.error!);
                }
              }
            }
          } else if (lastMessage.hasCachedImageData && lastMessage.cachedImageData != null && lastMessage.cachedImageData!.isNotEmpty) {
            // 图片已经生成，清除当前任务ID
            print('ImagePage: 图片已加载，清除当前任务ID');
            _currentTaskId = null;
          } else if (lastMessage.imageRef != null && lastMessage.imageRef!.isNotEmpty) {
            // 消息有 imageRef 但没有缓存数据，尝试加载
            print('ImagePage: 消息有 imageRef 但没有缓存，尝试加载');
            final imageStorage = ImageStorageService();
            final imageData = await imageStorage.loadImage(lastMessage.imageRef!);
            if (imageData != null) {
              // 图片文件存在，加载并缓存 - 创建新对象避免引用问题
              final updatedMessages = List<ImageMessage>.from(messages);
              final newMessage = ImageMessage(
                prompt: lastMessage.prompt,
                imageRef: lastMessage.imageRef,
                aiDescription: lastMessage.aiDescription,
                timestamp: lastMessage.timestamp,
                isSeparator: lastMessage.isSeparator,
              )..setCachedImageData(imageData);
              updatedMessages[messages.length - 1] = newMessage;
              final updatedSession = sessionWithImages.copyWith(messages: updatedMessages);
              ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
              _currentTaskId = null;
              print('ImagePage: 图片加载成功，清除当前任务ID');
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听会话列表变化，加载完成后自动选中会话（只注册一次）
    if (!_hasListener) {
      _hasListener = true;
      ref.listen<List<ImageSession>>(imageSessionListProvider, (previous, next) {
        print('ImagePage: imageSessionListProvider 变化: ${previous?.length} -> ${next.length}');
        if (next.isNotEmpty) {
          _autoSelectSession();
        }
      });
      
      // 监听当前会话ID变化，自动加载图片
      ref.listen<String?>(currentImageSessionIdProvider, (previous, next) {
        print('ImagePage: currentImageSessionIdProvider 变化: $previous -> $next');
        if (next != null && next != previous) {
          // 延迟加载，确保会话列表已更新
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _loadCurrentSessionImages();
            }
          });
        }
      });
    }
    
    final currentSession = ref.watch(currentImageSessionProvider);
    final messages = currentSession?.messages ?? <ImageMessage>[];
    // 排除分隔符来判断是否正在生成
    final nonSeparatorMessages = messages.where((msg) => !msg.isSeparator).toList();
    final bool isGenerating = nonSeparatorMessages.isNotEmpty &&
                              !nonSeparatorMessages.last.hasCachedImageData &&
                              !nonSeparatorMessages.last.hasImage;
    // 缓存模型名称列表，避免重复加载
    final namesAsync = ref.watch(imageModelNamesProvider);
    final currentModel = ref.watch(imageCurrentModelProvider);

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
                      
                      // 显示分隔符
                      if (msg.isSeparator) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(child: Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), thickness: 1)),
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
                              Expanded(child: Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), thickness: 1)),
                            ],
                          ),
                        );
                      }
                      
                      final timeStr = "${msg.timestamp.year}-${msg.timestamp.month.toString().padLeft(2, '0')}-${msg.timestamp.day.toString().padLeft(2, '0')} ${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}";
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4, left: 4),
                              child: Text(
                                "$currentModel • $timeStr",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
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
                                        borderRadius: BorderRadius.circular(4),
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
                                            ref.read(notificationServiceProvider).showSuccess('已复制到剪贴板');
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
                                  borderRadius: BorderRadius.circular(4),
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
                                        borderRadius: BorderRadius.circular(4),
                                        child: !msg.hasCachedImageData || (msg.cachedImageData != null && msg.cachedImageData!.isEmpty)
                                            ? Container(
                                                height: 320,
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                                                  borderRadius: BorderRadius.circular(4),
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
                                                 child: msg.cachedImageData != null && msg.cachedImageData!.isNotEmpty
                                                     ? Image.memory(
                                                         msg.cachedImageData!,
                                                         height: 320,
                                                         fit: BoxFit.cover,
                                                       )
                                                     : Container(
                                                         height: 320,
                                                         decoration: BoxDecoration(
                                                           color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                                                           borderRadius: BorderRadius.circular(4),
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
                                                                 '加载中...',
                                                                 style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                                   color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                                 ),
                                                               ),
                                                             ],
                                                           ),
                                                         ),
                                                       ),
                                               ),
                                      ),
                                    ),
                                    if (msg.aiDescription != null && msg.aiDescription!.isNotEmpty && msg.hasCachedImageData)
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
                                    if (msg.hasCachedImageData)
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
                      hintText: isGenerating ? '生成中...' : (messages.isEmpty ? '描述图像' : '编辑图像'),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            namesAsync.when(
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
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.upload_file, size: 14),
                              tooltip: '上传参考图片',
                              constraints: const BoxConstraints(
                                maxWidth: 32,
                                maxHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                shape: const CircleBorder(),
                                hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                              ),
                              onPressed: _uploadImage,
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
                                // 取消正在运行的任务
                                if (_currentTaskId != null) {
                                  final taskManager = ref.read(taskManagerProvider);
                                  taskManager.cancelTask(_currentTaskId!);
                                  _currentTaskId = null;
                                }
                                
                                var localSessionId = ref.read(currentImageSessionIdProvider);
                                if (localSessionId == null) {
                                  final newSession = await ref.read(imageSessionListProvider.notifier).createNewSession();
                                  ref.read(currentImageSessionIdProvider.notifier).setSessionId(newSession.id);
                                  localSessionId = newSession.id;
                                }
                                
                                // 移除最后的 loading 消息（如果存在）
                                final currentSession = ref.read(currentImageSessionProvider);
                                if (currentSession != null && currentSession.messages.isNotEmpty) {
                                  final lastMessage = currentSession.messages.last;
                                  if (!lastMessage.hasCachedImageData && !lastMessage.hasImage) {
                                    final newMessages = currentSession.messages.sublist(0, currentSession.messages.length - 1);
                                    final updatedSession = currentSession.copyWith(messages: newMessages);
                                    await ref.read(imageSessionListProvider.notifier).updateSession(updatedSession);
                                  }
                                }
                                
                                await ref.read(imageSessionListProvider.notifier).addSeparator(localSessionId!);
                                _promptController.clear();
                                if (mounted) {
                                  ref.read(notificationServiceProvider).showSuccess('上下文已清除');
                                }
                              },
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
                        borderRadius: BorderRadius.circular(4),
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