import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/chat_session.dart';

class ChatDatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'chat_history.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        system_prompt TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        text TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        sender TEXT,
        content_parts TEXT,
        is_system INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<List<ChatSession>> getSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sessions',
      orderBy: 'created_at DESC',
      limit: 2,
    );
    final List<ChatSession> sessions = [];
    for (final map in maps) {
      final messages = await getMessages(map['id'] as String);
      sessions.add(ChatSession(
        id: map['id'] as String,
        title: map['title'] as String,
        systemPrompt: map['system_prompt'] as String?,
        messages: messages,
        createdAt: DateTime.parse(map['created_at'] as String),
      ));
    }
    return sessions;
  }

  Future<List<Message>> getMessages(String sessionId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) => Message.fromJson(Map<String, dynamic>.from(maps[i])));
  }

  Future<void> saveSession(ChatSession session) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'sessions',
        {
          'id': session.id,
          'title': session.title,
          'system_prompt': session.systemPrompt,
          'created_at': session.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'messages',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      for (final msg in session.messages) {
        await txn.insert(
          'messages',
          {
            ...msg.toJson(),
            'session_id': session.id,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<SessionSummary>> getSummaries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sessions',
      columns: ['id', 'title', 'created_at'],
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => SessionSummary.fromJson(Map<String, dynamic>.from(maps[i])));
  }

  Future<void> migrateFromHive() async {
    try {
      final boxName = 'chat_history';
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);

      // Migrate summaries
      final summariesJson = box.get('history_summaries');
      if (summariesJson != null) {
        // Skip or update if needed
      }

      // Migrate individual sessions
      final keys = box.keys.where((k) => k != 'sessions' && k != 'history_summaries').toList();
      for (final key in keys) {
        final jsonStr = box.get(key);
        if (jsonStr is String) {
          final sessionMap = json.decode(jsonStr) as Map<String, dynamic>;
          final session = ChatSession.fromJson(sessionMap);
          await saveSession(session);
        }
      }

      // Clear Hive data after migration
      await box.clear();
    } catch (e) {
      print('Migration error: $e');
    }
  }

  Future<ChatSession?> getSessionById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    final map = maps.first;
    final messages = await getMessages(id);
    return ChatSession(
      id: map['id'] as String,
      title: map['title'] as String,
      systemPrompt: map['system_prompt'] as String?,
      messages: messages,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Future<void> deleteSession(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
      // messages deleted by CASCADE
    });
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}