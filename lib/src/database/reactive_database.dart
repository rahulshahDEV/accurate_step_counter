import 'dart:async';

/// Reactive wrapper for SQLite database change notifications
///
/// Since sqflite doesn't have built-in watch functionality like Hive,
/// this class provides StreamController-based reactivity for database changes.
///
/// Example:
/// ```dart
/// final reactiveDb = ReactiveDatabase();
///
/// // Listen for changes
/// reactiveDb.recordChanges.listen((_) {
///   print('Records changed!');
/// });
///
/// // Notify after write operations
/// await db.insert('step_records', record.toMap());
/// reactiveDb.notifyRecordsChanged();
/// ```
class ReactiveDatabase {
  // Singleton instance
  static ReactiveDatabase? _instance;

  // Broadcast controllers for different tables
  final _recordsController = StreamController<void>.broadcast();
  final _logsController = StreamController<void>.broadcast();

  // Private constructor
  ReactiveDatabase._internal();

  /// Get the singleton instance
  factory ReactiveDatabase() {
    _instance ??= ReactiveDatabase._internal();
    return _instance!;
  }

  /// Stream that emits whenever step_records table changes
  Stream<void> get recordChanges => _recordsController.stream;

  /// Stream that emits whenever step_logs table changes
  Stream<void> get logChanges => _logsController.stream;

  /// Notify listeners that step_records table has changed
  ///
  /// Call this after any insert, update, or delete operation on step_records.
  void notifyRecordsChanged() {
    if (!_recordsController.isClosed) {
      _recordsController.add(null);
    }
  }

  /// Notify listeners that step_logs table has changed
  ///
  /// Call this after any insert, update, or delete operation on step_logs.
  void notifyLogsChanged() {
    if (!_logsController.isClosed) {
      _logsController.add(null);
    }
  }

  /// Check if controllers are still active
  bool get isActive =>
      !_recordsController.isClosed && !_logsController.isClosed;

  /// Close all stream controllers
  ///
  /// Should be called when completely done with the reactive database.
  Future<void> close() async {
    if (!_recordsController.isClosed) {
      await _recordsController.close();
    }
    if (!_logsController.isClosed) {
      await _logsController.close();
    }
    _instance = null;
  }

  /// Reset the reactive database (for testing)
  ///
  /// Closes existing controllers and creates new ones.
  static void reset() {
    _instance?.close();
    _instance = null;
  }
}
