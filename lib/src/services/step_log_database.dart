import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../database/reactive_database.dart';
import '../models/step_log_entry.dart';
import '../models/step_log_source.dart';

/// Local database for storing step log entries using SQLite
///
/// This service provides a Health Connect-like API for querying step data
/// with support for real-time streams, aggregation, and filtering.
///
/// Note: This class is deprecated in favor of StepRecordStore. It is maintained
/// for backwards compatibility and uses the separate step_logs table.
///
/// Example:
/// ```dart
/// final db = StepLogDatabase();
/// await db.initialize();
///
/// // Log steps
/// await db.logSteps(StepLogEntry(
///   stepCount: 100,
///   fromTime: startTime,
///   toTime: endTime,
///   source: StepLogSource.foreground,
/// ));
///
/// // Get total steps
/// final total = await db.getTotalSteps();
///
/// // Watch for real-time updates
/// db.watchTotalSteps().listen((total) => print('Total: $total'));
/// ```
@Deprecated('Use StepRecordStore instead')
class StepLogDatabase {
  static const String _tableName = 'step_logs';

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ReactiveDatabase _reactiveDb = ReactiveDatabase();
  bool _isInitialized = false;

  /// Whether the database has been initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the SQLite database
  ///
  /// Must be called before any other methods. Can be called multiple times
  /// safely - subsequent calls are no-ops.
  ///
  /// Example:
  /// ```dart
  /// final db = StepLogDatabase();
  /// await db.initialize();
  /// ```
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize the database (creates tables if needed)
    await _dbHelper.database;
    _isInitialized = true;
  }

  /// Ensure database is open and ready
  Future<Database> _ensureDbOpen() async {
    if (!_isInitialized) {
      await initialize();
    }
    await _dbHelper.ensureOpen();
    return _dbHelper.database;
  }

  /// Log a new step entry
  ///
  /// Example:
  /// ```dart
  /// await db.logSteps(StepLogEntry(
  ///   stepCount: 50,
  ///   fromTime: DateTime.now().subtract(Duration(minutes: 5)),
  ///   toTime: DateTime.now(),
  ///   source: StepLogSource.foreground,
  /// ));
  /// ```
  Future<void> logSteps(StepLogEntry entry) async {
    final db = await _ensureDbOpen();
    await db.insert(_tableName, entry.toMap());
    _reactiveDb.notifyLogsChanged();
  }

  /// Get all step log entries
  ///
  /// Returns entries sorted by fromTime (newest first).
  ///
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  /// [source] - Optional source filter
  ///
  /// Example:
  /// ```dart
  /// // Get all logs
  /// final allLogs = await db.getStepLogs();
  ///
  /// // Get logs from today
  /// final todayLogs = await db.getStepLogs(
  ///   from: DateTime.now().startOfDay,
  ///   to: DateTime.now(),
  /// );
  ///
  /// // Get only foreground logs
  /// final fgLogs = await db.getStepLogs(source: StepLogSource.foreground);
  /// ```
  Future<List<StepLogEntry>> getStepLogs({
    DateTime? from,
    DateTime? to,
    // ignore: deprecated_member_use_from_same_package
    StepLogSource? source,
  }) async {
    final db = await _ensureDbOpen();

    String? whereClause;
    List<dynamic>? whereArgs;

    final conditions = <String>[];
    final args = <dynamic>[];

    if (from != null) {
      conditions.add('to_time >= ?');
      args.add(from.toUtc().millisecondsSinceEpoch);
    }
    if (to != null) {
      conditions.add('from_time <= ?');
      args.add(to.toUtc().millisecondsSinceEpoch);
    }
    if (source != null) {
      conditions.add('source = ?');
      args.add(source.index);
    }

    if (conditions.isNotEmpty) {
      whereClause = conditions.join(' AND ');
      whereArgs = args;
    }

    final results = await db.query(
      _tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'from_time DESC',
    );

    return results.map((map) => StepLogEntry.fromMap(map)).toList();
  }

  /// Get total step count (aggregate)
  ///
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  ///
  /// Example:
  /// ```dart
  /// // Get all-time total
  /// final total = await db.getTotalSteps();
  ///
  /// // Get today's total
  /// final today = await db.getTotalSteps(
  ///   from: DateTime.now().startOfDay,
  ///   to: DateTime.now(),
  /// );
  /// ```
  Future<int> getTotalSteps({DateTime? from, DateTime? to}) async {
    final entries = await getStepLogs(from: from, to: to);
    return entries.fold<int>(0, (sum, entry) => sum + entry.stepCount);
  }

  /// Get step count by source
  ///
  /// [source] - The step log source to filter by
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  ///
  /// Example:
  /// ```dart
  /// final fgSteps = await db.getStepsBySource(StepLogSource.foreground);
  /// final bgSteps = await db.getStepsBySource(StepLogSource.background);
  /// final termSteps = await db.getStepsBySource(StepLogSource.terminated);
  /// ```
  Future<int> getStepsBySource(
    // ignore: deprecated_member_use_from_same_package
    StepLogSource source, {
    DateTime? from,
    DateTime? to,
  }) async {
    final entries = await getStepLogs(from: from, to: to, source: source);
    return entries.fold<int>(0, (sum, entry) => sum + entry.stepCount);
  }

  /// Watch all step logs in real-time
  ///
  /// Emits the current list of logs immediately, then emits updates
  /// whenever logs are added, modified, or deleted.
  ///
  /// Example:
  /// ```dart
  /// db.watchStepLogs().listen((logs) {
  ///   print('Total entries: ${logs.length}');
  /// });
  /// ```
  Stream<List<StepLogEntry>> watchStepLogs({
    DateTime? from,
    DateTime? to,
    // ignore: deprecated_member_use_from_same_package
    StepLogSource? source,
  }) {
    Stream<List<StepLogEntry>> watchWithRetry() async* {
      await _ensureDbOpen();

      // Emit current value immediately
      yield await getStepLogs(from: from, to: to, source: source);

      // Then watch for changes
      await for (final _ in _reactiveDb.logChanges) {
        yield await getStepLogs(from: from, to: to, source: source);
      }
    }

    return watchWithRetry();
  }

  /// Watch total step count in real-time
  ///
  /// Emits the current total immediately, then emits updates
  /// whenever the total changes.
  ///
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  ///
  /// Example:
  /// ```dart
  /// db.watchTotalSteps().listen((total) {
  ///   print('Total steps: $total');
  /// });
  ///
  /// // Watch today's steps
  /// db.watchTotalSteps(from: DateTime.now().startOfDay).listen((today) {
  ///   print('Today: $today steps');
  /// });
  /// ```
  Stream<int> watchTotalSteps({DateTime? from, DateTime? to}) {
    Stream<int> watchWithRetry() async* {
      await _ensureDbOpen();

      // Emit current value immediately
      yield await getTotalSteps(from: from, to: to);

      // Then watch for changes
      await for (final _ in _reactiveDb.logChanges) {
        yield await getTotalSteps(from: from, to: to);
      }
    }

    return watchWithRetry();
  }

  /// Get the number of log entries
  Future<int> getEntryCount() async {
    final db = await _ensureDbOpen();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all step logs
  ///
  /// Example:
  /// ```dart
  /// await db.clearLogs();
  /// ```
  Future<void> clearLogs() async {
    final db = await _ensureDbOpen();
    await db.delete(_tableName);
    _reactiveDb.notifyLogsChanged();
  }

  /// Delete logs older than a specific date
  ///
  /// [date] - Delete all logs with toTime before this date
  ///
  /// Example:
  /// ```dart
  /// // Delete logs older than 30 days
  /// await db.deleteLogsBefore(
  ///   DateTime.now().subtract(Duration(days: 30)),
  /// );
  /// ```
  Future<void> deleteLogsBefore(DateTime date) async {
    final db = await _ensureDbOpen();
    await db.delete(
      _tableName,
      where: 'to_time < ?',
      whereArgs: [date.toUtc().millisecondsSinceEpoch],
    );
    _reactiveDb.notifyLogsChanged();
  }

  /// Get step statistics for a date range
  ///
  /// Returns a map with various statistics about the step data.
  ///
  /// Example:
  /// ```dart
  /// final stats = await db.getStepStats(from: startOfWeek, to: endOfWeek);
  /// print('Total: ${stats['totalSteps']}');
  /// print('Average per day: ${stats['averagePerDay']}');
  /// ```
  Future<Map<String, dynamic>> getStepStats({
    DateTime? from,
    DateTime? to,
  }) async {
    final entries = await getStepLogs(from: from, to: to);

    if (entries.isEmpty) {
      return {
        'totalSteps': 0,
        'entryCount': 0,
        'averagePerEntry': 0.0,
        'averagePerDay': 0.0,
        'foregroundSteps': 0,
        'backgroundSteps': 0,
        'terminatedSteps': 0,
      };
    }

    final totalSteps = entries.fold<int>(0, (sum, e) => sum + e.stepCount);

    final foregroundSteps = entries
        // ignore: deprecated_member_use_from_same_package
        .where((e) => e.source == StepLogSource.foreground)
        .fold<int>(0, (sum, e) => sum + e.stepCount);

    final backgroundSteps = entries
        // ignore: deprecated_member_use_from_same_package
        .where((e) => e.source == StepLogSource.background)
        .fold<int>(0, (sum, e) => sum + e.stepCount);

    final terminatedSteps = entries
        // ignore: deprecated_member_use_from_same_package
        .where((e) => e.source == StepLogSource.terminated)
        .fold<int>(0, (sum, e) => sum + e.stepCount);

    // Calculate date range for daily average
    final earliest = entries
        .map((e) => e.fromTime)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final latest = entries
        .map((e) => e.toTime)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final days = latest.difference(earliest).inDays + 1;
    final averagePerDay = days > 0 ? totalSteps / days : 0.0;

    return {
      'totalSteps': totalSteps,
      'entryCount': entries.length,
      'averagePerEntry': totalSteps / entries.length,
      'averagePerDay': averagePerDay,
      'foregroundSteps': foregroundSteps,
      'backgroundSteps': backgroundSteps,
      'terminatedSteps': terminatedSteps,
      'earliestEntry': earliest,
      'latestEntry': latest,
    };
  }

  /// Close the database
  ///
  /// Should be called when completely done with the database.
  Future<void> close() async {
    await _dbHelper.close();
    _isInitialized = false;
  }
}
