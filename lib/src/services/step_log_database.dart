import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/step_log_entry.dart';
import '../models/step_log_source.dart';

// Export the generated adapters for registration
export '../models/step_log_entry.dart' show StepLogEntryAdapter;
export '../models/step_log_source.dart' show StepLogSourceAdapter;

/// Local database for storing step log entries using Hive
///
/// This service provides a Health Connect-like API for querying step data
/// with support for real-time streams, aggregation, and filtering.
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
class StepLogDatabase {
  static const String _boxName = 'step_logs';

  Box<StepLogEntry>? _box;
  bool _isInitialized = false;

  /// Whether the database has been initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the Hive database
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

    await Hive.initFlutter('accurate_step_counter');

    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(StepLogEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(StepLogSourceAdapter());
    }

    _box = await Hive.openBox<StepLogEntry>(_boxName);
    _isInitialized = true;
  }

  /// Ensure database is initialized
  void _ensureInitialized() {
    if (!_isInitialized || _box == null) {
      throw StateError(
        'StepLogDatabase not initialized. Call initialize() first.',
      );
    }
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
    _ensureInitialized();
    await _box!.add(entry);
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
    StepLogSource? source,
  }) async {
    _ensureInitialized();

    var entries = _box!.values.toList();

    // Apply filters
    if (from != null) {
      entries = entries.where((e) => !e.toTime.isBefore(from)).toList();
    }
    if (to != null) {
      entries = entries.where((e) => !e.fromTime.isAfter(to)).toList();
    }
    if (source != null) {
      entries = entries.where((e) => e.source == source).toList();
    }

    // Sort by fromTime descending (newest first)
    entries.sort((a, b) => b.fromTime.compareTo(a.fromTime));

    return entries;
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
    StepLogSource? source,
  }) {
    _ensureInitialized();

    return _box!
        .watch()
        .asyncMap((_) async {
          return await getStepLogs(from: from, to: to, source: source);
        })
        .startWith(getStepLogs(from: from, to: to, source: source));
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
    _ensureInitialized();

    return _box!
        .watch()
        .asyncMap((_) async {
          return await getTotalSteps(from: from, to: to);
        })
        .startWith(getTotalSteps(from: from, to: to));
  }

  /// Get the number of log entries
  Future<int> getEntryCount() async {
    _ensureInitialized();
    return _box!.length;
  }

  /// Clear all step logs
  ///
  /// Example:
  /// ```dart
  /// await db.clearLogs();
  /// ```
  Future<void> clearLogs() async {
    _ensureInitialized();
    await _box!.clear();
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
    _ensureInitialized();

    final keysToDelete = <dynamic>[];

    for (var i = 0; i < _box!.length; i++) {
      final entry = _box!.getAt(i);
      if (entry != null && entry.toTime.isBefore(date)) {
        keysToDelete.add(_box!.keyAt(i));
      }
    }

    await _box!.deleteAll(keysToDelete);
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
        .where((e) => e.source == StepLogSource.foreground)
        .fold<int>(0, (sum, e) => sum + e.stepCount);

    final backgroundSteps = entries
        .where((e) => e.source == StepLogSource.background)
        .fold<int>(0, (sum, e) => sum + e.stepCount);

    final terminatedSteps = entries
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
    if (_box != null && _box!.isOpen) {
      await _box!.close();
    }
    _isInitialized = false;
  }
}

/// Extension to add startWith functionality to Stream
extension _StreamStartWith<T> on Stream<T> {
  Stream<T> startWith(Future<T> value) async* {
    yield await value;
    await for (final item in this) {
      yield item;
    }
  }
}
