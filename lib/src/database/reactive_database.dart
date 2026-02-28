import 'dart:async';

/// Reactive wrapper for SQLite database change notifications.
///
/// Since sqflite doesn't have built-in watch functionality like Hive,
/// this class provides StreamController-based reactivity for step_records changes.
class ReactiveDatabase {
  // Singleton instance
  static ReactiveDatabase? _instance;

  // Broadcast controller for step_records table
  final _recordsController = StreamController<void>.broadcast();

  // Private constructor
  ReactiveDatabase._internal();

  /// Get the singleton instance
  factory ReactiveDatabase() {
    _instance ??= ReactiveDatabase._internal();
    return _instance!;
  }

  /// Stream that emits whenever step_records table changes
  Stream<void> get recordChanges => _recordsController.stream;

  /// Notify listeners that step_records table has changed
  ///
  /// Call this after any insert, update, or delete operation on step_records.
  void notifyRecordsChanged() {
    if (!_recordsController.isClosed) {
      _recordsController.add(null);
    }
  }

  /// Check if controller is still active
  bool get isActive => !_recordsController.isClosed;

  /// Close stream controller
  ///
  /// Should be called when completely done with the reactive database.
  Future<void> close() async {
    if (!_recordsController.isClosed) {
      await _recordsController.close();
    }
    _instance = null;
  }

  /// Reset the reactive database (for testing)
  ///
  /// Closes existing controller and creates a new one.
  static void reset() {
    _instance?.close();
    _instance = null;
  }
}
