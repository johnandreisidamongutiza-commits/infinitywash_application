import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalAvatarRecord {
  final String userId;
  final String? avatarUrl;
  final String? localPath;
  final bool isSynced;
  final DateTime updatedAt;

  LocalAvatarRecord({
    required this.userId,
    this.avatarUrl,
    this.localPath,
    this.isSynced = true,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'avatar_url': avatarUrl,
        'local_path': localPath,
        'is_synced': isSynced ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory LocalAvatarRecord.fromMap(Map<String, dynamic> map) => LocalAvatarRecord(
        userId: map['user_id'] as String,
        avatarUrl: map['avatar_url'] as String?,
        localPath: map['local_path'] as String?,
        isSynced: (map['is_synced'] as int? ?? 1) == 1,
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// SQLite-backed local cache for user profile pictures.
/// Stores the photo locally in SQLite first so that even if cloud uploads
/// or network connections fail, the photo is preserved and displayed instantly.
class ProfileLocalDatabase {
  static final ProfileLocalDatabase instance = ProfileLocalDatabase._init();
  static Database? _database;

  ProfileLocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('profile_avatars.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profile_avatars (
        user_id TEXT PRIMARY KEY,
        avatar_url TEXT,
        local_path TEXT,
        is_synced INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE profile_avatars ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 1');
      } catch (_) {}
    }
  }

  /// Copies an image file to app storage and stores its record in SQLite FIRST.
  /// Sets [isSynced] to false by default until Firebase upload completes.
  Future<String> saveLocalImage({
    required String userId,
    required File sourceFile,
    String? avatarUrl,
    bool isSynced = false,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory(join(appDir.path, 'avatars'));
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }

    final ext = sourceFile.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final targetPath = join(avatarsDir.path, '${userId}_profile.$ext');

    // Copy to persistent application documents directory
    await sourceFile.copy(targetPath);

    final record = LocalAvatarRecord(
      userId: userId,
      avatarUrl: avatarUrl,
      localPath: targetPath,
      isSynced: isSynced,
      updatedAt: DateTime.now(),
    );

    final db = await database;
    await db.insert(
      'profile_avatars',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return targetPath;
  }

  /// Marks a local avatar as successfully synced to Firebase Storage & Supabase.
  Future<void> markSynced({
    required String userId,
    required String avatarUrl,
  }) async {
    final db = await database;
    await db.update(
      'profile_avatars',
      {
        'avatar_url': avatarUrl,
        'is_synced': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Retrieves an unsynced avatar record for the user if cloud upload is still pending.
  Future<LocalAvatarRecord?> getPendingUpload(String userId) async {
    final db = await database;
    final results = await db.query(
      'profile_avatars',
      where: 'user_id = ? AND is_synced = 0',
      whereArgs: [userId],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final record = LocalAvatarRecord.fromMap(results.first);
    if (record.localPath != null && record.localPath!.isNotEmpty) {
      final file = File(record.localPath!);
      if (await file.exists()) {
        return record;
      }
    }
    return null;
  }

  /// Saves downloaded remote avatar bytes to local disk & SQLite.
  Future<String> saveDownloadedBytes({
    required String userId,
    required Uint8List bytes,
    required String avatarUrl,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory(join(appDir.path, 'avatars'));
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }

    final targetPath = join(avatarsDir.path, '${userId}_profile.jpg');
    final file = File(targetPath);
    await file.writeAsBytes(bytes);

    final record = LocalAvatarRecord(
      userId: userId,
      avatarUrl: avatarUrl,
      localPath: targetPath,
      isSynced: true,
      updatedAt: DateTime.now(),
    );

    final db = await database;
    await db.insert(
      'profile_avatars',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return targetPath;
  }

  /// Updates the remote avatar URL for a given user in SQLite.
  Future<void> updateRemoteUrl({
    required String userId,
    required String avatarUrl,
  }) async {
    final db = await database;
    await db.update(
      'profile_avatars',
      {
        'avatar_url': avatarUrl,
        'is_synced': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Retrieves the cached avatar record. Returns null if not cached or if
  /// the local file was removed from the device filesystem.
  Future<LocalAvatarRecord?> getAvatar(String userId) async {
    final db = await database;
    final results = await db.query(
      'profile_avatars',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final record = LocalAvatarRecord.fromMap(results.first);
    if (record.localPath != null && record.localPath!.isNotEmpty) {
      final file = File(record.localPath!);
      if (await file.exists()) {
        return record;
      }
    }

    return record;
  }

  /// Deletes the local avatar file on disk and clears the SQLite row.
  Future<void> deleteAvatar(String userId) async {
    final db = await database;
    final results = await db.query(
      'profile_avatars',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      final path = results.first['local_path'] as String?;
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }

    await db.delete(
      'profile_avatars',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
