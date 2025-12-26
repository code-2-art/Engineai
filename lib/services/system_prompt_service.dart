import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/system_prompt.dart';
import '../models/prompt/prompt_map.dart';

class SystemPromptService {
  static const String _boxName = 'system_prompts';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<List<SystemPrompt>> _getCustomPrompts() async {
    final box = await _getBox();
    final List<dynamic> rawList = box.get('prompts', defaultValue: []);
    return rawList.map((item) {
      if (item is String) {
        return SystemPrompt.fromJson(json.decode(item));
      }
      return SystemPrompt.fromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  Future<void> _saveCustomPrompts(List<SystemPrompt> prompts) async {
    final box = await _getBox();
    final data = prompts.map((p) => p.toJson()).toList();
    await box.put('prompts', data);
  }

  Future<List<SystemPrompt>> getCustomPrompts() async {
    return await _getCustomPrompts();
  }


  Future<List<SystemPrompt>> getAllPrompts() async {
    final predefined = getChatPromptMap().values.toList();
    final customs = await _getCustomPrompts();
    return [...predefined, ...customs];
  }


  Future<void> addPrompt(SystemPrompt prompt) async {
    final customs = await _getCustomPrompts();
    customs.add(prompt);
    await _saveCustomPrompts(customs);
  }

  Future<void> updatePrompt(SystemPrompt prompt) async {
    final customs = await _getCustomPrompts();
    final index = customs.indexWhere((p) => p.id == prompt.id);
    if (index != -1) {
      customs[index] = prompt;
      await _saveCustomPrompts(customs);
    }
  }

  Future<void> deletePrompt(String id) async {
    final customs = await _getCustomPrompts();
    customs.removeWhere((p) => p.id == id);
    await _saveCustomPrompts(customs);
  }

  Future<void> togglePrompt(String id) async {
    final customs = await _getCustomPrompts();
    final index = customs.indexWhere((p) => p.id == id);
    if (index != -1) {
      customs[index] = customs[index].copyWith(isEnabled: !customs[index].isEnabled);
      await _saveCustomPrompts(customs);
    }
  }

}
