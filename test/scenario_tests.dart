import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/models/step_record.dart';
import 'package:accurate_step_counter/src/models/step_record_source.dart';

/// Comprehensive test scenarios based on TEST_SCENARIOS_COMPREHENSIVE.md
void main() {
  group('Scenario 2: External Source Import', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('2.1 Import external steps without double-counting', () async {
      // Initialize
      await stepCounter.initializeLogging(debugLogging: false);

      // Import 500 steps from Google Fit
      final now = DateTime.now();
      final twoHoursAgo = now.subtract(const Duration(hours: 2));

      await stepCounter.writeStepsToAggregated(
        stepCount: 500,
        fromTime: twoHoursAgo,
        toTime: now,
        source: StepRecordSource.external,
      );

      // Verify steps were imported
      final logs = await stepCounter.getStepLogs();
      expect(logs.length, 1);
      expect(logs.first.stepCount, 500);
      expect(logs.first.source, StepRecordSource.external);
      expect(logs.first.fromTime, twoHoursAgo);
      expect(logs.first.toTime, now);
    });

    test('2.2 Import multiple batches and verify total', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Import batch 1: Google Fit (500 steps)
      await stepCounter.writeStepsToAggregated(
        stepCount: 500,
        fromTime: now.subtract(const Duration(hours: 4)),
        toTime: now.subtract(const Duration(hours: 3)),
        source: StepRecordSource.external,
      );

      // Import batch 2: Apple Health (300 steps)
      await stepCounter.writeStepsToAggregated(
        stepCount: 300,
        fromTime: now.subtract(const Duration(hours: 2)),
        toTime: now.subtract(const Duration(hours: 1)),
        source: StepRecordSource.external,
      );

      // Verify total
      final total = await stepCounter.getTotalSteps();
      expect(total, 800);

      // Verify external steps only
      final externalSteps = await stepCounter.getStepsBySource(
        StepRecordSource.external,
      );
      expect(externalSteps, 800);
    });

    test('2.3 Verify source tracking after import', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Import external steps
      await stepCounter.writeStepsToAggregated(
        stepCount: 100,
        fromTime: now.subtract(const Duration(hours: 1)),
        toTime: now,
        source: StepRecordSource.external,
      );

      // Get logs and verify source
      final logs = await stepCounter.getStepLogs();
      expect(
        logs.every((log) => log.source == StepRecordSource.external),
        true,
      );
    });

    test('2.4 Error handling - negative steps', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Attempt to import negative steps
      expect(
        () => stepCounter.writeStepsToAggregated(
          stepCount: -100,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('2.5 Error handling - toTime before fromTime', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Attempt to import with invalid time range
      expect(
        () => stepCounter.writeStepsToAggregated(
          stepCount: 100,
          fromTime: now,
          toTime: now.subtract(const Duration(hours: 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Scenario 3: Aggregated Mode with No Warmup', () {
    test('3.1 Default config has no warmup', () {
      final config = StepRecordConfig.aggregated();

      expect(config.warmupDurationMs, 0);
      expect(config.minStepsToValidate, 1);
      expect(config.enableAggregatedMode, true);
      expect(config.maxStepsPerSecond, 5.0);
    });

    test('3.2 Walking preset has warmup', () {
      final config = StepRecordConfig.walking();

      expect(config.warmupDurationMs, 5000);
      expect(config.minStepsToValidate, 8);
      expect(config.inactivityTimeoutMs, 10000);
    });

    test('3.3 Running preset has warmup', () {
      final config = StepRecordConfig.running();

      expect(config.warmupDurationMs, 3000);
      expect(config.minStepsToValidate, 10);
      expect(config.inactivityTimeoutMs, 8000);
    });

    test('3.4 Custom config with copyWith', () {
      final base = StepRecordConfig.aggregated();
      final custom = base.copyWith(
        inactivityTimeoutMs: 5000,
        maxStepsPerSecond: 3.0,
      );

      expect(custom.warmupDurationMs, 0); // Preserved
      expect(custom.inactivityTimeoutMs, 5000); // Modified
      expect(custom.maxStepsPerSecond, 3.0); // Modified
      expect(custom.enableAggregatedMode, true); // Preserved
    });
  });

  group('Scenario 4: Stream Initialization and Data Flow', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('4.1 watchTodaySteps emits initial value immediately', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      // Pre-populate with some steps
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: startOfToday,
          toTime: now,
          source: StepRecordSource.foreground,
        ),
      );

      // Subscribe and get first emission
      int? firstValue;
      final subscription = stepCounter.watchTodaySteps().listen((steps) {
        firstValue ??= steps;
      });

      // Wait a bit for stream to emit
      await Future.delayed(const Duration(milliseconds: 100));

      expect(firstValue, isNotNull);
      expect(firstValue, greaterThanOrEqualTo(100));

      await subscription.cancel();
    });

    test('4.2 Stream emits updates when new steps added', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final emissions = <int>[];
      final subscription = stepCounter.watchTodaySteps().listen((steps) {
        emissions.add(steps);
      });

      // Wait for initial emission
      await Future.delayed(const Duration(milliseconds: 100));
      final initialCount = emissions.length;

      // Add new steps
      final now = DateTime.now();
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(minutes: 5)),
          toTime: now,
          source: StepRecordSource.foreground,
        ),
      );

      // Wait for emission
      await Future.delayed(const Duration(milliseconds: 100));

      expect(emissions.length, greaterThan(initialCount));

      await subscription.cancel();
    });

    test('4.3 Multiple subscribers receive same data', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      int? value1;
      int? value2;

      final sub1 = stepCounter.watchTodaySteps().listen((steps) {
        value1 ??= steps;
      });

      final sub2 = stepCounter.watchTodaySteps().listen((steps) {
        value2 ??= steps;
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(value1, isNotNull);
      expect(value2, isNotNull);
      expect(value1, equals(value2));

      await sub1.cancel();
      await sub2.cancel();
    });
  });

  group('Scenario 5: Error Handling and Recovery', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('5.1 Call methods before initialization throws error', () {
      expect(() => stepCounter.getTotalSteps(), throwsA(isA<StateError>()));

      expect(() => stepCounter.watchTodaySteps(), throwsA(isA<StateError>()));
    });

    test('5.2 Start logging before initializeLogging throws error', () async {
      expect(() => stepCounter.startLogging(), throwsA(isA<StateError>()));
    });

    test('5.3 Multiple initialization is safe', () async {
      await stepCounter.initializeLogging(debugLogging: false);
      await stepCounter.initializeLogging(
        debugLogging: false,
      ); // Should be no-op

      // Verify still works
      final total = await stepCounter.getTotalSteps();
      expect(total, isA<int>());
    });

    test('5.4 Dispose and reinitialize works', () async {
      // First initialization
      await stepCounter.initializeLogging(debugLogging: false);
      final total1 = await stepCounter.getTotalSteps();

      // Dispose
      await stepCounter.dispose();

      // Reinitialize
      stepCounter = AccurateStepCounter();
      await stepCounter.initializeLogging(debugLogging: false);
      final total2 = await stepCounter.getTotalSteps();

      expect(total2, isA<int>());
    });

    test('5.5 Clear logs and verify empty', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      // Add some data
      final now = DateTime.now();
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.foreground,
        ),
      );

      // Verify data exists
      final beforeClear = await stepCounter.getTotalSteps();
      expect(beforeClear, greaterThan(0));

      // Clear
      await stepCounter.clearStepLogs();

      // Verify empty
      final afterClear = await stepCounter.getTotalSteps();
      expect(afterClear, 0);
    });

    test('5.6 Delete old logs works correctly', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Add old record (40 days ago)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(days: 40)),
          toTime: now.subtract(const Duration(days: 40)),
          source: StepRecordSource.foreground,
        ),
      );

      // Add recent record (1 day ago)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(days: 1)),
          toTime: now.subtract(const Duration(days: 1)),
          source: StepRecordSource.foreground,
        ),
      );

      // Delete logs older than 30 days
      await stepCounter.deleteStepLogsBefore(
        now.subtract(const Duration(days: 30)),
      );

      // Verify only recent data remains
      final total = await stepCounter.getTotalSteps();
      expect(total, 50);
    });
  });

  group('All StepRecordSource Values', () {
    test('All source types are available', () {
      expect(StepRecordSource.values.length, 4);
      expect(StepRecordSource.values, contains(StepRecordSource.foreground));
      expect(StepRecordSource.values, contains(StepRecordSource.background));
      expect(StepRecordSource.values, contains(StepRecordSource.terminated));
      expect(StepRecordSource.values, contains(StepRecordSource.external));
    });
  });

  // ============================================================
  // HYBRID ARCHITECTURE SCENARIOS
  // ============================================================

  group('Scenario 6: Hybrid Architecture - No Duplicate Writes', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('6.1 Foreground service config has correct default API level', () {
      final config = const StepDetectorConfig();

      expect(config.foregroundServiceMaxApiLevel, 29); // Android 10
      expect(config.useForegroundServiceOnOldDevices, true);
    });

    test('6.2 Custom API level configuration', () {
      final config = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 32, // Android 12
      );

      expect(config.foregroundServiceMaxApiLevel, 32);
    });

    test('6.3 Terminated steps have correct source', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));

      // Simulate terminated step log
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: oneHourAgo,
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      // Verify source
      final terminatedSteps = await stepCounter.getStepsBySource(
        StepRecordSource.terminated,
      );
      expect(terminatedSteps, 100);

      // Verify no foreground steps
      final foregroundSteps = await stepCounter.getStepsBySource(
        StepRecordSource.foreground,
      );
      expect(foregroundSteps, 0);
    });

    test('6.4 No duplicates when mixing sources', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Simulate foreground steps
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now.subtract(const Duration(hours: 1)),
          source: StepRecordSource.foreground,
        ),
      );

      // Simulate terminated steps (from foreground service sync)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 30,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      // Total should be sum of both (no duplicates)
      final total = await stepCounter.getTotalSteps();
      expect(total, 80);

      // Verify each source has correct count
      final fg = await stepCounter.getStepsBySource(
        StepRecordSource.foreground,
      );
      final term = await stepCounter.getStepsBySource(
        StepRecordSource.terminated,
      );
      expect(fg, 50);
      expect(term, 30);
    });

    test('6.5 Stats distinguish between sources correctly', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Add steps from different sources
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 3)),
          toTime: now.subtract(const Duration(hours: 2)),
          source: StepRecordSource.foreground,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 75,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now.subtract(const Duration(hours: 1)),
          source: StepRecordSource.background,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 25,
          fromTime: now.subtract(const Duration(minutes: 30)),
          toTime: now,
          source: StepRecordSource.external,
        ),
      );

      // Get stats
      final stats = await stepCounter.getStepStats();

      expect(stats['totalSteps'], 250);
      expect(stats['foregroundSteps'], 100);
      expect(stats['backgroundSteps'], 75);
      expect(stats['terminatedSteps'], 50);
      expect(stats['externalSteps'], 25);
    });

    test('6.6 Config presets have correct foreground service settings', () {
      final walking = StepDetectorConfig.walking();
      final running = StepDetectorConfig.running();
      final sensitive = StepDetectorConfig.sensitive();
      final conservative = StepDetectorConfig.conservative();

      // All presets should have foreground service enabled by default
      expect(walking.useForegroundServiceOnOldDevices, true);
      expect(running.useForegroundServiceOnOldDevices, true);
      expect(sensitive.useForegroundServiceOnOldDevices, true);
      expect(conservative.useForegroundServiceOnOldDevices, true);

      // All presets should use default API level (29)
      expect(walking.foregroundServiceMaxApiLevel, 29);
      expect(running.foregroundServiceMaxApiLevel, 29);
      expect(sensitive.foregroundServiceMaxApiLevel, 29);
      expect(conservative.foregroundServiceMaxApiLevel, 29);
    });
  });

  group('Scenario 7: Step Rate Validation (No False Positives)', () {
    test('7.1 Aggregated config has reasonable max step rate', () {
      final config = StepRecordConfig.aggregated();

      // 5 steps/second is reasonable for running
      expect(config.maxStepsPerSecond, 5.0);
    });

    test('7.2 Walking config has stricter step rate', () {
      final config = StepRecordConfig.walking();

      // Walking should have lower max rate
      expect(config.maxStepsPerSecond, 3.0);
    });

    test('7.3 Running config allows faster step rate', () {
      final config = StepRecordConfig.running();

      // Running allows faster steps
      expect(config.maxStepsPerSecond, 5.0);
    });

    test('7.4 Custom step rate can be configured', () {
      final config = StepRecordConfig(maxStepsPerSecond: 2.5);

      expect(config.maxStepsPerSecond, 2.5);
    });
  });

  group('Scenario 8: Android 11+ Compatibility (API > 29)', () {
    test('8.1 Default config works for all API levels', () {
      final config = const StepDetectorConfig();

      // Should work for both old and new Android
      expect(config.useForegroundServiceOnOldDevices, true);
      expect(config.foregroundServiceMaxApiLevel, 29);
      expect(config.enableOsLevelSync, true);
    });

    test('8.2 OS level sync enabled by default for terminated state', () {
      final config = const StepDetectorConfig();

      // TYPE_STEP_COUNTER sync should be enabled for Android 11+
      expect(config.enableOsLevelSync, true);
    });

    test('8.3 Disabled foreground service still allows OS sync', () {
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: false, // Disabled
        enableOsLevelSync: true, // But OS sync enabled
      );

      expect(config.useForegroundServiceOnOldDevices, false);
      expect(config.enableOsLevelSync, true);
    });

    test('8.4 Custom max API level for special cases', () {
      // Some apps might want foreground service on Android 12 too
      final config = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 32, // Android 12L
      );

      expect(config.foregroundServiceMaxApiLevel, 32);
    });
  });
}
