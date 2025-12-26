import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/image_session.dart';
import '../models/image_message.dart';

class ImageDatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'image_history.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE image_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE image_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        prompt TEXT NOT NULL,
        image BLOB NOT NULL,
        ai_description TEXT,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES image_sessions (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<List<ImageSession>> getSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'image_sessions',
      orderBy: 'created_at DESC',
    );
    final List<ImageSession> sessions = [];
    for (final map in maps) {
      final messages = await getMessages(map['id'] as String);
      sessions.add(ImageSession(
        id: map['id'] as String,
        title: map['title'] as String,
        messages: messages,
        createdAt: DateTime.parse(map['created_at'] as String),
      ));
    }
    return sessions;
  }

  Future<List<ImageMessage>> getMessages(String sessionId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'image_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) {
      final map = Map<String, dynamic>.from(maps[i]);
      map['imageBase64'] = base64Encode(map['image'] as Uint8List);
      map.remove('image');
      map.remove('session_id');
      return ImageMessage.fromJson(map);
    });
  }

  Future<void> saveSession(ImageSession session) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'image_sessions',
        {
          'id': session.id,
          'title': session.title,
          'created_at': session.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'image_messages',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      for (final msg in session.messages) {
        final msgJson = msg.toJson();
        final imageBytes = base64Decode(msgJson['imageBase64'] as String);
        await txn.insert(
          'image_messages',
          {
            'id': msgJson['id'] as String? ?? Uuid().v4(),
            'session_id': session.id,
            'prompt': msgJson['prompt'] as String,
            'image': imageBytes,
            'ai_description': msgJson['aiDescription'],
            'timestamp': msgJson['timestamp'] as String,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> migrateFromHive() async {
    try {
      final boxName = 'image_history';
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);

      final jsonList = box.get('sessions') as List<dynamic>?;
      if (jsonList != null) {
        for (final item in jsonList) {
          if (item is String) {
            final sessionMap = json.decode(item) as Map<String, dynamic>;
            final session = ImageSession.fromJson(sessionMap);
            await saveSession(session);
          }
        }
      }

      await box.clear();
    } catch (e) {
      print('Image migration error: $e');
    }
  }

  Future<ImageSession?> getSessionById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'image_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    final map = maps.first;
    final messages = await getMessages(id);
    return ImageSession(
      id: map['id'] as String,
      title: map['title'] as String,
      messages: messages,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Future<void> deleteSession(String id) async {
    final db = await database;
    await db.delete('image_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}