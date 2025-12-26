import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mcp_config.dart';
class McpStorageService {
  static const String _key = 'mcp_config_json';

  Future<List<McpServerConfig>> readConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> data = json.decode(jsonString);
        return data.map((dynamic item) => McpServerConfig.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        return [];
      }
    } catch (e) {
      print('McpStorageService: Error reading config: $e');
      return [];
    }
  }

  Future<void> saveConfig(List<McpServerConfig> configs) async {
    final List<Map<String, dynamic>> data = configs.map((c) => c.toJson()).toList();
    final jsonContent = json.encode(data);
    print('McpStorageService: Saving config to SharedPreferences...');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonContent);
    print('McpStorageService: Config saved to SharedPreferences.');
  }
}