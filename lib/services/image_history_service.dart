import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/image_session.dart';

class ImageHistoryService {
  static const String _boxName = 'image_history';
  static const String _key = 'sessions';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
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