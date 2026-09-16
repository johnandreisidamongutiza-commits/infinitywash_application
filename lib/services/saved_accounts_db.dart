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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE saved_accounts (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        role TEXT NOT NULL,
        first_name TEXT,
        last_name TEXT,
        profile_picture_url TEXT,
        last_login_date TEXT NOT NULL
      )
    ''');

    // Create index for faster lookups
    await db.execute('''
      CREATE INDEX idx_email_role ON saved_accounts(email, role)
    ''');
  }

  // Save or update an account
  Future<void> saveAccount(SavedAccount account) async {
    final db = await database;
    
    // Update last_login_date to now
    final updatedAccount = account.copyWith(lastLoginDate: DateTime.now());
    
    await db.insert(
      'saved_accounts',
      updatedAccount.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get all saved accounts, ordered by most recent login
  Future<List<SavedAccount>> getAllAccounts() async {
    final db = await database;
    final result = await db.query(
      'saved_accounts',
      orderBy: 'last_login_date DESC',
    );

    return result.map((map) => SavedAccount.fromMap(map)).toList();
  }

  // Get accounts by role
  Future<List<SavedAccount>> getAccountsByRole(String role) async {
    final db = await database;
    final result = await db.query(
      'saved_accounts',
      where: 'role = ?',
      whereArgs: [role],
      orderBy: 'last_login_date DESC',
    );

    return result.map((map) => SavedAccount.fromMap(map)).toList();
  }

  // Get a specific account by email and role
  Future<SavedAccount?> getAccount(String email, String role) async {
    final db = await database;
    final result = await db.query(
      'saved_accounts',
      where: 'email = ? AND role = ?',
      whereArgs: [email, role],
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

  // Delete an account
  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete(
      'saved_accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete account by email and role
  Future<void> deleteAccountByEmailAndRole(String email, String role) async {
    final db = await database;
    await db.delete(
      'saved_accounts',
      where: 'email = ? AND role = ?',
      whereArgs: [email, role],
    );
  }

  // Clear all saved accounts
  Future<void> clearAllAccounts() async {
    final db = await database;
    await db.delete('saved_accounts');
  }

  // Check if an account exists
  Future<bool> accountExists(String email, String role) async {
    final db = await database;
    final result = await db.query(
      'saved_accounts',
      where: 'email = ? AND role = ?',
      whereArgs: [email, role],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // Get the most recently used account for a role
  Future<SavedAccount?> getMostRecentAccountForRole(String role) async {
    final db = await database;
    final result = await db.query(
      'saved_accounts',
      where: 'role = ?',
      whereArgs: [role],
      orderBy: 'last_login_date DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return SavedAccount.fromMap(result.first);
  }

  // Close the database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
