import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/mcp_config.dart';

class McpStorageService {
  static const String _boxName = 'mcp_config';
  static const String _key = 'config_json';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<List<McpServerConfig>> readConfig() async {
    try {
      final box = await _getBox();
      final jsonString = box.get(_key);
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
    print('McpStorageService: Saving config to Hive Database...');
    final box = await _getBox();
    await box.put(_key, jsonContent);
    print('McpStorageService: Config saved to Hive.');
  }
}