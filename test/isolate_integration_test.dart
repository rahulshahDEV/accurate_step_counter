import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/services/step_record_store.dart';
import 'package:accurate_step_counter/src/database/database_helper.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integration tests for background isolate mode
///
/// Note: Tests that actually use isolate mode are skipped in unit tests
/// because isolates cannot share the FFI database factory configured
/// in the main isolate. The isolate will work correctly on real devices
/// where sqflite uses the native SQLite implementation.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.setTestMode();
  });

  group('StepRecordStore isolate flag', () {
    test('isUsingIsolate returns true when created with isolate flag', () {
      final store = StepRecordStore(useIsolate: true);
      expect(store.isUsingIsolate, isTrue);
    });

    test('isUsingIsolate returns false when created without isolate flag', () {
      final store = StepRecordStore(useIsolate: false);
      expect(store.isUsingIsolate, isFalse);
    });

    test('default constructor does not use isolate', () {
      final store = StepRecordStore();
      expect(store.isUsingIsolate, isFalse);
    });
  });

  group('StepRecordStore without isolate mode', () {
    late StepRecordStore store;

    setUp(() async {
      store = StepRecordStore(useIsolate: false);
      await store.initialize();
    });

    tearDown(() async {
      await store.deleteAllRecords();
      await store.close();
      await DatabaseHelper.resetInstance();
    });

    test('insert and read records works without isolate', () async {
      final now = DateTime.now().toUtc();

      await store.insertRecord(StepRecord(
        stepCount: 100,
        fromTime: now.subtract(const Duration(hours: 1)),
        toTime: now,
        source: StepRecordSource.foreground,
      ));

      final records = await store.readRecords();
      expect(records.length, 1);
      expect(records.first.stepCount, 100);
    });

    test('readTotalSteps works without isolate', () async {
      final now = DateTime.now().toUtc();

      await store.insertRecord(StepRecord(
        stepCount: 100,
        fromTime: now.subtract(const Duration(hours: 2)),
        toTime: now.subtract(const Duration(hours: 1)),
        source: StepRecordSource.foreground,
      ));

      await store.insertRecord(StepRecord(
        stepCount: 200,
        fromTime: now.subtract(const Duration(hours: 1)),
        toTime: now,
        source: StepRecordSource.foreground,
      ));

      final total = await store.readTotalSteps();
      expect(total, 300);
    });
  });

  group('StepRecordConfig with isolate', () {
    test('lowEndDevice preset enables isolate', () {
      final config = StepRecordConfig.lowEndDevice();
      expect(config.useBackgroundIsolate, isTrue);
    });

    test('default presets do not enable isolate by default', () {
      expect(StepRecordConfig.walking().useBackgroundIsolate, isFalse);
      expect(StepRecordConfig.running().useBackgroundIsolate, isFalse);
      expect(StepRecordConfig.sensitive().useBackgroundIsolate, isFalse);
      expect(StepRecordConfig.conservative().useBackgroundIsolate, isFalse);
      expect(StepRecordConfig.aggregated().useBackgroundIsolate, isFalse);
      expect(StepRecordConfig.noValidation().useBackgroundIsolate, isFalse);
    });

    test('presets can enable isolate via parameter', () {
      expect(
        StepRecordConfig.walking(useBackgroundIsolate: true).useBackgroundIsolate,
        isTrue,
      );
      expect(
        StepRecordConfig.running(useBackgroundIsolate: true).useBackgroundIsolate,
        isTrue,
      );
      expect(
        StepRecordConfig.aggregated(useBackgroundIsolate: true).useBackgroundIsolate,
        isTrue,
      );
    });

    test('copyWith can toggle isolate mode', () {
      final config = StepRecordConfig.aggregated();
      expect(config.useBackgroundIsolate, isFalse);

      final withIsolate = config.copyWith(useBackgroundIsolate: true);
      expect(withIsolate.useBackgroundIsolate, isTrue);

      // Other values should be preserved
      expect(withIsolate.enableAggregatedMode, config.enableAggregatedMode);
      expect(withIsolate.maxStepsPerSecond, config.maxStepsPerSecond);
      expect(withIsolate.retentionPeriod, config.retentionPeriod);
    });

    test('toString includes isolate flag', () {
      final configWithIsolate = StepRecordConfig.lowEndDevice();
      expect(configWithIsolate.toString(), contains('isolate: true'));

      final configWithoutIsolate = StepRecordConfig.aggregated();
      expect(configWithoutIsolate.toString(), contains('isolate: false'));
    });

    test('default StepRecordConfig has isolate disabled', () {
      const config = StepRecordConfig();
      expect(config.useBackgroundIsolate, isFalse);
    });
  });

  group('AccurateStepCounter initialization with isolate parameter', () {
    late AccurateStepCounter stepCounter;

    setUp(() async {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
      await DatabaseHelper.resetInstance();
    });

    test('initializeLogging accepts useBackgroundIsolate parameter', () async {
      // Should not throw when called with parameter
      await stepCounter.initializeLogging(useBackgroundIsolate: false);
      expect(stepCounter.isLoggingInitialized, isTrue);
    });

    test('initializeLogging without parameters uses default (no isolate)', () async {
      await stepCounter.initializeLogging();
      expect(stepCounter.isLoggingInitialized, isTrue);
    });
  });

  group('AccurateStepCounter without isolate mode', () {
    late AccurateStepCounter stepCounter;

    setUp(() async {
      stepCounter = AccurateStepCounter();
      await stepCounter.initializeLogging(useBackgroundIsolate: false);
    });

    tearDown(() async {
      await stepCounter.dispose();
      await DatabaseHelper.resetInstance();
    });

    test('startLogging with aggregated config works', () async {
      await stepCounter.startLogging(config: StepRecordConfig.aggregated());
      expect(stepCounter.isLoggingEnabled, isTrue);
    });

    test('writeStepsToAggregated works without isolate', () async {
      await stepCounter.startLogging(config: StepRecordConfig.aggregated());

      final now = DateTime.now();

      await stepCounter.writeStepsToAggregated(
        stepCount: 500,
        fromTime: now.subtract(const Duration(hours: 2)),
        toTime: now,
        source: StepRecordSource.external,
      );

      final logs = await stepCounter.getStepLogs();
      expect(logs.length, 1);
      expect(logs.first.stepCount, 500);
      expect(logs.first.source, StepRecordSource.external);
    });

    test('getTodayStepCount works without isolate', () async {
      await stepCounter.startLogging(config: StepRecordConfig.aggregated());

      final now = DateTime.now();

      await stepCounter.writeStepsToAggregated(
        stepCount: 1000,
        fromTime: now.subtract(const Duration(hours: 1)),
        toTime: now,
        source: StepRecordSource.external,
      );

      final todayCount = await stepCounter.getTodayStepCount();
      expect(todayCount, 1000);
    });

    test('clearStepLogs works without isolate', () async {
      await stepCounter.startLogging(config: StepRecordConfig.aggregated());

      final now = DateTime.now();

      await stepCounter.writeStepsToAggregated(
        stepCount: 1000,
        fromTime: now.subtract(const Duration(hours: 1)),
        toTime: now,
        source: StepRecordSource.external,
      );

      await stepCounter.clearStepLogs();

      final logs = await stepCounter.getStepLogs();
      expect(logs.isEmpty, isTrue);
    });
  });

  group('Backward compatibility', () {
    late AccurateStepCounter stepCounter;

    setUp(() async {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
      await DatabaseHelper.resetInstance();
    });

    test('existing code without isolate still works', () async {
      // This is how existing code would use the API
      await stepCounter.initializeLogging();
      await stepCounter.startLogging(config: StepRecordConfig.aggregated());

      final now = DateTime.now();

      await stepCounter.writeStepsToAggregated(
        stepCount: 500,
        fromTime: now.subtract(const Duration(hours: 2)),
        toTime: now,
        source: StepRecordSource.external,
      );

      final logs = await stepCounter.getStepLogs();
      expect(logs.length, 1);
      expect(logs.first.stepCount, 500);
    });

    test('all existing presets work without changes', () async {
      // Walking preset
      await stepCounter.initializeLogging();
      await stepCounter.startLogging(config: StepRecordConfig.walking());
      expect(stepCounter.isLoggingEnabled, isTrue);
      await stepCounter.stopLogging();
      await stepCounter.dispose();
      await DatabaseHelper.resetInstance();

      // Running preset
      stepCounter = AccurateStepCounter();
      await stepCounter.initializeLogging();
      await stepCounter.startLogging(config: StepRecordConfig.running());
      expect(stepCounter.isLoggingEnabled, isTrue);
      await stepCounter.stopLogging();
      await stepCounter.dispose();
      await DatabaseHelper.resetInstance();

      // Conservative preset
      stepCounter = AccurateStepCounter();
      await stepCounter.initializeLogging();
      await stepCounter.startLogging(config: StepRecordConfig.conservative());
      expect(stepCounter.isLoggingEnabled, isTrue);
    });
  });

  // Note: The following tests are skipped because isolates cannot share
  // the databaseFactoryFfi from the main isolate. The isolate creates its
  // own database connection which doesn't have access to the FFI factory.
  // These would work on a real device but not in unit tests.
  group('AccurateStepCounter with isolate mode (skipped in tests)', () {
    test('initializeLogging with isolate works on real device', () {
      // This test demonstrates the API but cannot run in unit tests
      // because isolates don't share the FFI database factory
    });
  }, skip: 'Isolate tests require real device - isolates cannot share FFI database factory');
}
