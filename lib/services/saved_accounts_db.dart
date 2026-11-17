import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/saved_account.dart';

class SavedAccountsDatabase {
  static final SavedAccountsDatabase instance = SavedAccountsDatabase._init();
  static Database? _database;

  SavedAccountsDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('saved_accounts.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE saved_accounts (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        password TEXT,
        first_name TEXT,
        last_name TEXT,
        profile_picture_url TEXT,
        last_login_date TEXT NOT NULL
      )
    ''');

    // Create index for faster lookups
    await db.execute('''
      CREATE INDEX idx_email ON saved_accounts(email)
    ''');
  }

  /// Migrate from v1 (which stored a `role` column) to v2 (role removed),
  /// and v2 to v3 (adding password column for offline / device credential persistence).
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE saved_accounts_new (
            id TEXT PRIMARY KEY,
            email TEXT NOT NULL,
            first_name TEXT,
            last_name TEXT,
            profile_picture_url TEXT,
            last_login_date TEXT NOT NULL
          )
        ''');

        await txn.execute('''
          INSERT INTO saved_accounts_new (
            id, email, first_name, last_name, profile_picture_url, last_login_date
          )
          SELECT id, email, first_name, last_name, profile_picture_url, last_login_date
          FROM saved_accounts
        ''');

        await txn.execute('DROP INDEX IF EXISTS idx_email_role');
        await txn.execute('DROP TABLE saved_accounts');
        await txn.execute('ALTER TABLE saved_accounts_new RENAME TO saved_accounts');
        await txn.execute('CREATE INDEX idx_email ON saved_accounts(email)');
      });
    }

    if (oldVersion < 3) {
      final columns = await db.rawQuery('PRAGMA table_info(saved_accounts)');
      final hasPassword = columns.any((col) => col['name'] == 'password');
      if (!hasPassword) {
        await db.execute('ALTER TABLE saved_accounts ADD COLUMN password TEXT');
      }
    }
  }

  // Save or update an account (only accounts with passwords, i.e. email/password logins)
  Future<void> saveAccount(SavedAccount account) async {
    // Only save accounts that have a password. OAuth / Google accounts are never saved.
    if (account.password == null || account.password!.isEmpty) {
      final existing = await getAccountById(account.id);
      if (existing == null || existing.password == null || existing.password!.isEmpty) {
        return;
      }
    }

    final db = await database;

    // Update last_login_date to now
    var updatedAccount = account.copyWith(lastLoginDate: DateTime.now());

    // Preserve existing saved password if updated model has null password
    if (updatedAccount.password == null) {
      final existing = await getAccountById(account.id);
      if (existing != null && existing.password != null) {
        updatedAccount = updatedAccount.copyWith(password: existing.password);
      }
    }

    if (updatedAccount.password == null || updatedAccount.password!.isEmpty) {
      return;
    }

    await db.insert(
      'saved_accounts',
      updatedAccount.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get all saved accounts, ordered by most recent login (only email/password accounts)
  Future<List<SavedAccount>> getAllAccounts() async {
    final db = await database;

    // Clean up any legacy saved accounts that do not have a password (e.g. Google sign-ins)
    await db.delete(
      'saved_accounts',
      where: 'password IS NULL OR password = ?',
      whereArgs: [''],
    );

    final result = await db.query(
      'saved_accounts',
      where: 'password IS NOT NULL AND password != ?',
      whereArgs: [''],
      orderBy: 'last_login_date DESC',
    );

    return result.map((map) => SavedAccount.fromMap(map)).toList();
  }

  // Get the most recently used account
  Future<SavedAccount?> getMostRecentAccount() async {
    final db = await database;
    final result = await db.query(
      'saved_accounts',
      orderBy: 'last_login_date DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return SavedAccount.fromMap(result.first);
  }

  // Get account by ID
  Future<SavedAccount?> getAccountById(String id) async {
    final db = await database;
    final result = await db.query(
      'saved_accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return SavedAccount.fromMap(result.first);
  }

  // Update last login date
  Future<void> updateLastLogin(String id) async {
    final db = await database;
    await db.update(
      'saved_accounts',
      {'last_login_date': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Update profile picture url
  Future<void> updateProfilePicture(String id, String? profilePictureUrl) async {
    final db = await database;
    await db.update(
      'saved_accounts',
      {'profile_picture_url': profilePictureUrl},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Update account first and last name
  Future<void> updateAccountName(String id, String? firstName, String? lastName) async {
    final db = await database;
    await db.update(
      'saved_accounts',
      {
        'first_name': firstName,
        'last_name': lastName,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete an account
  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete(
      'saved_accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Clear all saved accounts
  Future<void> clearAllAccounts() async {
    final db = await database;
    await db.delete('saved_accounts');
  }

  // Close the database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
