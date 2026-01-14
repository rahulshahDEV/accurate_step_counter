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

  // ============================================================
  // REAL-LIFE TEST SCENARIOS
  // ============================================================

  group('Scenario 9: Android ≤10 Foreground Service Mode', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('9.1 Config for foreground service mode is correct', () {
      // Simulate Android 10 config
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: true,
        foregroundServiceMaxApiLevel: 29,
        foregroundNotificationTitle: 'Step Counter',
        foregroundNotificationText: 'Tracking your steps...',
      );

      expect(config.useForegroundServiceOnOldDevices, true);
      expect(config.foregroundServiceMaxApiLevel, 29);
      expect(config.foregroundNotificationTitle, 'Step Counter');
      expect(config.foregroundNotificationText, 'Tracking your steps...');
    });

    test('9.2 Steps logged correctly in foreground service mode', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Simulate steps from foreground service (background source when using service)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 150,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.background,
        ),
      );

      final total = await stepCounter.getTotalSteps();
      expect(total, 150);

      final bgSteps = await stepCounter.getStepsBySource(
        StepRecordSource.background,
      );
      expect(bgSteps, 150);
    });

    test('9.3 Session restart does not duplicate steps', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // First session - 100 steps
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now.subtract(const Duration(hours: 1)),
          source: StepRecordSource.background,
        ),
      );

      // Second session - 50 NEW steps (not cumulative)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.background,
        ),
      );

      // Total should be 150 (no duplication)
      final total = await stepCounter.getTotalSteps();
      expect(total, 150);

      // Should have 2 records
      final logs = await stepCounter.getStepLogs();
      expect(logs.length, 2);
    });

    test('9.4 Terminated steps sync on restart', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Simulate terminated sync (steps from foreground service while app was killed)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 200,
          fromTime: now.subtract(const Duration(hours: 3)),
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      final total = await stepCounter.getTotalSteps();
      expect(total, 200);

      final terminatedSteps = await stepCounter.getStepsBySource(
        StepRecordSource.terminated,
      );
      expect(terminatedSteps, 200);
    });
  });

  group('Scenario 10: Android 11+ Native Detector Mode', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('10.1 Config for native detector mode is correct', () {
      // Default config works for Android 11+
      final config = const StepDetectorConfig();

      expect(config.enableOsLevelSync, true);
      expect(config.useForegroundServiceOnOldDevices, true);
      // Android 11+ (API 30+) won't trigger foreground service
    });

    test('10.2 Foreground steps logged correctly', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Steps while app in foreground
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(minutes: 30)),
          toTime: now,
          source: StepRecordSource.foreground,
        ),
      );

      final fgSteps = await stepCounter.getStepsBySource(
        StepRecordSource.foreground,
      );
      expect(fgSteps, 100);
    });

    test('10.3 Background steps logged correctly', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Steps while app in background
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 75,
          fromTime: now.subtract(const Duration(minutes: 20)),
          toTime: now,
          source: StepRecordSource.background,
        ),
      );

      final bgSteps = await stepCounter.getStepsBySource(
        StepRecordSource.background,
      );
      expect(bgSteps, 75);
    });

    test('10.4 Terminated state sync logged correctly', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Steps synced from TYPE_STEP_COUNTER after app termination
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 500,
          fromTime: now.subtract(const Duration(hours: 8)),
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      final terminatedSteps = await stepCounter.getStepsBySource(
        StepRecordSource.terminated,
      );
      expect(terminatedSteps, 500);
    });

    test('10.5 All sources combined correctly', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Mixed sources
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 4)),
          toTime: now.subtract(const Duration(hours: 3)),
          source: StepRecordSource.foreground,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 3)),
          toTime: now.subtract(const Duration(hours: 2)),
          source: StepRecordSource.background,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 200,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 25,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.external,
        ),
      );

      // Total = 100 + 50 + 200 + 25 = 375
      final total = await stepCounter.getTotalSteps();
      expect(total, 375);

      // Stats breakdown
      final stats = await stepCounter.getStepStats();
      expect(stats['foregroundSteps'], 100);
      expect(stats['backgroundSteps'], 50);
      expect(stats['terminatedSteps'], 200);
      expect(stats['externalSteps'], 25);
    });

    test('10.6 Today steps calculation correct', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      // Add steps for today
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 150,
          fromTime: startOfToday.add(const Duration(hours: 8)),
          toTime: startOfToday.add(const Duration(hours: 10)),
          source: StepRecordSource.foreground,
        ),
      );

      // Query today's steps
      final todaySteps = await stepCounter.getTodayStepCount();
      expect(todaySteps, 150);
    });
  });

  group('Scenario 11: Warmup and Inactivity Timeout (Both Modes)', () {
    test('11.1 Warmup config works with aggregated preset', () {
      final config = StepRecordConfig.aggregated().copyWith(
        warmupDurationMs: 8000,
        inactivityTimeoutMs: 2000,
      );

      expect(config.warmupDurationMs, 8000);
      expect(config.inactivityTimeoutMs, 2000);
      expect(config.enableAggregatedMode, true);
    });

    test('11.2 Walking preset has proper warmup', () {
      final config = StepRecordConfig.walking();

      expect(config.warmupDurationMs, 5000);
      expect(config.minStepsToValidate, 8);
      expect(config.inactivityTimeoutMs, 10000);
    });

    test('11.3 Custom inactivity timeout', () {
      final config = StepRecordConfig(inactivityTimeoutMs: 5000);

      expect(config.inactivityTimeoutMs, 5000);
    });

    test('11.4 Zero warmup means immediate counting', () {
      final config = StepRecordConfig.aggregated();

      expect(config.warmupDurationMs, 0);
      expect(config.minStepsToValidate, 1);
    });

    test('11.5 Config presets preserve customizations', () {
      final base = StepRecordConfig.aggregated();
      final custom = base.copyWith(
        warmupDurationMs: 8000,
        inactivityTimeoutMs: 2000,
      );

      // Preserved from aggregated
      expect(custom.enableAggregatedMode, true);
      expect(custom.maxStepsPerSecond, 5.0);

      // Customized
      expect(custom.warmupDurationMs, 8000);
      expect(custom.inactivityTimeoutMs, 2000);
    });

    test('11.6 Detector config and record config are separate', () {
      final detectorConfig = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 32,
      );

      final recordConfig = StepRecordConfig.aggregated().copyWith(
        warmupDurationMs: 8000,
      );

      // These are independent configurations
      expect(detectorConfig.foregroundServiceMaxApiLevel, 32);
      expect(recordConfig.warmupDurationMs, 8000);
    });
  });

  // ============================================================
  // COMPREHENSIVE REAL-LIFE SCENARIOS
  // ============================================================

  group('Scenario 12: Complete Integration Tests', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('12.1 Full initialization flow works', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      // Should be ready to start
      expect(stepCounter.isLoggingInitialized, true);
    });

    test('12.2 Config chain preserves all settings', () {
      final detectorConfig = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 32,
        useForegroundServiceOnOldDevices: true,
        foregroundNotificationTitle: 'Test Title',
        foregroundNotificationText: 'Test Text',
      );

      final recordConfig = StepRecordConfig.aggregated().copyWith(
        warmupDurationMs: 8000,
        inactivityTimeoutMs: 2000,
      );

      // Detector config preserved
      expect(detectorConfig.foregroundServiceMaxApiLevel, 32);
      expect(detectorConfig.useForegroundServiceOnOldDevices, true);
      expect(detectorConfig.foregroundNotificationTitle, 'Test Title');
      expect(detectorConfig.foregroundNotificationText, 'Test Text');

      // Record config preserved
      expect(recordConfig.warmupDurationMs, 8000);
      expect(recordConfig.inactivityTimeoutMs, 2000);
      expect(recordConfig.enableAggregatedMode, true);
    });

    test('12.3 Multiple step records from different sources', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Add steps from all 4 sources
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 4)),
          toTime: now.subtract(const Duration(hours: 3)),
          source: StepRecordSource.foreground,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 75,
          fromTime: now.subtract(const Duration(hours: 3)),
          toTime: now.subtract(const Duration(hours: 2)),
          source: StepRecordSource.background,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 200,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now.subtract(const Duration(hours: 1)),
          source: StepRecordSource.terminated,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.external,
        ),
      );

      // Total: 100 + 75 + 200 + 50 = 425
      final total = await stepCounter.getTotalSteps();
      expect(total, 425);

      // Stats breakdown
      final stats = await stepCounter.getStepStats();
      expect(stats['foregroundSteps'], 100);
      expect(stats['backgroundSteps'], 75);
      expect(stats['terminatedSteps'], 200);
      expect(stats['externalSteps'], 50);
    });

    test('12.4 Date range queries work correctly', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final today = DateTime(now.year, now.month, now.day);

      // Yesterday's steps
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 5000,
          fromTime: yesterday.add(const Duration(hours: 10)),
          toTime: yesterday.add(const Duration(hours: 18)),
          source: StepRecordSource.foreground,
        ),
      );

      // Today's steps
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 3000,
          fromTime: today.add(const Duration(hours: 8)),
          toTime: today.add(const Duration(hours: 12)),
          source: StepRecordSource.foreground,
        ),
      );

      final yesterdayTotal = await stepCounter.getStepCount(
        start: yesterday,
        end: today,
      );
      expect(yesterdayTotal, 5000);

      final todayTotal = await stepCounter.getTodayStepCount();
      expect(todayTotal, 3000);
    });

    test('12.5 Step logs can be queried by source', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.external,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 200,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now.subtract(const Duration(hours: 1)),
          source: StepRecordSource.foreground,
        ),
      );

      final externalLogs = await stepCounter.getStepLogs(
        source: StepRecordSource.external,
      );
      expect(externalLogs.length, 1);
      expect(externalLogs.first.stepCount, 100);

      final foregroundLogs = await stepCounter.getStepLogs(
        source: StepRecordSource.foreground,
      );
      expect(foregroundLogs.length, 1);
      expect(foregroundLogs.first.stepCount, 200);
    });

    test('12.6 Write to aggregated works with external source', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Simulate Health Connect import
      await stepCounter.writeStepsToAggregated(
        stepCount: 1000,
        fromTime: now.subtract(const Duration(hours: 3)),
        toTime: now,
        source: StepRecordSource.external,
      );

      final externalSteps = await stepCounter.getStepsBySource(
        StepRecordSource.external,
      );
      expect(externalSteps, 1000);
    });
  });

  group('Scenario 13: Warmup Validation Behavior', () {
    test('13.1 Warmup with custom duration', () {
      final config = StepRecordConfig(
        warmupDurationMs: 8000,
        minStepsToValidate: 15,
      );

      expect(config.warmupDurationMs, 8000);
      expect(config.minStepsToValidate, 15);
    });

    test('13.2 Warmup disabled with zero duration', () {
      final config = StepRecordConfig(warmupDurationMs: 0);

      expect(config.warmupDurationMs, 0);
    });

    test('13.3 Aggregated preset has no warmup by default', () {
      final config = StepRecordConfig.aggregated();

      expect(config.warmupDurationMs, 0);
      expect(config.minStepsToValidate, 1);
    });

    test('13.4 Walking preset has standard warmup', () {
      final config = StepRecordConfig.walking();

      expect(config.warmupDurationMs, 5000);
      expect(config.minStepsToValidate, 8);
    });
  });

  group('Scenario 14: EventChannel and Polling Coexistence', () {
    test('14.1 Detector config enables foreground service', () {
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: true,
        foregroundServiceMaxApiLevel: 29,
      );

      expect(config.useForegroundServiceOnOldDevices, true);
      expect(config.foregroundServiceMaxApiLevel, 29);
    });

    test('14.2 Detector config for Android 10 and below', () {
      final config = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 29,
        useForegroundServiceOnOldDevices: true,
      );

      expect(config.foregroundServiceMaxApiLevel, 29);
      expect(config.useForegroundServiceOnOldDevices, true);
    });

    test('14.3 Detector config for Android 12 and below', () {
      final config = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 32,
        useForegroundServiceOnOldDevices: true,
      );

      expect(config.foregroundServiceMaxApiLevel, 32);
      expect(config.useForegroundServiceOnOldDevices, true);
    });

    test('14.4 OS level sync enabled by default', () {
      final config = const StepDetectorConfig();

      expect(config.enableOsLevelSync, true);
    });
  });

  // ============================================================
  // DUPLICATE STEP PREVENTION SCENARIOS
  // ============================================================

  group('Scenario 15: Duplicate Step Prevention', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('15.1 Foreground to background: no duplicate counts', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Foreground session: 100 steps
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now.subtract(const Duration(hours: 1)),
          source: StepRecordSource.foreground,
        ),
      );

      // Background session: 50 NEW steps (starting after foreground ended)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.background,
        ),
      );

      // Total should be exactly 150 (no duplication)
      final total = await stepCounter.getTotalSteps();
      expect(total, 150);

      // Verify each source has correct distinct count
      final fg = await stepCounter.getStepsBySource(
        StepRecordSource.foreground,
      );
      final bg = await stepCounter.getStepsBySource(
        StepRecordSource.background,
      );
      expect(fg, 100);
      expect(bg, 50);
    });

    test('15.2 Background to terminated: no duplicate counts', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Background session while app was in background
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 75,
          fromTime: now.subtract(const Duration(hours: 3)),
          toTime: now.subtract(const Duration(hours: 2)),
          source: StepRecordSource.background,
        ),
      );

      // Terminated sync: steps counted while app was killed
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      // Total should be 175 (no duplication)
      final total = await stepCounter.getTotalSteps();
      expect(total, 175);
    });

    test(
      '15.3 Terminated sync does not overlap with existing records',
      () async {
        await stepCounter.initializeLogging(debugLogging: false);

        final now = DateTime.now();

        // First terminated sync at 10:00
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 200,
            fromTime: now.subtract(const Duration(hours: 4)),
            toTime: now.subtract(const Duration(hours: 2)),
            source: StepRecordSource.terminated,
          ),
        );

        // Second terminated sync at 12:00 (non-overlapping)
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 100,
            fromTime: now.subtract(const Duration(hours: 2)),
            toTime: now,
            source: StepRecordSource.terminated,
          ),
        );

        // Total should be sum of both
        final total = await stepCounter.getTotalSteps();
        expect(total, 300);

        // Get logs and verify they're distinct
        final logs = await stepCounter.getStepLogs();
        expect(logs.length, 2);
      },
    );

    test('15.4 Multiple state transitions: total is correct', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Simulate full day: foreground → background → terminated → foreground
      // Period 1: Morning walk (foreground)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 8)),
          toTime: now.subtract(const Duration(hours: 7)),
          source: StepRecordSource.foreground,
        ),
      );

      // Period 2: App in background (background)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 7)),
          toTime: now.subtract(const Duration(hours: 6)),
          source: StepRecordSource.background,
        ),
      );

      // Period 3: App killed for hours (terminated sync)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 200,
          fromTime: now.subtract(const Duration(hours: 6)),
          toTime: now.subtract(const Duration(hours: 2)),
          source: StepRecordSource.terminated,
        ),
      );

      // Period 4: Evening walk (foreground)
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 75,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now,
          source: StepRecordSource.foreground,
        ),
      );

      // Total: 100 + 50 + 200 + 75 = 425
      final total = await stepCounter.getTotalSteps();
      expect(total, 425);

      // Verify stats breakdown
      final stats = await stepCounter.getStepStats();
      expect(stats['foregroundSteps'], 175); // 100 + 75
      expect(stats['backgroundSteps'], 50);
      expect(stats['terminatedSteps'], 200);
    });

    test('15.5 Rapid state changes do not cause duplicates', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Quick foreground → background → foreground cycle
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 10,
          fromTime: now.subtract(const Duration(minutes: 10)),
          toTime: now.subtract(const Duration(minutes: 8)),
          source: StepRecordSource.foreground,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 5,
          fromTime: now.subtract(const Duration(minutes: 8)),
          toTime: now.subtract(const Duration(minutes: 6)),
          source: StepRecordSource.background,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 15,
          fromTime: now.subtract(const Duration(minutes: 6)),
          toTime: now,
          source: StepRecordSource.foreground,
        ),
      );

      // Total: 10 + 5 + 15 = 30
      final total = await stepCounter.getTotalSteps();
      expect(total, 30);
    });

    test(
      '15.6 External import does not duplicate with native counts',
      () async {
        await stepCounter.initializeLogging(debugLogging: false);

        final now = DateTime.now();

        // Native counting (foreground)
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 500,
            fromTime: now.subtract(const Duration(hours: 4)),
            toTime: now.subtract(const Duration(hours: 2)),
            source: StepRecordSource.foreground,
          ),
        );

        // External import (Health Connect) for DIFFERENT time period
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 300,
            fromTime: now.subtract(const Duration(hours: 8)),
            toTime: now.subtract(const Duration(hours: 4)),
            source: StepRecordSource.external,
          ),
        );

        // Total: 500 + 300 = 800
        final total = await stepCounter.getTotalSteps();
        expect(total, 800);

        // Verify distinct sources
        final fg = await stepCounter.getStepsBySource(
          StepRecordSource.foreground,
        );
        final ext = await stepCounter.getStepsBySource(
          StepRecordSource.external,
        );
        expect(fg, 500);
        expect(ext, 300);
      },
    );
  });

  // ============================================================
  // SAMSUNG TYPE_STEP_DETECTOR FIX VERIFICATION
  // ============================================================

  group('Scenario 16: TYPE_STEP_DETECTOR Priority (Samsung Fix)', () {
    test('16.1 Config allows hardware detector configuration', () {
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: true,
        foregroundServiceMaxApiLevel: 32, // Android 12
      );

      expect(config.useForegroundServiceOnOldDevices, true);
      expect(config.foregroundServiceMaxApiLevel, 32);
    });

    test('16.2 Default config uses API 29 cutoff', () {
      final config = const StepDetectorConfig();

      // TYPE_STEP_DETECTOR (native) should be used for API > 29
      // TYPE_STEP_COUNTER (foreground service) for API <= 29
      expect(config.foregroundServiceMaxApiLevel, 29);
    });

    test('16.3 Running preset preserves detector settings', () {
      final config = StepDetectorConfig.running();

      // Running preset should still have default service settings
      expect(config.useForegroundServiceOnOldDevices, true);
      expect(config.foregroundServiceMaxApiLevel, 29);
    });

    test('16.4 Custom config can extend foreground service to newer APIs', () {
      // For Samsung devices that don't support TYPE_STEP_COUNTER well
      final config = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 33, // Android 13
        useForegroundServiceOnOldDevices: true,
      );

      expect(config.foregroundServiceMaxApiLevel, 33);
      expect(config.useForegroundServiceOnOldDevices, true);
    });
  });

  // ============================================================
  // CROSS-API LEVEL BEHAVIOR
  // ============================================================

  group('Scenario 17: Cross-API Level Behavior', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('17.1 Android 10 config uses foreground service', () {
      final config = StepDetectorConfig(
        foregroundServiceMaxApiLevel: 29, // Android 10
        useForegroundServiceOnOldDevices: true,
        foregroundNotificationTitle: 'Step Counter',
        foregroundNotificationText: 'Tracking steps in background',
      );

      expect(config.foregroundServiceMaxApiLevel, 29);
      expect(config.foregroundNotificationTitle, 'Step Counter');
      expect(config.foregroundNotificationText, 'Tracking steps in background');
    });

    test('17.2 Android 11+ config uses native detector', () {
      final config = StepDetectorConfig(
        enableOsLevelSync: true, // For terminated state
        useForegroundServiceOnOldDevices: true,
        foregroundServiceMaxApiLevel: 29, // Only for API <= 29
      );

      // API > 29 should use native TYPE_STEP_DETECTOR instead
      expect(config.enableOsLevelSync, true);
      expect(config.foregroundServiceMaxApiLevel, 29);
    });

    test('17.3 Terminated source works for both API levels', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Terminated steps should work regardless of API level
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 500,
          fromTime: now.subtract(const Duration(hours: 8)),
          toTime: now,
          source: StepRecordSource.terminated,
        ),
      );

      final terminated = await stepCounter.getStepsBySource(
        StepRecordSource.terminated,
      );
      expect(terminated, 500);
    });

    test('17.4 Config respects foregroundServiceMaxApiLevel', () {
      // Test different API level configurations
      final config10 = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
      final config12 = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);
      final config13 = StepDetectorConfig(foregroundServiceMaxApiLevel: 33);

      expect(config10.foregroundServiceMaxApiLevel, 29);
      expect(config12.foregroundServiceMaxApiLevel, 32);
      expect(config13.foregroundServiceMaxApiLevel, 33);
    });

    test('17.5 All sources available on all API levels', () async {
      await stepCounter.initializeLogging(debugLogging: false);

      final now = DateTime.now();

      // Add steps from all sources
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 4)),
          toTime: now.subtract(const Duration(hours: 3)),
          source: StepRecordSource.foreground,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 75,
          fromTime: now.subtract(const Duration(hours: 3)),
          toTime: now.subtract(const Duration(hours: 2)),
          source: StepRecordSource.background,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 50,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now.subtract(const Duration(hours: 1)),
          source: StepRecordSource.terminated,
        ),
      );

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 25,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.external,
        ),
      );

      // All 4 sources should work
      final fg = await stepCounter.getStepsBySource(
        StepRecordSource.foreground,
      );
      final bg = await stepCounter.getStepsBySource(
        StepRecordSource.background,
      );
      final term = await stepCounter.getStepsBySource(
        StepRecordSource.terminated,
      );
      final ext = await stepCounter.getStepsBySource(StepRecordSource.external);

      expect(fg, 100);
      expect(bg, 75);
      expect(term, 50);
      expect(ext, 25);

      // Total: 250
      final total = await stepCounter.getTotalSteps();
      expect(total, 250);
    });
  });

  // ============================================================
  // SCENARIO 17: MIDNIGHT BOUNDARY HANDLING
  // ============================================================

  group('Scenario 17: Midnight Boundary Handling', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test(
      '17.1 Record ending at midnight is NOT included in today count',
      () async {
        await stepCounter.initializeLogging(debugLogging: false);

        final now = DateTime.now();
        final midnight = DateTime(
          now.year,
          now.month,
          now.day,
        ); // Today 00:00:00
        final yesterdayEvening = midnight.subtract(
          const Duration(hours: 6),
        ); // Yesterday 18:00:00

        // Add a record that ends exactly at midnight
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 500,
            fromTime: yesterdayEvening,
            toTime: midnight, // Ends at 00:00:00 today
            source: StepRecordSource.terminated,
          ),
        );

        // Today's count should be 0 (record belongs to yesterday)
        final todaySteps = await stepCounter.getTodaySteps();
        expect(todaySteps, 0);
      },
    );

    test(
      '17.2 Record ending after midnight IS included in today count',
      () async {
        await stepCounter.initializeLogging(debugLogging: false);

        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day);
        final afterMidnight = midnight.add(const Duration(seconds: 1));
        final yesterdayEvening = midnight.subtract(const Duration(hours: 6));

        // Add a record that ends just after midnight
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 500,
            fromTime: yesterdayEvening,
            toTime: afterMidnight, // Ends at 00:00:01 today
            source: StepRecordSource.terminated,
          ),
        );

        // Today's count should include this record
        final todaySteps = await stepCounter.getTodaySteps();
        expect(todaySteps, 500);
      },
    );

    test(
      '17.3 Separate yesterday and today records counted correctly',
      () async {
        await stepCounter.initializeLogging(debugLogging: false);

        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day);
        final yesterdayStart = midnight.subtract(const Duration(hours: 12));
        final yesterdayEnd = midnight.subtract(
          const Duration(milliseconds: 1),
        ); // 23:59:59.999

        // Yesterday's record (ending before midnight)
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 1000,
            fromTime: yesterdayStart,
            toTime: yesterdayEnd,
            source: StepRecordSource.foreground,
          ),
        );

        // Today's record
        await stepCounter.insertRecord(
          StepRecord(
            stepCount: 500,
            fromTime: midnight.add(const Duration(hours: 1)),
            toTime: now,
            source: StepRecordSource.foreground,
          ),
        );

        final todaySteps = await stepCounter.getTodaySteps();
        expect(todaySteps, 500); // Only today's steps
      },
    );
  });
}
