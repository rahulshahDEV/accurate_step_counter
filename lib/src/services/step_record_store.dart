import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/step_record.dart';
import '../models/step_record_source.dart';

// Export the generated adapters for registration
export '../models/step_record.dart' show StepRecordAdapter;
export '../models/step_record_source.dart' show StepRecordSourceAdapter;

/// Local store for step records using Hive
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
  static const String _boxName = 'step_records';

  Box<StepRecord>? _box;
  bool _isInitialized = false;

  /// Whether the store has been initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the Hive store
  ///
  /// Must be called before any other methods. Can be called multiple times
  /// safely - subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter('accurate_step_counter');

    // Register adapters
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(StepRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(StepRecordSourceAdapter());
    }

    _box = await Hive.openBox<StepRecord>(_boxName);
    _isInitialized = true;
  }

  /// Ensure store is initialized
  void _ensureInitialized() {
    if (!_isInitialized || _box == null) {
      throw StateError(
        'StepRecordStore not initialized. Call initialize() first.',
      );
    }
  }

  /// Insert a new step record
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
    _ensureInitialized();
    await _box!.add(record);
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
  Stream<List<StepRecord>> watchRecords({
    DateTime? from,
    DateTime? to,
    StepRecordSource? source,
  }) {
    _ensureInitialized();

    return _box!
        .watch()
        .asyncMap((_) async {
          return await readRecords(from: from, to: to, source: source);
        })
        .startWith(readRecords(from: from, to: to, source: source));
  }

  /// Watch total step count in real-time
  ///
  /// Emits the current total immediately, then emits updates
  /// whenever the total changes.
  Stream<int> watchTotalSteps({DateTime? from, DateTime? to}) {
    _ensureInitialized();

    return _box!
        .watch()
        .asyncMap((_) async {
          return await readTotalSteps(from: from, to: to);
        })
        .startWith(readTotalSteps(from: from, to: to));
  }

  /// Get the number of records
  Future<int> getRecordCount() async {
    _ensureInitialized();
    return _box!.length;
  }

  /// Delete all step records
  Future<void> deleteAllRecords() async {
    _ensureInitialized();
    await _box!.clear();
  }

  /// Delete records older than a specific date
  ///
  /// [date] - Delete all records with toTime before this date
  Future<void> deleteRecordsBefore(DateTime date) async {
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
    if (_box != null && _box!.isOpen) {
      await _box!.close();
    }
    _isInitialized = false;
  }
}

// Backwards compatibility
@Deprecated('Use StepRecordStore instead')
typedef StepLogDatabase = StepRecordStore;

/// Extension to add startWith functionality to Stream
extension _StreamStartWith<T> on Stream<T> {
  Stream<T> startWith(Future<T> value) async* {
    yield await value;
    await for (final item in this) {
      yield item;
    }
  }
}
