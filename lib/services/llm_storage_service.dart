import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
class LLMStorageService {
  static const String _key = 'llm_config_json';
  static const String _assetPath = 'assets/config/llm.json';

  Future<Map<String, dynamic>> readConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key);

      if (jsonString != null && jsonString.isNotEmpty) {
        print('LLMStorageService: Found persisted config in SharedPreferences.');
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
    print('LLMStorageService: Saving config to SharedPreferences...');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonContent);
    print('LLMStorageService: Config saved to SharedPreferences.');
  }
}
