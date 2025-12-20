import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/system_prompt.dart';

class SystemPromptService {
  static const String _boxName = 'system_prompts';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<List<SystemPrompt>> getAllPrompts() async {
    final box = await _getBox();
    final List<dynamic> rawList = box.get('prompts', defaultValue: []);
    return rawList.map((item) {
      if (item is String) {
        return SystemPrompt.fromJson(json.decode(item));
      }
      return SystemPrompt.fromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  Future<void> savePrompts(List<SystemPrompt> prompts) async {
    final box = await _getBox();
    final data = prompts.map((p) => p.toJson()).toList();
    await box.put('prompts', data);
  }

  Future<void> addPrompt(SystemPrompt prompt) async {
    final prompts = await getAllPrompts();
    prompts.add(prompt);
    await savePrompts(prompts);
  }

  Future<void> updatePrompt(SystemPrompt prompt) async {
    final prompts = await getAllPrompts();
    final index = prompts.indexWhere((p) => p.id == prompt.id);
    if (index != -1) {
      prompts[index] = prompt;
      await savePrompts(prompts);
    }
  }

  Future<void> deletePrompt(String id) async {
    final prompts = await getAllPrompts();
    prompts.removeWhere((p) => p.id == id);
    await savePrompts(prompts);
  }

  Future<void> togglePrompt(String id) async {
    final prompts = await getAllPrompts();
    final index = prompts.indexWhere((p) => p.id == id);
    if (index != -1) {
      prompts[index] = prompts[index].copyWith(isEnabled: !prompts[index].isEnabled);
      await savePrompts(prompts);
    }
  }
}
