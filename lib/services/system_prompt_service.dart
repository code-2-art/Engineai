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
  
  Future<void> ensureInit() async {
    if (_box == null) {
      await _init();
    }
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
    }).toList();
  }

  Future<void> addPrompt(SystemPrompt prompt) async {
    await ensureInit();
    state = [...state, prompt];
    await _save();
  }

  Future<void> updatePrompt(SystemPrompt prompt) async {
    await ensureInit();
    final index = state.indexWhere((p) => p.id == prompt.id);
    if (index != -1) {
      state = List<SystemPrompt>.from(state)..[index] = prompt;
      await _save();
    }
  }

  Future<void> deletePrompt(String id) async {
    await ensureInit();
    state = state.where((p) => p.id != id).toList();
    await _save();
  }

  Future<void> togglePrompt(String id) async {
    await ensureInit();
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
  final customs = ref.watch(systemPromptNotifierProvider).where((c) => !getChatPromptMap().containsKey(c.id)).toList();
  final builtins = ref.watch(builtinPromptsProvider);
  return [...customs, ...builtins];
});

final enabledSystemPromptsProvider = Provider<List<SystemPrompt>>((ref) {
  final allPrompts = ref.watch(allSystemPromptsProvider);
  return allPrompts.where((p) => p.isEnabled).toList();
});

class BuiltinPromptNotifier extends StateNotifier<Map<String, bool>> {
  static const String _builtinKey = 'builtin_enables';
  Box<dynamic>? _box;

  BuiltinPromptNotifier() : super({}) {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(SystemPromptNotifier._boxName);
    _load();
  }
  
  Future<void> ensureInit() async {
    if (_box == null) {
      await _init();
    }
  }

  void _load() {
    if (_box == null) return;
    final rawStr = _box!.get(_builtinKey, defaultValue: '{}') as String;
    final Map<String, dynamic> rawMap = json.decode(rawStr);
    state = rawMap.map((k, v) => MapEntry(k, v as bool));
  }

  Future<void> toggleBuiltin(String id) async {
    await ensureInit();
    final current = state[id] ?? true;
    state = Map<String, bool>.from(state)..[id] = !current;
    await _save();
  }

  Future<void> _save() async {
    if (_box == null) return;
    await _box!.put(_builtinKey, json.encode(state));
  }
}

final builtinPromptNotifierProvider = StateNotifierProvider<BuiltinPromptNotifier, Map<String, bool>>((ref) => BuiltinPromptNotifier());

final builtinPromptsProvider = Provider<List<SystemPrompt>>((ref) {
  final enables = ref.watch(builtinPromptNotifierProvider);
  final map = getChatPromptMap();
  return map.entries.map((e) => e.value.copyWith(isEnabled: enables[e.key] ?? true)).toList();
});
