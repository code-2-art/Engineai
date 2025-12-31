import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/generation_task.dart';
import 'task_storage_service.dart';
import 'llm_provider.dart';
import 'image_provider.dart';
import 'session_provider.dart';
import 'image_session_provider.dart';
import 'shared_prefs_service.dart';
import 'image_storage_service.dart';
import 'image_history_service.dart';

class GenerationTaskManager {
  final TaskStorageService _storage;
  final Uuid _uuid = const Uuid();
  
  // 任务状态缓存
  final Map<String, GenerationTask> _tasks = {};
  final Map<String, StreamController<GenerationTask>> _controllers = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  
  // 防抖和批量更新
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, String> _pendingResponses = {};
  final Map<String, Timer> _storageTimers = {};
  static const _debounceDelay = Duration(milliseconds: 50); // UI更新防抖
  static const _storageDelay = Duration(milliseconds: 500); // 存储写入防抖

  GenerationTaskManager(this._storage);
  
  final ImageStorageService _imageStorage = ImageStorageService();

  // 初始化：加载已保存的任务
  Future<void> init() async {
    final savedTasks = await _storage.loadTasks();
    for (final task in savedTasks) {
      _tasks[task.id] = task;
      
      // 如果有运行中的任务，恢复它们
      if (task.status == TaskStatus.running) {
        await _resumeTask(task);
      }
    }
  }

  // 获取任务
  GenerationTask? getTask(String taskId) {
    return _tasks[taskId];
  }

  // 获取指定类型的所有任务
  List<GenerationTask> getTasksByType(TaskType type) {
    return _tasks.values.where((t) => t.type == type).toList();
  }

  // 获取指定类型的运行中任务
  GenerationTask? getRunningTask(TaskType type) {
    return _tasks.values
        .where((t) => t.type == type && t.status == TaskStatus.running)
        .firstOrNull;
  }

  // 监听任务状态
  Stream<GenerationTask> watchTask(String taskId) {
    if (!_controllers.containsKey(taskId)) {
      _controllers[taskId] = StreamController<GenerationTask>.broadcast();
    }
    return _controllers[taskId]!.stream;
  }

  // 创建 Chat 任务
  Future<String> createChatTask(
    String sessionId,
    String prompt,
    List<Map<String, dynamic>>? userContentParts,
    String? systemPrompt,
    WidgetRef ref,
  ) async {
    final taskId = _uuid.v4();
    final task = GenerationTask(
      id: taskId,
      type: TaskType.chat,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      sessionId: sessionId,
      params: {
        'prompt': prompt,
        'userContentParts': userContentParts,
        'systemPrompt': systemPrompt,
      },
    );
    
    await _addTask(task);
    await _startChatTask(task, ref);
    return taskId;
  }

  // 创建 Image 任务
  Future<String> createImageTaskPending(
    String sessionId,
    String prompt,
    List<String>? base64Images,
  ) async {
    final taskId = _uuid.v4();
    print('TaskManager: Created image task $taskId');
    final task = GenerationTask(
      id: taskId,
      type: TaskType.image,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      sessionId: sessionId,
      params: {
        'prompt': prompt,
        'base64Images': base64Images,
      },
    );
    
    await _addTask(task);
    return taskId;
  }

  Future<String> createImageTask(
    String sessionId,
    String prompt,
    List<String>? base64Images,
    WidgetRef ref,
  ) async {
    final taskId = await createImageTaskPending(sessionId, prompt, base64Images);
    await _startImageTask(_tasks[taskId]!, ref);
    return taskId;
  }

  Future<void> startImageTask(String taskId, WidgetRef ref) async {
    final task = _tasks[taskId];
    if (task == null) throw Exception('Task $taskId not found');
    await _startImageTask(task, ref);
  }

