import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/image_session.dart';

class ImageHistoryService {
  static const String _boxName = 'image_history';
  static const String _key = 'sessions';
  
  Box? _cachedBox;

  Future<Box> _getBox() async {
    if (_cachedBox != null && _cachedBox!.isOpen) {
      return _cachedBox!;
    }
    if (!Hive.isBoxOpen(_boxName)) {
      _cachedBox = await Hive.openBox(_boxName);
    } else {
      _cachedBox = Hive.box(_boxName);
    }
    return _cachedBox!;
  }
  
  /// 清理资源，关闭 Hive box
  Future<void> dispose() async {
    try {
      if (_cachedBox != null && _cachedBox!.isOpen) {
        await _cachedBox!.close();
        _cachedBox = null;
        print('ImageHistoryService: Box closed');
      }
    } catch (e) {
      print('ImageHistoryService: Error closing box: $e');
    }
  }

  Future<List<ImageSession>> getSessions() async {
    try {
      final box = await _getBox();
      final List<dynamic>? jsonList = box.get(_key);

      if (jsonList != null) {
        return jsonList
            .map((item) => ImageSession.fromJson(json.decode(item as String)))
            .toList();
      }
    } catch (e) {
      print('ImageHistoryService: Error reading sessions: $e');
    }
    return [];
  }

  Future<void> saveSessions(List<ImageSession> sessions) async {
    try {
      final box = await _getBox();
      final jsonList = sessions.map((s) => json.encode(s.toJson())).toList();
      await box.put(_key, jsonList);
    } catch (e) {
      print('ImageHistoryService: Error saving sessions: $e');
    }
  }
}