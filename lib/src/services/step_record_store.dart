import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../database/reactive_database.dart';
import '../models/step_record.dart';
import '../models/step_record_source.dart';

/// Local store for step records using SQLite
///
/// This service provides a Health Connect-like API for storing and querying
/// step data with support for real-time streams, aggregation, and filtering.
///
/// Example:
/// ```dart
/// final store = StepRecordStore();
/// await store.initialize();
///
/// // Write a record
/// await store.insertRecord(StepRecord(
///   stepCount: 100,
///   fromTime: startTime,
///   toTime: endTime,
///   source: StepRecordSource.foreground,
/// ));
///
/// // Read total steps
/// final total = await store.readTotalSteps();
///
/// // Watch for real-time updates
/// store.watchTotalSteps().listen((total) => print('Total: $total'));
/// ```
class StepRecordStore {
  static const String _tableName = 'step_records';

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ReactiveDatabase _reactiveDb = ReactiveDatabase();
  bool _isInitialized = false;

  /// Whether the store has been initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the SQLite store
  ///
  /// Must be called before any other methods. Can be called multiple times
  /// safely - subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize the database (creates tables if needed)
    await _dbHelper.database;
    _isInitialized = true;
  }

  /// Ensure store is initialized and database is open
  ///
  /// This method checks both initialization state AND whether the database
  /// is actually open. This is critical for handling cold starts where
  /// Android may have killed the app and closed the database.
  Future<Database> _ensureDbOpen() async {
    if (!_isInitialized) {
      await initialize();
    }
    await _dbHelper.ensureOpen();
    return _dbHelper.database;
  }

  /// Insert a new step record
  ///
  /// This method safely ensures the database is open before writing.
  /// Handles cold start scenarios where Android may have closed the database.
  ///
  /// Example:
  /// ```dart
  /// await store.insertRecord(StepRecord(
  ///   stepCount: 50,
  ///   fromTime: DateTime.now().subtract(Duration(minutes: 5)),
  ///   toTime: DateTime.now(),
  ///   source: StepRecordSource.foreground,
  /// ));
  /// ```
  Future<void> insertRecord(StepRecord record) async {
    try {
      final db = await _ensureDbOpen();
      await db.insert(_tableName, record.toMap());
      _reactiveDb.notifyRecordsChanged();
    } catch (e) {
      // If database operations fail, try one more time with fresh initialization
      if (e.toString().contains('database') ||
          e.toString().contains('DatabaseException')) {
        _isInitialized = false;
        await initialize();
        final db = await _dbHelper.database;
        await db.insert(_tableName, record.toMap());
        _reactiveDb.notifyRecordsChanged();
      } else {
        rethrow;
      }
    }
  }

  /// Check for duplicate or overlapping records
  ///
  /// Returns true if a record with the same or overlapping time range already exists.
  /// Uses a tolerance window to detect "fuzzy" duplicates (within 60 seconds).
  ///
  /// [fromTime] - Start time of the record to check
  /// [toTime] - End time of the record to check
  /// [stepCount] - Optional step count to also match (for exact duplicate detection)
  /// [source] - Optional source to also match
  ///
  /// Example:
  /// ```dart
  /// final isDuplicate = await store.hasDuplicateRecord(
  ///   fromTime: startTime,
  ///   toTime: endTime,
  ///   stepCount: 100,
  /// );
  /// if (!isDuplicate) {
  ///   await store.insertRecord(record);
  /// }
  /// ```
  Future<bool> hasDuplicateRecord({
    required DateTime fromTime,
    required DateTime toTime,
    int? stepCount,
    StepRecordSource? source,
  }) async {
    final db = await _ensureDbOpen();

    // Tolerance window for fuzzy matching (60 seconds)
    const toleranceMs = 60000;
    final fromStart = fromTime.toUtc().millisecondsSinceEpoch - toleranceMs;
    final fromEnd = fromTime.toUtc().millisecondsSinceEpoch + toleranceMs;
    final toStart = toTime.toUtc().millisecondsSinceEpoch - toleranceMs;
    final toEnd = toTime.toUtc().millisecondsSinceEpoch + toleranceMs;

    String whereClause =
        'from_time > ? AND from_time < ? AND to_time > ? AND to_time < ?';
    List<dynamic> whereArgs = [fromStart, fromEnd, toStart, toEnd];

    if (stepCount != null) {
      whereClause += ' AND step_count = ?';
      whereArgs.add(stepCount);
    }

    if (source != null) {
      whereClause += ' AND source = ?';
      whereArgs.add(source.index);
    }

    final results = await db.query(
      _tableName,
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );

    return results.isNotEmpty;
  }

  /// Check for any overlapping records in a time range
  ///
  /// Returns true if any existing record overlaps with the given time range.
  /// Useful for preventing duplicate imports from external sources.
  ///
  /// [fromTime] - Start time of the range to check
  /// [toTime] - End time of the range to check
  Future<bool> hasOverlappingRecord({
    required DateTime fromTime,
    required DateTime toTime,
  }) async {
    final db = await _ensureDbOpen();

    final fromMs = fromTime.toUtc().millisecondsSinceEpoch;
    final toMs = toTime.toUtc().millisecondsSinceEpoch;

    // Check for overlap: record.fromTime < toTime AND record.toTime > fromTime
    final results = await db.query(
      _tableName,
      where: 'from_time < ? AND to_time > ?',
      whereArgs: [toMs, fromMs],
      limit: 1,
    );

    return results.isNotEmpty;
  }

  /// Read all step records
  ///
  /// Returns records sorted by fromTime (newest first).
  ///
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  /// [source] - Optional source filter
  Future<List<StepRecord>> readRecords({
    DateTime? from,
    DateTime? to,
    StepRecordSource? source,
  }) async {
    final db = await _ensureDbOpen();

    String? whereClause;
    List<dynamic>? whereArgs;

    final conditions = <String>[];
    final args = <dynamic>[];

    if (from != null) {
      conditions.add('to_time > ?');
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

    return results.map((map) => StepRecord.fromMap(map)).toList();
  }

  /// Read total step count (aggregate)
  ///
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  Future<int> readTotalSteps({DateTime? from, DateTime? to}) async {
    final entries = await readRecords(from: from, to: to);
    return entries.fold<int>(0, (sum, entry) => sum + entry.stepCount);
  }

  /// Read step count by source
  ///
  /// [source] - The step record source to filter by
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  Future<int> readStepsBySource(
    StepRecordSource source, {
    DateTime? from,
    DateTime? to,
  }) async {
    final entries = await readRecords(from: from, to: to, source: source);
    return entries.fold<int>(0, (sum, entry) => sum + entry.stepCount);
  }

  /// Watch all step records in real-time
  ///
  /// Emits the current list immediately, then emits updates
  /// whenever records are added, modified, or deleted.
  ///
  /// Handles closed database scenarios by ensuring database is open before watching.
  Stream<List<StepRecord>> watchRecords({
    DateTime? from,
    DateTime? to,
    StepRecordSource? source,
  }) {
    // Use async* generator to ensure database is open before watching
    Stream<List<StepRecord>> watchWithRetry() async* {
      await _ensureDbOpen();

      // Emit current value immediately
      yield await readRecords(from: from, to: to, source: source);

      // Then watch for changes
      await for (final _ in _reactiveDb.recordChanges) {
        yield await readRecords(from: from, to: to, source: source);
      }
    }

    return watchWithRetry();
  }

  /// Watch total step count in real-time
  ///
  /// Emits the current total immediately, then emits updates
  /// whenever the total changes.
  ///
  /// Handles closed database scenarios by ensuring database is open before watching.
  Stream<int> watchTotalSteps({DateTime? from, DateTime? to}) {
    // Use async* generator to ensure database is open before watching
    Stream<int> watchWithRetry() async* {
      await _ensureDbOpen();

      // Emit current value immediately
      yield await readTotalSteps(from: from, to: to);

      // Then watch for changes
      await for (final _ in _reactiveDb.recordChanges) {
        yield await readTotalSteps(from: from, to: to);
      }
    }

    return watchWithRetry();
  }

  /// Get the number of records
  Future<int> getRecordCount() async {
    final db = await _ensureDbOpen();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete all step records
  Future<void> deleteAllRecords() async {
    try {
      final db = await _ensureDbOpen();
      await db.delete(_tableName);
      _reactiveDb.notifyRecordsChanged();
    } catch (e) {
      if (e.toString().contains('database') ||
          e.toString().contains('DatabaseException')) {
        _isInitialized = false;
        await initialize();
        final db = await _dbHelper.database;
        await db.delete(_tableName);
        _reactiveDb.notifyRecordsChanged();
      } else {
        rethrow;
      }
    }
  }

  /// Delete records older than a specific date
  ///
  /// [date] - Delete all records with toTime before this date
  ///
  /// This method is safe to call even if no records exist or the database
  /// was closed by Android. It will silently succeed if there's nothing
  /// to delete or if re-initialization fails.
  Future<void> deleteRecordsBefore(DateTime date) async {
    try {
      final db = await _ensureDbOpen();

      await db.delete(
        _tableName,
        where: 'to_time < ?',
        whereArgs: [date.toUtc().millisecondsSinceEpoch],
      );
      _reactiveDb.notifyRecordsChanged();
    } catch (e) {
      if (e.toString().contains('database') ||
          e.toString().contains('DatabaseException')) {
        _isInitialized = false;
        try {
          await initialize();
          final db = await _dbHelper.database;
          await db.delete(
            _tableName,
            where: 'to_time < ?',
            whereArgs: [date.toUtc().millisecondsSinceEpoch],
          );
          _reactiveDb.notifyRecordsChanged();
        } catch (_) {
          // Silently fail - data retention is not critical enough to crash the app
          return;
        }
      } else {
        // For non-database errors, log but don't crash
        // Data retention failure should not prevent app from working
        return;
      }
    }
  }

  /// Get step statistics for a date range
  ///
  /// Returns a map with various statistics about the step data.
  Future<Map<String, dynamic>> getStats({DateTime? from, DateTime? to}) async {
    final entries = await readRecords(from: from, to: to);

    if (entries.isEmpty) {
      return {
        'totalSteps': 0,
        'recordCount': 0,
        'averagePerRecord': 0.0,
        'averagePerDay': 0.0,
        'foregroundSteps': 0,
        'backgroundSteps': 0,
        'terminatedSteps': 0,
      };
    }

    final totalSteps = entries.fold<int>(0, (sum, e) => sum + e.stepCount);

    final foregroundSteps = entries
        .where((e) => e.source == StepRecordSource.foreground)
        .fold<int>(0, (sum, e) => sum + e.stepCount);

    final backgroundSteps = entries
        .where((e) => e.source == StepRecordSource.background)
        .fold<int>(0, (sum, e) => sum + e.stepCount);

    final terminatedSteps = entries
        .where((e) => e.source == StepRecordSource.terminated)
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
      'recordCount': entries.length,
      'averagePerRecord': totalSteps / entries.length,
      'averagePerDay': averagePerDay,
      'foregroundSteps': foregroundSteps,
      'backgroundSteps': backgroundSteps,
      'terminatedSteps': terminatedSteps,
      'earliestRecord': earliest,
      'latestRecord': latest,
    };
  }

  /// Close the store
  ///
  /// Should be called when completely done with the store.
  Future<void> close() async {
    await _dbHelper.close();
    _isInitialized = false;
  }
}

// Backwards compatibility
@Deprecated('Use StepRecordStore instead')
typedef StepLogDatabase = StepRecordStore;
