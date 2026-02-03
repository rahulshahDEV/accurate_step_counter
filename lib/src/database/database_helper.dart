import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Helper class for managing the SQLite database
///
/// Provides singleton access to the database with lazy initialization,
/// schema creation, and connection management for Android cold starts.
class DatabaseHelper {
  static const String _databaseName = 'accurate_step_counter.db';
  static const int _databaseVersion = 1;

  // Singleton instance
  static DatabaseHelper? _instance;
  static Database? _database;

  // Test mode configuration
  static bool _isTestMode = false;

  // Private constructor
  DatabaseHelper._internal();

  /// Get the singleton instance
  factory DatabaseHelper() {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  /// Enable test mode for in-memory database
  ///
  /// This uses in-memory database for testing to avoid file conflicts
  /// when running tests in parallel.
  static void setTestMode() {
    _isTestMode = true;
  }

  /// Disable test mode
  static void clearTestMode() {
    _isTestMode = false;
  }

  /// Reset the singleton instance (for testing)
  static Future<void> resetInstance() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }
    _database = null;
    _instance = null;
  }

  // Initialization lock
  static Completer<Database>? _initCompleter;

  /// Get the database instance, initializing if needed
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database);
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null; // Allow retry on failure
      rethrow;
    } finally {
      _initCompleter = null;
    }

    return _database!;
  }

  /// Check if database is initialized and open
  bool get isOpen => _database != null && _database!.isOpen;

  /// Initialize the database
  Future<Database> _initDatabase() async {
    String path;

    if (_isTestMode) {
      // Use in-memory database for tests
      path = inMemoryDatabasePath;
    } else {
      final databasesPath = await getDatabasesPath();
      path = join(databasesPath, _databaseName);
    }

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: !_isTestMode, // Allow multiple instances in test mode
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // Step records table (primary)
    await db.execute('''
      CREATE TABLE step_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        step_count INTEGER NOT NULL,
        from_time INTEGER NOT NULL,
        to_time INTEGER NOT NULL,
        source INTEGER NOT NULL,
        confidence REAL
      )
    ''');

    // Indexes for efficient querying
    await db.execute('''
      CREATE INDEX idx_step_records_time ON step_records(from_time, to_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_step_records_source ON step_records(source)
    ''');

    // Step logs table (deprecated, for backwards compatibility)
    await db.execute('''
      CREATE TABLE step_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        step_count INTEGER NOT NULL,
        from_time INTEGER NOT NULL,
        to_time INTEGER NOT NULL,
        source INTEGER NOT NULL,
        source_name TEXT NOT NULL DEFAULT 'accurate_step_counter',
        confidence REAL NOT NULL DEFAULT 1.0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_step_logs_time ON step_logs(from_time, to_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_step_logs_source ON step_logs(source)
    ''');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
    // Example:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE step_records ADD COLUMN new_field TEXT');
    // }
  }

  /// Ensure the database is open
  ///
  /// This is critical for handling Android cold starts where the database
  /// connection may have been closed by the system.
  Future<void> ensureOpen() async {
    // Accessing the getter triggers safe initialization if needed
    await database;
  }

  /// Close the database connection
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// Reset the database (for testing purposes)
  ///
  /// Closes and deletes the database file, then reinitializes.
  Future<void> reset() async {
    await close();
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);
    await deleteDatabase(path);
    // Force re-init safely
    await database;
  }
}
