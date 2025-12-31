import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/image_session.dart';
import '../models/image_message.dart';
import 'image_storage_service.dart';

class ImageHistoryService {
  static const String _boxName = 'image_history_meta';
  static const String _key = 'sessions';
  
  Box? _cachedBox;
  final ImageStorageService _imageStorage = ImageStorageService();

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

  /// 获取会话列表（只包含元数据，不包含图片数据）
  Future<List<ImageSession>> getSessions() async {
    try {
      final box = await _getBox();
      final List<dynamic>? jsonList = box.get(_key);

      print('ImageHistoryService: getSessions - jsonList: $jsonList');
      
      if (jsonList != null) {
        final sessions = jsonList
            .map((item) => _parseSession(json.decode(item as String)))
            .toList();
        print('ImageHistoryService: getSessions - 返回 ${sessions.length} 个会话');
        return sessions;
      }
    } catch (e) {
      print('ImageHistoryService: Error reading sessions: $e');
    }
    print('ImageHistoryService: getSessions - 返回空列表');
    return [];
  }

  /// 解析会话，自动检测新旧格式
  ImageSession _parseSession(Map<String, dynamic> json) {
    // 检测是否为新格式（包含 imageRef 字段）
    final messages = (json['messages'] as List<dynamic>)
        .map((m) => _parseMessage(m as Map<String, dynamic>))
        .toList();
    
    return ImageSession(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: messages,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// 解析消息，自动检测新旧格式
  ImageMessage _parseMessage(Map<String, dynamic> json) {
    // 检测是否为新格式（包含 imageRef 字段）
    if (json.containsKey('imageRef')) {
      return ImageMessage.fromJson(json);
    } else {
      // 旧格式，需要迁移
      return ImageMessage.fromLegacyJson(json);
    }
  }

  /// 保存会话列表（只保存元数据）
  Future<void> saveSessions(List<ImageSession> sessions) async {
    try {
      print('ImageHistoryService: saveSessions - 保存 ${sessions.length} 个会话');
      final box = await _getBox();
      final jsonList = sessions.map((s) => json.encode(s.toJson())).toList();
      await box.put(_key, jsonList);
      print('ImageHistoryService: saveSessions - 保存完成');
    } catch (e) {
      print('ImageHistoryService: Error saving sessions: $e');
    }
  }

  /// 加载指定会话的所有图片数据
  /// 返回包含缓存图片数据的会话副本
  Future<ImageSession> loadSessionWithImages(ImageSession session) async {
    final messagesWithImages = <ImageMessage>[];
    
    print('ImageHistoryService: loadSessionWithImages - 会话ID: ${session.id}');
    print('ImageHistoryService: loadSessionWithImages - 消息数量: ${session.messages.length}');
    
    for (int i = 0; i < session.messages.length; i++) {
      final msg = session.messages[i];
      print('ImageHistoryService: loadSessionWithImages - 消息[$i]: prompt="${msg.prompt}", imageRef="${msg.imageRef}", hasCached=${msg.hasCachedImageData}');
      
      if (msg.imageRef != null && msg.imageRef!.isNotEmpty) {
        // 从文件系统加载图片
        print('ImageHistoryService: loadSessionWithImages - 尝试加载图片 ${msg.imageRef}');
        final imageData = await _imageStorage.loadImage(msg.imageRef!);
        if (imageData != null) {
          print('ImageHistoryService: loadSessionWithImages - 图片 ${msg.imageRef} 加载成功，大小: ${imageData.length}');
          final copiedMsg = msg.copyWith();
          copiedMsg.setCachedImageData(imageData);
          print('ImageHistoryService: loadSessionWithImages - 复制后消息 hasCached=${copiedMsg.hasCachedImageData}, cachedSize=${copiedMsg.cachedImageData?.length}');
          messagesWithImages.add(copiedMsg);
        } else {
          print('ImageHistoryService: loadSessionWithImages - 图片 ${msg.imageRef} 加载失败');
          messagesWithImages.add(msg);
        }
      } else if (msg.hasCachedImageData) {
        // 已经有缓存数据
        print('ImageHistoryService: loadSessionWithImages - 消息已有缓存数据，大小: ${msg.cachedImageData?.length}');
        messagesWithImages.add(msg);
      } else {
        print('ImageHistoryService: loadSessionWithImages - 消息无图片数据');
        messagesWithImages.add(msg);
      }
    }
    
    print('ImageHistoryService: loadSessionWithImages - 会话 ${session.id} 加载完成，返回 ${messagesWithImages.length} 条消息');
    final result = session.copyWith(messages: messagesWithImages);
    print('ImageHistoryService: loadSessionWithImages - 返回会话消息数量: ${result.messages.length}');
    return result;
  }

  /// 迁移旧格式的数据到新格式
  /// 将旧格式中嵌入的 base64 图片保存到文件系统
  Future<void> migrateLegacyData() async {
    try {
      print('ImageHistoryService: Starting legacy data migration');
      final sessions = await getSessions();
      bool needsMigration = false;

      for (final session in sessions) {
        final newMessages = <ImageMessage>[];
        bool sessionNeedsMigration = false;

        for (final msg in session.messages) {
          // 检查是否有缓存的旧格式图片数据
          if (msg.cachedImageData != null && msg.cachedImageData!.isNotEmpty && msg.imageRef == null) {
            // 保存图片到文件系统
            final imageRef = await _imageStorage.saveImage(msg.cachedImageData!);
            final newMsg = ImageMessage(
              prompt: msg.prompt,
              imageRef: imageRef,
              aiDescription: msg.aiDescription,
              timestamp: msg.timestamp,
              isSeparator: msg.isSeparator,
            );
            newMessages.add(newMsg);
            sessionNeedsMigration = true;
          } else {
            newMessages.add(msg);
          }
        }

        if (sessionNeedsMigration) {
          final updatedSession = session.copyWith(messages: newMessages);
          // 更新会话列表
          final allSessions = await getSessions();
          final index = allSessions.indexWhere((s) => s.id == session.id);
          if (index != -1) {
            allSessions[index] = updatedSession;
            await saveSessions(allSessions);
          }
          needsMigration = true;
        }
      }

      if (needsMigration) {
        print('ImageHistoryService: Legacy data migration completed');
      } else {
        print('ImageHistoryService: No legacy data to migrate');
      }
    } catch (e) {
      print('ImageHistoryService: Error during migration: $e');
    }
  }

  /// 清理孤立的图片文件
  Future<void> cleanupOrphanedImages() async {
    try {
      final sessions = await getSessions();
      final validImageRefs = <String>[];

      // 收集所有有效的图片引用
      for (final session in sessions) {
        for (final msg in session.messages) {
          if (msg.imageRef != null && msg.imageRef!.isNotEmpty) {
            validImageRefs.add(msg.imageRef!);
          }
        }
      }

      // 清理孤立的图片
      final cleanedCount = await _imageStorage.cleanupOrphanedImages(validImageRefs);
      if (cleanedCount > 0) {
        print('ImageHistoryService: Cleaned up $cleanedCount orphaned images');
      }
    } catch (e) {
      print('ImageHistoryService: Error cleaning orphaned images: $e');
    }
  }

  /// 删除会话并清理相关图片
  Future<void> deleteSession(String sessionId) async {
    try {
      final sessions = await getSessions();
      final sessionIndex = sessions.indexWhere((s) => s.id == sessionId);
      
      if (sessionIndex != -1) {
        final session = sessions[sessionIndex];
        
        // 收集要删除的图片引用
        final imageRefsToDelete = <String>[];
        for (final msg in session.messages) {
          if (msg.imageRef != null && msg.imageRef!.isNotEmpty) {
            imageRefsToDelete.add(msg.imageRef!);
          }
        }
        
        // 删除图片文件
        await _imageStorage.deleteImages(imageRefsToDelete);
        
        // 删除会话
        sessions.removeAt(sessionIndex);
        await saveSessions(sessions);
        
        print('ImageHistoryService: Deleted session $sessionId and ${imageRefsToDelete.length} images');
      }
    } catch (e) {
      print('ImageHistoryService: Error deleting session: $e');
    }
  }

  /// 清空所有数据和图片
  Future<void> clearAll() async {
    try {
      await saveSessions([]);
      await _imageStorage.clearAllImages();
      print('ImageHistoryService: Cleared all sessions and images');
    } catch (e) {
      print('ImageHistoryService: Error clearing all data: $e');
    }
  }

  /// 获取存储统计信息
  Future<Map<String, dynamic>> getStorageStats() async {
    try {
      final sessions = await getSessions();
      final imageCount = await _imageStorage.getImageCount();
      final storageSize = await _imageStorage.getTotalStorageSize();
      
      int totalMessages = 0;
      for (final session in sessions) {
        totalMessages += session.messages.length;
      }

      return {
        'sessionCount': sessions.length,
        'messageCount': totalMessages,
        'imageCount': imageCount,
        'storageSize': storageSize,
        'storageSizeMB': (storageSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      print('ImageHistoryService: Error getting storage stats: $e');
      return {};
    }
  }
}
