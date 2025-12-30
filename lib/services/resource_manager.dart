import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'generation_task_manager.dart';
import 'chat_history_service.dart';
import 'image_history_service.dart';

/// 全局资源管理器，负责统一清理应用中的所有资源
class ResourceManager {
  final List<Future<void> Function()> _cleanupCallbacks = [];
  final List<void Function()> _syncCleanupCallbacks = [];
  bool _isDisposed = false;

  /// 注册异步清理回调
  void registerCleanup(Future<void> Function() callback) {
    if (!_isDisposed) {
      _cleanupCallbacks.add(callback);
    }
  }

  /// 注册同步清理回调
  void registerSyncCleanup(void Function() callback) {
    if (!_isDisposed) {
      _syncCleanupCallbacks.add(callback);
    }
  }

  /// 清理所有资源
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    print('=== RESOURCE MANAGER: Starting cleanup ===');

    // 先执行同步清理
    for (final callback in _syncCleanupCallbacks) {
      try {
        callback();
      } catch (e) {
        print('=== RESOURCE MANAGER: Sync cleanup error: $e ===');
      }
    }

    // 再执行异步清理
    for (final callback in _cleanupCallbacks) {
      try {
        await callback();
      } catch (e) {
        print('=== RESOURCE MANAGER: Async cleanup error: $e ===');
      }
    }

    print('=== RESOURCE MANAGER: Cleanup completed ===');
  }

  /// 检查是否已释放
  bool get isDisposed => _isDisposed;
}

/// 全局资源管理器 Provider
final resourceManagerProvider = Provider<ResourceManager>((ref) {
  final manager = ResourceManager();
  
  // 当 Provider 被释放时，自动清理资源
  ref.onDispose(() async {
    await manager.dispose();
  });
  
  return manager;
});

/// 初始化资源管理器，注册所有需要清理的资源
void initializeResourceManager(ProviderContainer container, {
  required ChatHistoryService chatHistoryService,
  required ImageHistoryService imageHistoryService,
}) {
  final resourceManager = container.read(resourceManagerProvider);

  // 注册任务管理器的清理
  resourceManager.registerSyncCleanup(() {
    final taskManager = container.read(taskManagerProvider);
    taskManager.dispose();
    print('=== RESOURCE MANAGER: TaskManager disposed ===');
  });

  // 注册 ChatHistoryService 的清理
  resourceManager.registerCleanup(() async {
    await chatHistoryService.dispose();
    print('=== RESOURCE MANAGER: ChatHistoryService disposed ===');
  });

  // 注册 ImageHistoryService 的清理
  resourceManager.registerCleanup(() async {
    await imageHistoryService.dispose();
    print('=== RESOURCE MANAGER: ImageHistoryService disposed ===');
  });

  // 注册 Hive 的全局清理
  resourceManager.registerCleanup(() async {
    await Hive.close();
    print('=== RESOURCE MANAGER: Hive closed ===');
  });

  print('=== RESOURCE MANAGER: Initialized ===');
}
