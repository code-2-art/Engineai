import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/generation_task.dart';

class TaskStorageService {
  static const String _tasksKey = 'generation_tasks';
  final SharedPreferences _prefs;

  TaskStorageService(this._prefs);

  // 保存任务列表
  Future<void> saveTasks(List<GenerationTask> tasks) async {
    final tasksJson = tasks.map((task) => task.toJson()).toList();
    await _prefs.setString(_tasksKey, json.encode(tasksJson));
  }

  // 加载任务列表
  Future<List<GenerationTask>> loadTasks() async {
    final tasksStr = _prefs.getString(_tasksKey);
    if (tasksStr == null) return [];
    
    try {
      final tasksJson = json.decode(tasksStr) as List;
      return tasksJson
          .map((json) => GenerationTask.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('加载任务失败: $e');
      return [];
    }
  }

  // 添加任务
  Future<void> addTask(GenerationTask task) async {
    final tasks = await loadTasks();
    tasks.add(task);
    await saveTasks(tasks);
  }

  // 更新任务
  Future<void> updateTask(GenerationTask updatedTask) async {
    final tasks = await loadTasks();
    final index = tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      tasks[index] = updatedTask;
      await saveTasks(tasks);
    }
  }

  // 删除任务
  Future<void> deleteTask(String taskId) async {
    final tasks = await loadTasks();
    tasks.removeWhere((t) => t.id == taskId);
    await saveTasks(tasks);
  }

  // 获取指定类型的任务
  Future<List<GenerationTask>> getTasksByType(TaskType type) async {
    final tasks = await loadTasks();
    return tasks.where((t) => t.type == type).toList();
  }

  // 获取运行中的任务
  Future<List<GenerationTask>> getRunningTasks() async {
    final tasks = await loadTasks();
    return tasks.where((t) => t.status == TaskStatus.running).toList();
  }

  // 清理已完成的任务（保留最近 N 个）
  Future<void> cleanupCompletedTasks({int keepCount = 10}) async {
    final tasks = await loadTasks();
    final completedTasks = tasks
        .where((t) => t.status == TaskStatus.completed)
        .toList()
      ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    
    if (completedTasks.length > keepCount) {
      final toRemove = completedTasks.skip(keepCount);
      for (final task in toRemove) {
        tasks.remove(task);
      }
      await saveTasks(tasks);
    }
  }
}
