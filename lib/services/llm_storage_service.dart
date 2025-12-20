import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LLMStorageService {
  static const String _boxName = 'llm_config';
  static const String _key = 'config_json';
  static const String _assetPath = 'assets/config/llm.json';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<Map<String, dynamic>> readConfig() async {
    try {
      final box = await _getBox();
      final jsonString = box.get(_key);

      if (jsonString != null && jsonString.isNotEmpty) {
        print('LLMStorageService: Found persisted config in Hive Database.');
        return json.decode(jsonString);
      } else {
        print('LLMStorageService: No persisted config, loading defaults from assets.');
        // Fallback to assets
        final configString = await rootBundle.loadString(_assetPath);
        final config = json.decode(configString);
        // Save default to local so it exists for next time
        await saveConfig(config);
        return config;
      }
    } catch (e) {
      print('LLMStorageService: Error reading config: $e');
      final configString = await rootBundle.loadString(_assetPath);
      return json.decode(configString);
    }
  }

  Future<void> saveConfig(Map<String, dynamic> config) async {
    final jsonContent = json.encode(config);
    print('LLMStorageService: Saving config to Hive Database...');
    final box = await _getBox();
    await box.put(_key, jsonContent);
    print('LLMStorageService: Config saved to Hive.');
  }
}