  // 暂停任务
  Future<void> pauseTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != TaskStatus.running) return;

    final updatedTask = task.copyWith(status: TaskStatus.paused);
    await _updateTask(updatedTask);
    
    // 取消订阅
    _subscriptions[taskId]?.cancel();
    _subscriptions.remove(taskId);
  }

  // 恢复任务
  Future<void> resumeTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != TaskStatus.paused) return;

    await _resumeTask(task);
  }

  // 取消任务
  Future<void> cancelTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    final updatedTask = task.copyWith(
      status: TaskStatus.cancelled,
      completedAt: DateTime.now(),
    );
    await _updateTask(updatedTask);
    
    // 取消订阅
    _subscriptions[taskId]?.cancel();
    _subscriptions.remove(taskId);
  }

  // 内部方法：添加任务
  Future<void> _addTask(GenerationTask task) async {
    _tasks[task.id] = task;
    await _storage.addTask(task);
    _notifyTaskUpdate(task);
  }

  // 内部方法：更新任务
  Future<void> _updateTask(GenerationTask task) async {
    print('TaskManager: Updating task ${task.id} to ${task.status}');
    _tasks[task.id] = task;
    await _storage.updateTask(task);
    _notifyTaskUpdate(task);
  }

  // 内部方法：通知任务更新
  void _notifyTaskUpdate(GenerationTask task) {
    print('TaskManager: Notifying task ${task.id} status ${task.status}');
    _controllers[task.id]?.add(task);
  }

  // 内部方法：启动 Chat 任务
  Future<void> _startChatTask(GenerationTask task, WidgetRef ref) async {
    final updatedTask = task.copyWith(status: TaskStatus.running);
    await _updateTask(updatedTask);

    try {
      final llm = await ref.read(chatLlmProvider.future);
      final prompt = task.params['prompt'] as String;
      final userContentParts = task.params['userContentParts'] as List<Map<String, dynamic>>?;
      final systemPrompt = task.params['systemPrompt'] as String?;

      final stream = llm.generateStream(
        [],
        prompt,
        userContentParts: userContentParts,
        systemPrompt: systemPrompt ?? '',
      );

      final subscription = stream.listen(
        (delta) {
          final currentTask = _tasks[task.id];
          if (currentTask == null) return;
          
          // 累积响应内容
          _pendingResponses[task.id] = (_pendingResponses[task.id] ?? currentTask.currentResponse ?? '') + delta;
          
          // 防抖：延迟更新UI和存储
          _debounceTimers[task.id]?.cancel();
          _debounceTimers[task.id] = Timer(_debounceDelay, () {
            final newResponse = _pendingResponses[task.id] ?? '';
            if (newResponse.isNotEmpty) {
              final updatedTask = currentTask.copyWith(currentResponse: newResponse);
              _tasks[task.id] = updatedTask;
              _notifyTaskUpdate(updatedTask);
              
              // 延迟存储到磁盘，避免频繁IO
              _storageTimers[task.id]?.cancel();
              _storageTimers[task.id] = Timer(_storageDelay, () {
                _storage.updateTask(updatedTask);
              });
            }
          });
        },
        onDone: () async {
          // 取消所有定时器
          _debounceTimers[task.id]?.cancel();
          _storageTimers[task.id]?.cancel();
          
          final currentTask = _tasks[task.id];
          if (currentTask == null) return;
          
          // 确保最后的响应被保存
          final finalResponse = _pendingResponses[task.id] ?? currentTask.currentResponse ?? '';
          _pendingResponses.remove(task.id);
          
          final updatedTask = currentTask.copyWith(
            status: TaskStatus.completed,
            completedAt: DateTime.now(),
            currentResponse: finalResponse,
          );
          await _updateTask(updatedTask);
          _subscriptions.remove(task.id);
          _debounceTimers.remove(task.id);
          _storageTimers.remove(task.id);
        },
        onError: (e) async {
          // 取消所有定时器
          _debounceTimers[task.id]?.cancel();
          _storageTimers[task.id]?.cancel();
          
          final currentTask = _tasks[task.id];
          if (currentTask == null) return;
          
          final finalResponse = _pendingResponses[task.id] ?? currentTask.currentResponse ?? '';
          _pendingResponses.remove(task.id);
          
          final updatedTask = currentTask.copyWith(
            status: TaskStatus.failed,
            completedAt: DateTime.now(),
            error: e.toString(),
            currentResponse: finalResponse,
          );
          await _updateTask(updatedTask);
          _subscriptions.remove(task.id);
          _debounceTimers.remove(task.id);
          _storageTimers.remove(task.id);
        },
      );

      _subscriptions[task.id] = subscription;
    } catch (e) {
      final updatedTask = task.copyWith(
        status: TaskStatus.failed,
        completedAt: DateTime.now(),
        error: e.toString(),
      );
      await _updateTask(updatedTask);
    }
  }

  // 内部方法：启动 Image 任务
  Future<void> _startImageTask(GenerationTask task, WidgetRef ref) async {
    print('TaskManager: Starting image task ${task.id}');
    final updatedTask = task.copyWith(status: TaskStatus.running);
    await _updateTask(updatedTask);
    print('TaskManager: Task ${task.id} set to running');

    try {
      print('TaskManager: Getting generator');
      final generator = await ref.read(imageGeneratorProvider.future);
      print('TaskManager: Generator ready');
      final prompt = task.params['prompt'] as String;
      final base64Images = task.params['base64Images'] as List<String>?;
      print('TaskManager: Calling generateImage, prompt len: ${prompt.length}, images: ${base64Images?.length ?? 0}');

      final result = await generator.generateImage(
        prompt,
        base64Images: base64Images,
      );
      print('TaskManager: generateImage done, bytes: ${result.imageBytes?.length ?? 0}');

      // 检查任务是否已被取消
      final currentTask = _tasks[task.id];
      if (currentTask == null || currentTask.status == TaskStatus.cancelled) {
        print('TaskManager: Task ${task.id} was cancelled, ignoring result');
        return;
      }

      if (result.imageBytes != null) {
        final updatedTask = task.copyWith(
          status: TaskStatus.completed,
          completedAt: DateTime.now(),
          generatedImage: result.imageBytes,
          currentResponse: result.description,
        );
        await _updateTask(updatedTask);
        print('TaskManager: Task ${task.id} set to completed');
      } else {
        throw Exception('No image bytes returned');
      }
    } catch (e) {
      // 检查任务是否已被取消
      final currentTask = _tasks[task.id];
      if (currentTask == null || currentTask.status == TaskStatus.cancelled) {
        print('TaskManager: Task ${task.id} was cancelled, ignoring error');
        return;
      }
      
      print('TaskManager: Image task ${task.id} error: $e');
      final updatedTask = task.copyWith(
        status: TaskStatus.failed,
        completedAt: DateTime.now(),
        error: e.toString(),
      );
      await _updateTask(updatedTask);
      print('TaskManager: Task ${task.id} set to failed');
    }
  }

  // 内部方法：恢复任务
  Future<void> _resumeTask(GenerationTask task) async {
    print('恢复任务: ${task.id}, 类型: ${task.type}, 状态: ${task.status}');
    
    if (task.type == TaskType.image) {
      // 对于 Image 任务，检查是否已经生成了图片
      // 通过检查 session 中最后一条消息是否有图片引用来判断
      final currentSessionId = task.sessionId;
      if (currentSessionId != null) {
        try {
          // 尝试检查 session 中是否有对应的图片
          // 由于这里没有直接访问 ImageHistoryService 的方式，
          // 我们简化处理：重启后将 running 状态的任务标记为 failed
          // 因为重启后无法继续生成
          print('Image任务 ${task.id} 在重启后无法恢复，标记为失败');
          final updatedTask = task.copyWith(
            status: TaskStatus.failed,
            completedAt: DateTime.now(),
            error: '应用程序重启，图像生成任务已中断',
          );
          await _updateTask(updatedTask);
        } catch (e) {
          print('恢复 Image 任务失败: $e');
        }
      }
    } else if (task.type == TaskType.chat) {
      // 对于 Chat 任务，重启后也无法恢复流式生成
      print('Chat任务 ${task.id} 在重启后无法恢复，标记为失败');
      final updatedTask = task.copyWith(
        status: TaskStatus.failed,
        completedAt: DateTime.now(),
        error: '应用程序重启，对话生成任务已中断',
      );
      await _updateTask(updatedTask);
    }
  }

  // 清理资源
  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    for (final timer in _storageTimers.values) {
      timer.cancel();
    }
    _controllers.clear();
    _subscriptions.clear();
    _debounceTimers.clear();
    _storageTimers.clear();
    _pendingResponses.clear();
  }
}

// Provider
final taskStorageServiceProvider = Provider<TaskStorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TaskStorageService(prefs);
});

final taskManagerProvider = Provider<GenerationTaskManager>((ref) {
  final manager = GenerationTaskManager(ref.watch(taskStorageServiceProvider));
  ref.onDispose(() => manager.dispose());
  return manager;
});
