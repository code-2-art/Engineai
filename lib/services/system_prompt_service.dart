import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/system_prompt.dart';
import '../models/prompt/prompt_map.dart';

class SystemPromptNotifier extends StateNotifier<List<SystemPrompt>> {
  static const String _boxName = 'system_prompts';
  Box<dynamic>? _box;

  SystemPromptNotifier() : super([]) {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(_boxName);
    _loadCustomPrompts();
  }

  void _loadCustomPrompts() {
    if (_box == null) return;
    final List<dynamic> rawList = _box!.get('prompts', defaultValue: <dynamic>[]);
    state = rawList.map((item) {
      Map<String, dynamic> jsonMap;
      if (item is String) {
        jsonMap = json.decode(item) as Map<String, dynamic>;
      } else {
        jsonMap = Map<String, dynamic>.from(item as Map);
      }
      return SystemPrompt.fromJson(jsonMap);
    }).where((p) => !getChatPromptMap().containsKey(p.id)).toList();
  }

  Future<void> addPrompt(SystemPrompt prompt) async {
    if (_box == null) return;
    state = [...state, prompt];
    await _save();
  }

  Future<void> updatePrompt(SystemPrompt prompt) async {
    if (_box == null) return;
    final index = state.indexWhere((p) => p.id == prompt.id);
    if (index != -1) {
      state = List<SystemPrompt>.from(state)..[index] = prompt;
      await _save();
    }
  }

  Future<void> deletePrompt(String id) async {
    if (_box == null) return;
    state = state.where((p) => p.id != id).toList();
    await _save();
  }

  Future<void> togglePrompt(String id) async {
    if (_box == null) return;
    final index = state.indexWhere((p) => p.id == id);
    if (index != -1) {
      final updated = state[index].copyWith(isEnabled: !state[index].isEnabled);
      state = List<SystemPrompt>.from(state)..[index] = updated;
      await _save();
    }
  }

  Future<void> _save() async {
    if (_box == null) return;
    final data = state.map((p) => p.toJson()).toList();
    await _box!.put('prompts', data);
  }
}

final systemPromptNotifierProvider = StateNotifierProvider<SystemPromptNotifier, List<SystemPrompt>>((ref) => SystemPromptNotifier());

final customPromptsProvider = Provider<List<SystemPrompt>>((ref) => ref.watch(systemPromptNotifierProvider));

final allSystemPromptsProvider = Provider<List<SystemPrompt>>((ref) {
  final customs = ref.watch(systemPromptNotifierProvider);
  return [...customs, ...getChatPromptMap().values.toList()];
});

final enabledSystemPromptsProvider = Provider<List<SystemPrompt>>((ref) {
  final allPrompts = ref.watch(allSystemPromptsProvider);
  return allPrompts.where((p) => p.isEnabled).toList();
});
