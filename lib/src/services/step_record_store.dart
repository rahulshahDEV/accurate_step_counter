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

  /// Ensure store is initialized and box is open
  ///
  /// This method checks both initialization state AND whether the Hive box
  /// is actually open. This is critical for handling cold starts where
  /// Android may have killed the app and closed the boxes.
  Future<void> _ensureBoxOpen() async {
    if (!_isInitialized || _box == null) {
      // Not initialized at all - initialize from scratch
      await initialize();
      return;
    }

    // Check if box is still open (Android may have closed it)
    if (!_box!.isOpen) {
      // Box was closed (app was killed by Android) - reopen it
      _box = await Hive.openBox<StepRecord>(_boxName);
    }
  }

  /// Synchronous check for initialization - throws if not ready
  /// Use _ensureBoxOpen() for operations that can wait for reopening
  void _ensureInitialized() {
    if (!_isInitialized || _box == null) {
      throw StateError(
        'StepRecordStore not initialized. Call initialize() first.',
      );
    }
  }

  /// Insert a new step record
  ///
  /// This method safely ensures the Hive box is open before writing.
  /// Handles cold start scenarios where Android may have closed the box.
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
      await _ensureBoxOpen();
      await _box!.add(record);
    } catch (e) {
      // If box operations fail, try one more time with fresh initialization
      if (e.toString().contains('Box has already been closed') ||
          e.toString().contains('HiveError')) {
        _isInitialized = false;
        _box = null;
        await initialize();
        await _box!.add(record);
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
    await _ensureBoxOpen();

    // Tolerance window for fuzzy matching (60 seconds)
    const toleranceMs = 60000;
    final fromStart = fromTime.subtract(
      const Duration(milliseconds: toleranceMs),
    );
    final fromEnd = fromTime.add(const Duration(milliseconds: toleranceMs));
    final toStart = toTime.subtract(const Duration(milliseconds: toleranceMs));
    final toEnd = toTime.add(const Duration(milliseconds: toleranceMs));

    for (final record in _box!.values) {
      // Check if fromTime is within tolerance
      final fromMatches =
          record.fromTime.isAfter(fromStart) &&
          record.fromTime.isBefore(fromEnd);

      // Check if toTime is within tolerance
      final toMatches =
          record.toTime.isAfter(toStart) && record.toTime.isBefore(toEnd);

      if (fromMatches && toMatches) {
        // Time range matches - check optional step count
        if (stepCount != null && record.stepCount != stepCount) {
          continue; // Step count doesn't match
        }

        // Check optional source
        if (source != null && record.source != source) {
          continue; // Source doesn't match
        }

        // Found a duplicate
        return true;
      }
    }

    return false;
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
    await _ensureBoxOpen();

    for (final record in _box!.values) {
      // Check for overlap: record.fromTime < toTime AND record.toTime > fromTime
      if (record.fromTime.isBefore(toTime) && record.toTime.isAfter(fromTime)) {
        return true;
      }
    }

    return false;
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
    await _ensureBoxOpen();

    var entries = _box!.values.toList();

    // Apply filters
    if (from != null) {
      entries = entries.where((e) => e.toTime.isAfter(from)).toList();
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
  ///
  /// Handles closed box scenarios by ensuring box is open before watching.
  Stream<List<StepRecord>> watchRecords({
    DateTime? from,
    DateTime? to,
    StepRecordSource? source,
  }) {
    // Use async* generator to ensure box is open before watching
    Stream<List<StepRecord>> watchWithRetry() async* {
      await _ensureBoxOpen();

      // Emit current value immediately
      yield await readRecords(from: from, to: to, source: source);

      // Then watch for changes
      await for (final _ in _box!.watch()) {
        // Re-check box is open on each event (defensive)
        if (_box == null || !_box!.isOpen) {
          await _ensureBoxOpen();
        }
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
  /// Handles closed box scenarios by ensuring box is open before watching.
  Stream<int> watchTotalSteps({DateTime? from, DateTime? to}) {
    // Use async* generator to ensure box is open before watching
    Stream<int> watchWithRetry() async* {
      await _ensureBoxOpen();

      // Emit current value immediately
      yield await readTotalSteps(from: from, to: to);

      // Then watch for changes
      await for (final _ in _box!.watch()) {
        // Re-check box is open on each event (defensive)
        if (_box == null || !_box!.isOpen) {
          await _ensureBoxOpen();
        }
        yield await readTotalSteps(from: from, to: to);
      }
    }

    return watchWithRetry();
  }

  /// Get the number of records
  Future<int> getRecordCount() async {
    await _ensureBoxOpen();
    return _box!.length;
  }

  /// Delete all step records
  Future<void> deleteAllRecords() async {
    try {
      await _ensureBoxOpen();
      await _box!.clear();
    } catch (e) {
      if (e.toString().contains('Box has already been closed') ||
          e.toString().contains('HiveError')) {
        _isInitialized = false;
        _box = null;
        await initialize();
        await _box!.clear();
      } else {
        rethrow;
      }
    }
  }

  /// Delete records older than a specific date
  ///
  /// [date] - Delete all records with toTime before this date
  Future<void> deleteRecordsBefore(DateTime date) async {
    try {
      await _ensureBoxOpen();

      final keysToDelete = <dynamic>[];

      for (var i = 0; i < _box!.length; i++) {
        final entry = _box!.getAt(i);
        if (entry != null && entry.toTime.isBefore(date)) {
          keysToDelete.add(_box!.keyAt(i));
        }
      }

      await _box!.deleteAll(keysToDelete);
    } catch (e) {
      if (e.toString().contains('Box has already been closed') ||
          e.toString().contains('HiveError')) {
        _isInitialized = false;
        _box = null;
        await initialize();
        // Retry the operation
        final keysToDelete = <dynamic>[];
        for (var i = 0; i < _box!.length; i++) {
          final entry = _box!.getAt(i);
          if (entry != null && entry.toTime.isBefore(date)) {
            keysToDelete.add(_box!.keyAt(i));
          }
        }
        await _box!.deleteAll(keysToDelete);
      } else {
        rethrow;
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
    if (_box != null && _box!.isOpen) {
      await _box!.close();
    }
    _isInitialized = false;
  }
}

// Backwards compatibility
@Deprecated('Use StepRecordStore instead')
typedef StepLogDatabase = StepRecordStore;
