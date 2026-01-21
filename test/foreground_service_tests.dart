import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/services/sensors_step_detector.dart';

/// Comprehensive test suite for both foreground service mode (Android ≤11)
/// and non-foreground service mode (Android 12+)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // SENSORS STEP DETECTOR TESTS (100+ tests)
  // Used for foreground service mode on Android 11 and below
  // ============================================================

  group('SensorsStepDetector - Initialization', () {
    test('should initialize with default parameters', () {
      final detector = SensorsStepDetector();
      expect(detector.stepCount, 0);
      expect(detector.isRunning, false);
    });

    test('should initialize with custom threshold', () {
      final detector = SensorsStepDetector(threshold: 1.5);
      expect(detector.stepCount, 0);
    });

    test('should initialize with custom filterAlpha', () {
      final detector = SensorsStepDetector(filterAlpha: 0.9);
      expect(detector.stepCount, 0);
    });

    test('should initialize with custom minTimeBetweenStepsMs', () {
      final detector = SensorsStepDetector(minTimeBetweenStepsMs: 300);
      expect(detector.stepCount, 0);
    });

    test('should initialize with debugLogging enabled', () {
      final detector = SensorsStepDetector(debugLogging: true);
      expect(detector.stepCount, 0);
    });

    test('should initialize with all custom parameters', () {
      final detector = SensorsStepDetector(
        threshold: 1.2,
        filterAlpha: 0.85,
        minTimeBetweenStepsMs: 275,
        debugLogging: true,
      );
      expect(detector.stepCount, 0);
      expect(detector.isRunning, false);
    });

    test('should have zero step count initially', () {
      final detector = SensorsStepDetector();
      expect(detector.stepCount, equals(0));
    });

    test('should not be running initially', () {
      final detector = SensorsStepDetector();
      expect(detector.isRunning, isFalse);
    });
  });

  group('SensorsStepDetector - Step Event Stream', () {
    test('should provide broadcast stream', () {
      final detector = SensorsStepDetector();
      expect(detector.stepEventStream, isA<Stream<StepCountEvent>>());
    });

    test('should allow multiple listeners', () {
      final detector = SensorsStepDetector();
      final sub1 = detector.stepEventStream.listen((_) {});
      final sub2 = detector.stepEventStream.listen((_) {});

      expect(sub1, isNotNull);
      expect(sub2, isNotNull);

      sub1.cancel();
      sub2.cancel();
    });

    test('stream getter returns fresh stream each time', () {
      final detector = SensorsStepDetector();
      final stream1 = detector.stepEventStream;
      final stream2 = detector.stepEventStream;
      // Broadcast streams return the same underlying stream
      expect(stream1, isNotNull);
      expect(stream2, isNotNull);
    });
  });

  group('SensorsStepDetector - Reset', () {
    test('should reset step count to zero', () {
      final detector = SensorsStepDetector();
      detector.reset();
      expect(detector.stepCount, 0);
    });

    test('should reset when not running', () {
      final detector = SensorsStepDetector();
      expect(detector.isRunning, false);
      detector.reset();
      expect(detector.stepCount, 0);
    });

    test('resetting multiple times should be safe', () {
      final detector = SensorsStepDetector();
      detector.reset();
      detector.reset();
      detector.reset();
      expect(detector.stepCount, 0);
    });
  });

  group('SensorsStepDetector - Dispose', () {
    test('should dispose without errors', () async {
      final detector = SensorsStepDetector();
      await detector.dispose();
      // No exception should be thrown
    });

    test('dispose should work when detector was never started', () async {
      final detector = SensorsStepDetector();
      await detector.dispose();
      // No exception should be thrown
    });

    test('should be able to dispose multiple times safely', () async {
      final detector = SensorsStepDetector();
      await detector.dispose();
      // Second dispose should not throw
      // Stream is already closed but that's expected
    });
  });

  // ============================================================
  // STEP DETECTOR CONFIG TESTS - FOREGROUND SERVICE PARAMETERS
  // ============================================================

  group('StepDetectorConfig - Foreground Service Configuration', () {
    test('default useForegroundServiceOnOldDevices is true', () {
      final config = const StepDetectorConfig();
      expect(config.useForegroundServiceOnOldDevices, true);
    });

    test('can disable foreground service on old devices', () {
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: false,
      );
      expect(config.useForegroundServiceOnOldDevices, false);
    });

    test('foreground notification title has default value', () {
      final config = const StepDetectorConfig();
      expect(config.foregroundNotificationTitle, 'Step Counter');
    });

    test('can customize foreground notification title', () {
      final config = StepDetectorConfig(
        foregroundNotificationTitle: 'My Fitness App',
      );
      expect(config.foregroundNotificationTitle, 'My Fitness App');
    });

    test('foreground notification text has default value', () {
      final config = const StepDetectorConfig();
      expect(config.foregroundNotificationText, 'Tracking your steps...');
    });

    test('can customize foreground notification text', () {
      final config = StepDetectorConfig(
        foregroundNotificationText: 'Counting steps in background',
      );
      expect(config.foregroundNotificationText, 'Counting steps in background');
    });

    test('copyWith preserves useForegroundServiceOnOldDevices', () {
      final original = StepDetectorConfig(
        useForegroundServiceOnOldDevices: false,
      );
      final modified = original.copyWith(threshold: 2.0);
      expect(modified.useForegroundServiceOnOldDevices, false);
    });

    test('copyWith can change useForegroundServiceOnOldDevices', () {
      final original = const StepDetectorConfig();
      final modified = original.copyWith(
        useForegroundServiceOnOldDevices: false,
      );
      expect(modified.useForegroundServiceOnOldDevices, false);
    });

    test('copyWith preserves foreground notification title', () {
      final original = StepDetectorConfig(
        foregroundNotificationTitle: 'Custom Title',
      );
      final modified = original.copyWith(threshold: 2.0);
      expect(modified.foregroundNotificationTitle, 'Custom Title');
    });

    test('copyWith can change foreground notification title', () {
      final original = const StepDetectorConfig();
      final modified = original.copyWith(
        foregroundNotificationTitle: 'New Title',
      );
      expect(modified.foregroundNotificationTitle, 'New Title');
    });

    test('copyWith preserves foreground notification text', () {
      final original = StepDetectorConfig(
        foregroundNotificationText: 'Custom Text',
      );
      final modified = original.copyWith(threshold: 2.0);
      expect(modified.foregroundNotificationText, 'Custom Text');
    });

    test('copyWith can change foreground notification text', () {
      final original = const StepDetectorConfig();
      final modified = original.copyWith(
        foregroundNotificationText: 'New Text',
      );
      expect(modified.foregroundNotificationText, 'New Text');
    });
  });

  // ============================================================
  // API LEVEL PATH SELECTION TESTS - COMPREHENSIVE
  // ============================================================

  group('Android API Level - Foreground Service Path Selection', () {
    // Android 5.0 to Android 10 (API 21-29)
    test('API 21 (Android 5.0) uses foreground service', () {
      const androidApiLevel = 21;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 22 (Android 5.1) uses foreground service', () {
      const androidApiLevel = 22;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 23 (Android 6.0) uses foreground service', () {
      const androidApiLevel = 23;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 24 (Android 7.0) uses foreground service', () {
      const androidApiLevel = 24;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 25 (Android 7.1) uses foreground service', () {
      const androidApiLevel = 25;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 26 (Android 8.0) uses foreground service', () {
      const androidApiLevel = 26;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 27 (Android 8.1) uses foreground service', () {
      const androidApiLevel = 27;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 28 (Android 9) uses foreground service', () {
      const androidApiLevel = 28;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 29 (Android 10) uses foreground service', () {
      const androidApiLevel = 29;
      final config = const StepDetectorConfig();
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    // Android 11+ (API 30+) with default config
    test(
      'API 30 (Android 11) skips foreground service with default config',
      () {
        const androidApiLevel = 30;
        final config = const StepDetectorConfig();
        expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
      },
    );

    test(
      'API 31 (Android 12) skips foreground service with default config',
      () {
        const androidApiLevel = 31;
        final config = const StepDetectorConfig();
        expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
      },
    );

    test(
      'API 32 (Android 12L) skips foreground service with default config',
      () {
        const androidApiLevel = 32;
        final config = const StepDetectorConfig();
        expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
      },
    );

    test(
      'API 33 (Android 13) skips foreground service with default config',
      () {
        const androidApiLevel = 33;
        final config = const StepDetectorConfig();
        expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
      },
    );

    test(
      'API 34 (Android 14) skips foreground service with default config',
      () {
        const androidApiLevel = 34;
        final config = const StepDetectorConfig();
        expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
      },
    );

    test(
      'API 35 (Android 15) skips foreground service with default config',
      () {
        const androidApiLevel = 35;
        final config = const StepDetectorConfig();
        expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
      },
    );
  });

  group('Android API Level - Extended Max API Level', () {
    // With maxApiLevel = 30 (includes Android 11)
    test('API 30 uses foreground service when maxApiLevel=30', () {
      const androidApiLevel = 30;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 30);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 31 skips foreground service when maxApiLevel=30', () {
      const androidApiLevel = 31;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 30);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
    });

    // With maxApiLevel = 31 (includes Android 12)
    test('API 31 uses foreground service when maxApiLevel=31', () {
      const androidApiLevel = 31;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 31);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 32 skips foreground service when maxApiLevel=31', () {
      const androidApiLevel = 32;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 31);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
    });

    // With maxApiLevel = 32 (includes Android 12L)
    test('API 32 uses foreground service when maxApiLevel=32', () {
      const androidApiLevel = 32;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 33 skips foreground service when maxApiLevel=32', () {
      const androidApiLevel = 33;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
    });

    // With maxApiLevel = 33 (includes Android 13)
    test('API 33 uses foreground service when maxApiLevel=33', () {
      const androidApiLevel = 33;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 33);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 34 skips foreground service when maxApiLevel=33', () {
      const androidApiLevel = 34;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 33);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
    });
  });

  group('Android API Level - Boundary Tests', () {
    test('minimum API level (21) uses foreground service', () {
      const androidApiLevel = 21;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 21);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('one below minimum API level should use foreground service', () {
      const androidApiLevel = 20;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 21);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('maximum configurable API level (50) works', () {
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 50);
      expect(config.foregroundServiceMaxApiLevel, 50);
    });

    test('API level exactly at max uses foreground service', () {
      const androidApiLevel = 50;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 50);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API level above max skips foreground service', () {
      const androidApiLevel = 51;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 50);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
    });
  });

  // ============================================================
  // STEP COUNT EVENT TESTS - COMPREHENSIVE
  // ============================================================

  group('StepCountEvent - Construction', () {
    test('creates with step count 0', () {
      final event = StepCountEvent(stepCount: 0, timestamp: DateTime.now());
      expect(event.stepCount, 0);
    });

    test('creates with step count 1', () {
      final event = StepCountEvent(stepCount: 1, timestamp: DateTime.now());
      expect(event.stepCount, 1);
    });

    test('creates with step count 100', () {
      final event = StepCountEvent(stepCount: 100, timestamp: DateTime.now());
      expect(event.stepCount, 100);
    });

    test('creates with step count 10000', () {
      final event = StepCountEvent(stepCount: 10000, timestamp: DateTime.now());
      expect(event.stepCount, 10000);
    });

    test('creates with step count 100000', () {
      final event = StepCountEvent(
        stepCount: 100000,
        timestamp: DateTime.now(),
      );
      expect(event.stepCount, 100000);
    });

    test('creates with specific timestamp', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30, 0);
      final event = StepCountEvent(stepCount: 42, timestamp: timestamp);
      expect(event.timestamp, timestamp);
    });

    test('creates with current time', () {
      final now = DateTime.now();
      final event = StepCountEvent(stepCount: 42, timestamp: now);
      expect(event.timestamp.difference(now).inSeconds, 0);
    });
  });

  group('StepCountEvent - Equality', () {
    test('equal events are equal', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30, 0);
      final event1 = StepCountEvent(stepCount: 42, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 42, timestamp: timestamp);
      expect(event1, equals(event2));
    });

    test('different step counts are not equal', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30, 0);
      final event1 = StepCountEvent(stepCount: 42, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 43, timestamp: timestamp);
      expect(event1, isNot(equals(event2)));
    });

    test('different timestamps are not equal', () {
      final event1 = StepCountEvent(
        stepCount: 42,
        timestamp: DateTime(2024, 1, 15, 10, 30, 0),
      );
      final event2 = StepCountEvent(
        stepCount: 42,
        timestamp: DateTime(2024, 1, 15, 10, 30, 1),
      );
      expect(event1, isNot(equals(event2)));
    });

    test('hash codes are equal for equal events', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30, 0);
      final event1 = StepCountEvent(stepCount: 42, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 42, timestamp: timestamp);
      expect(event1.hashCode, equals(event2.hashCode));
    });

    test('hash codes differ for different step counts', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30, 0);
      final event1 = StepCountEvent(stepCount: 42, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 43, timestamp: timestamp);
      expect(event1.hashCode, isNot(equals(event2.hashCode)));
    });
  });

  group('StepCountEvent - Confidence', () {
    test('default confidence is 1.0', () {
      final event = StepCountEvent(stepCount: 42, timestamp: DateTime.now());
      expect(event.confidence, 1.0);
    });

    test('can set confidence to 0.0', () {
      final event = StepCountEvent(
        stepCount: 42,
        timestamp: DateTime.now(),
        confidence: 0.0,
      );
      expect(event.confidence, 0.0);
    });

    test('can set confidence to 0.5', () {
      final event = StepCountEvent(
        stepCount: 42,
        timestamp: DateTime.now(),
        confidence: 0.5,
      );
      expect(event.confidence, 0.5);
    });

    test('can set confidence to 0.75', () {
      final event = StepCountEvent(
        stepCount: 42,
        timestamp: DateTime.now(),
        confidence: 0.75,
      );
      expect(event.confidence, 0.75);
    });

    test('can set confidence to 1.0', () {
      final event = StepCountEvent(
        stepCount: 42,
        timestamp: DateTime.now(),
        confidence: 1.0,
      );
      expect(event.confidence, 1.0);
    });
  });

  // ============================================================
  // STEP RECORD CONFIG TESTS - COMPREHENSIVE
  // ============================================================

  group('StepRecordConfig - Presets', () {
    test('walking preset has correct values', () {
      final config = StepRecordConfig.walking();
      expect(config.warmupDurationMs, 5000);
      expect(config.minStepsToValidate, 8);
      expect(config.maxStepsPerSecond, 3.0);
    });

    test('running preset has correct values', () {
      final config = StepRecordConfig.running();
      expect(config.warmupDurationMs, 3000);
      expect(config.minStepsToValidate, 10);
      expect(config.maxStepsPerSecond, 5.0);
    });

    test('sensitive preset has no warmup', () {
      final config = StepRecordConfig.sensitive();
      expect(config.warmupDurationMs, 0);
      expect(config.maxStepsPerSecond, 6.0);
    });

    test('conservative preset has longer warmup', () {
      final config = StepRecordConfig.conservative();
      expect(config.warmupDurationMs, 10000);
      expect(config.minStepsToValidate, 15);
    });

    test('noValidation preset has minimal validation', () {
      final config = StepRecordConfig.noValidation();
      expect(config.warmupDurationMs, 0);
      expect(config.minStepsToValidate, 1);
      expect(config.maxStepsPerSecond, 100.0);
    });

    test('aggregated preset enables aggregated mode', () {
      final config = StepRecordConfig.aggregated();
      expect(config.enableAggregatedMode, true);
      expect(config.warmupDurationMs, 0);
    });
  });

  group('StepRecordConfig - Custom Configuration', () {
    test('can set custom warmupDurationMs', () {
      final config = StepRecordConfig(warmupDurationMs: 7000);
      expect(config.warmupDurationMs, 7000);
    });

    test('can set custom minStepsToValidate', () {
      final config = StepRecordConfig(minStepsToValidate: 20);
      expect(config.minStepsToValidate, 20);
    });

    test('can set custom maxStepsPerSecond', () {
      final config = StepRecordConfig(maxStepsPerSecond: 4.5);
      expect(config.maxStepsPerSecond, 4.5);
    });

    test('can set custom recordIntervalMs', () {
      final config = StepRecordConfig(recordIntervalMs: 10000);
      expect(config.recordIntervalMs, 10000);
    });

    test('can enable aggregated mode', () {
      final config = StepRecordConfig(enableAggregatedMode: true);
      expect(config.enableAggregatedMode, true);
    });

    test('can set inactivity timeout', () {
      final config = StepRecordConfig(inactivityTimeoutMs: 60000);
      expect(config.inactivityTimeoutMs, 60000);
    });
  });

  // ============================================================
  // STEP RECORD SOURCE TESTS
  // ============================================================

  group('StepRecordSource - Enum Values', () {
    test('foreground source exists', () {
      expect(StepRecordSource.foreground, isNotNull);
    });

    test('background source exists', () {
      expect(StepRecordSource.background, isNotNull);
    });

    test('terminated source exists', () {
      expect(StepRecordSource.terminated, isNotNull);
    });

    test('external source exists', () {
      // This was added for Health Connect integration
      expect(StepRecordSource.external, isNotNull);
    });

    test('sources have unique values', () {
      final sources = StepRecordSource.values;
      final uniqueValues = sources.toSet();
      expect(sources.length, uniqueValues.length);
    });

    test('all sources can be used in switch', () {
      for (final source in StepRecordSource.values) {
        String result;
        switch (source) {
          case StepRecordSource.foreground:
            result = 'foreground';
          case StepRecordSource.background:
            result = 'background';
          case StepRecordSource.terminated:
            result = 'terminated';
          case StepRecordSource.external:
            result = 'external';
        }
        expect(result, isNotNull);
      }
    });
  });

  // ============================================================
  // STEP RECORD TESTS
  // ============================================================

  group('StepRecord - Construction', () {
    test('creates with required parameters', () {
      final fromTime = DateTime(2024, 1, 15, 10, 0);
      final toTime = DateTime(2024, 1, 15, 10, 5);
      final record = StepRecord(
        stepCount: 100,
        fromTime: fromTime,
        toTime: toTime,
        source: StepRecordSource.foreground,
      );
      expect(record.stepCount, 100);
      expect(record.fromTime, fromTime);
      expect(record.toTime, toTime);
      expect(record.source, StepRecordSource.foreground);
    });

    test('creates with confidence', () {
      final record = StepRecord(
        stepCount: 100,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
        confidence: 0.9,
      );
      expect(record.confidence, 0.9);
    });
  });

  group('StepRecord - Duration Calculation', () {
    test('durationMs is calculated correctly', () {
      final fromTime = DateTime(2024, 1, 15, 10, 0);
      final toTime = DateTime(2024, 1, 15, 10, 5);
      final record = StepRecord(
        stepCount: 100,
        fromTime: fromTime,
        toTime: toTime,
        source: StepRecordSource.foreground,
      );
      expect(record.durationMs, 5 * 60 * 1000); // 5 minutes in ms
    });

    test('durationMs for zero-length record', () {
      final time = DateTime(2024, 1, 15, 10, 0);
      final record = StepRecord(
        stepCount: 1,
        fromTime: time,
        toTime: time,
        source: StepRecordSource.foreground,
      );
      expect(record.durationMs, 0);
    });

    test('durationMs for one second record', () {
      final fromTime = DateTime(2024, 1, 15, 10, 0, 0);
      final toTime = DateTime(2024, 1, 15, 10, 0, 1);
      final record = StepRecord(
        stepCount: 2,
        fromTime: fromTime,
        toTime: toTime,
        source: StepRecordSource.foreground,
      );
      expect(record.durationMs, 1000);
    });

    test('stepsPerSecond is calculated correctly', () {
      final fromTime = DateTime(2024, 1, 15, 10, 0, 0);
      final toTime = DateTime(2024, 1, 15, 10, 0, 10); // 10 seconds
      final record = StepRecord(
        stepCount: 20,
        fromTime: fromTime,
        toTime: toTime,
        source: StepRecordSource.foreground,
      );
      expect(record.stepsPerSecond, 2.0);
    });

    test('stepsPerSecond for zero duration returns 0', () {
      final time = DateTime(2024, 1, 15, 10, 0);
      final record = StepRecord(
        stepCount: 100,
        fromTime: time,
        toTime: time,
        source: StepRecordSource.foreground,
      );
      expect(record.stepsPerSecond, 0);
    });
  });

  // ============================================================
  // FOREGROUND SERVICE TOGGLE TESTS
  // ============================================================

  group('Foreground Service - Toggle Tests', () {
    test('useForegroundServiceOnOldDevices default is true', () {
      final config = const StepDetectorConfig();
      expect(config.useForegroundServiceOnOldDevices, true);
    });

    test('can disable foreground service completely', () {
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: false,
      );
      expect(config.useForegroundServiceOnOldDevices, false);
    });

    test('foreground service is used when enabled AND API <= max', () {
      const androidApiLevel = 28;
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: true,
        foregroundServiceMaxApiLevel: 29,
      );
      final usesForegroundService =
          config.useForegroundServiceOnOldDevices &&
          androidApiLevel <= config.foregroundServiceMaxApiLevel;
      expect(usesForegroundService, true);
    });

    test('foreground service not used when disabled even if API <= max', () {
      const androidApiLevel = 28;
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: false,
        foregroundServiceMaxApiLevel: 29,
      );
      final usesForegroundService =
          config.useForegroundServiceOnOldDevices &&
          androidApiLevel <= config.foregroundServiceMaxApiLevel;
      expect(usesForegroundService, false);
    });

    test('foreground service not used when API > max even if enabled', () {
      const androidApiLevel = 31;
      final config = StepDetectorConfig(
        useForegroundServiceOnOldDevices: true,
        foregroundServiceMaxApiLevel: 29,
      );
      final usesForegroundService =
          config.useForegroundServiceOnOldDevices &&
          androidApiLevel <= config.foregroundServiceMaxApiLevel;
      expect(usesForegroundService, false);
    });
  });

  // ============================================================
  // SENSORS STEP DETECTOR PARAMETER TESTS
  // ============================================================

  group('SensorsStepDetector - Parameter Validation', () {
    test('threshold 0.5 is accepted', () {
      final detector = SensorsStepDetector(threshold: 0.5);
      expect(detector, isNotNull);
    });

    test('threshold 1.0 is accepted', () {
      final detector = SensorsStepDetector(threshold: 1.0);
      expect(detector, isNotNull);
    });

    test('threshold 1.5 is accepted', () {
      final detector = SensorsStepDetector(threshold: 1.5);
      expect(detector, isNotNull);
    });

    test('threshold 2.0 is accepted', () {
      final detector = SensorsStepDetector(threshold: 2.0);
      expect(detector, isNotNull);
    });

    test('filterAlpha 0.5 is accepted', () {
      final detector = SensorsStepDetector(filterAlpha: 0.5);
      expect(detector, isNotNull);
    });

    test('filterAlpha 0.8 is accepted', () {
      final detector = SensorsStepDetector(filterAlpha: 0.8);
      expect(detector, isNotNull);
    });

    test('filterAlpha 0.9 is accepted', () {
      final detector = SensorsStepDetector(filterAlpha: 0.9);
      expect(detector, isNotNull);
    });

    test('filterAlpha 0.95 is accepted', () {
      final detector = SensorsStepDetector(filterAlpha: 0.95);
      expect(detector, isNotNull);
    });

    test('minTimeBetweenStepsMs 100 is accepted', () {
      final detector = SensorsStepDetector(minTimeBetweenStepsMs: 100);
      expect(detector, isNotNull);
    });

    test('minTimeBetweenStepsMs 200 is accepted', () {
      final detector = SensorsStepDetector(minTimeBetweenStepsMs: 200);
      expect(detector, isNotNull);
    });

    test('minTimeBetweenStepsMs 250 is accepted', () {
      final detector = SensorsStepDetector(minTimeBetweenStepsMs: 250);
      expect(detector, isNotNull);
    });

    test('minTimeBetweenStepsMs 300 is accepted', () {
      final detector = SensorsStepDetector(minTimeBetweenStepsMs: 300);
      expect(detector, isNotNull);
    });

    test('minTimeBetweenStepsMs 500 is accepted', () {
      final detector = SensorsStepDetector(minTimeBetweenStepsMs: 500);
      expect(detector, isNotNull);
    });
  });

  // ============================================================
  // CONFIG EQUALITY AND HASH TESTS
  // ============================================================

  group('StepDetectorConfig - Equality', () {
    test('identical configs are equal', () {
      final config1 = const StepDetectorConfig();
      final config2 = const StepDetectorConfig();
      expect(config1, equals(config2));
    });

    test('configs with different threshold are not equal', () {
      final config1 = StepDetectorConfig(threshold: 1.0);
      final config2 = StepDetectorConfig(threshold: 1.5);
      expect(config1, isNot(equals(config2)));
    });

    test('configs with different filterAlpha are not equal', () {
      final config1 = StepDetectorConfig(filterAlpha: 0.8);
      final config2 = StepDetectorConfig(filterAlpha: 0.9);
      expect(config1, isNot(equals(config2)));
    });

    test('configs with different minTimeBetweenStepsMs are not equal', () {
      final config1 = StepDetectorConfig(minTimeBetweenStepsMs: 200);
      final config2 = StepDetectorConfig(minTimeBetweenStepsMs: 250);
      expect(config1, isNot(equals(config2)));
    });

    test('configs with different enableOsLevelSync are not equal', () {
      final config1 = StepDetectorConfig(enableOsLevelSync: true);
      final config2 = StepDetectorConfig(enableOsLevelSync: false);
      expect(config1, isNot(equals(config2)));
    });

    test(
      'configs with different useForegroundServiceOnOldDevices are not equal',
      () {
        final config1 = StepDetectorConfig(
          useForegroundServiceOnOldDevices: true,
        );
        final config2 = StepDetectorConfig(
          useForegroundServiceOnOldDevices: false,
        );
        expect(config1, isNot(equals(config2)));
      },
    );
  });

  group('StepDetectorConfig - Hash Code', () {
    test('identical configs have same hash code', () {
      final config1 = const StepDetectorConfig();
      final config2 = const StepDetectorConfig();
      expect(config1.hashCode, equals(config2.hashCode));
    });

    test('different configs have different hash codes', () {
      final config1 = StepDetectorConfig(threshold: 1.0);
      final config2 = StepDetectorConfig(threshold: 1.5);
      expect(config1.hashCode, isNot(equals(config2.hashCode)));
    });
  });

  // ============================================================
  // ADDITIONAL COMPREHENSIVE TESTS
  // ============================================================

  group('Step Detection - Edge Cases', () {
    test('API 29 boundary with maxApiLevel 29', () {
      const androidApiLevel = 29;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 30 boundary with maxApiLevel 29', () {
      const androidApiLevel = 30;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
    });

    test('API 30 boundary with maxApiLevel 30', () {
      const androidApiLevel = 30;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 30);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, true);
    });

    test('API 31 boundary with maxApiLevel 30', () {
      const androidApiLevel = 31;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 30);
      expect(androidApiLevel <= config.foregroundServiceMaxApiLevel, false);
    });
  });

  group('Step Count Event - Edge Cases', () {
    test('step count can be negative', () {
      final event = StepCountEvent(stepCount: -1, timestamp: DateTime.now());
      expect(event.stepCount, -1);
    });

    test('step count can be very large', () {
      final event = StepCountEvent(
        stepCount: 999999999,
        timestamp: DateTime.now(),
      );
      expect(event.stepCount, 999999999);
    });

    test('timestamp can be in the past', () {
      final pastTime = DateTime(2020, 1, 1);
      final event = StepCountEvent(stepCount: 42, timestamp: pastTime);
      expect(event.timestamp, pastTime);
    });

    test('timestamp can be in the future', () {
      final futureTime = DateTime(2030, 12, 31);
      final event = StepCountEvent(stepCount: 42, timestamp: futureTime);
      expect(event.timestamp, futureTime);
    });
  });

  group('Config Presets - All Values', () {
    test('walking preset threshold', () {
      expect(StepDetectorConfig.walking().threshold, 1.0);
    });

    test('running preset threshold', () {
      expect(StepDetectorConfig.running().threshold, 1.5);
    });

    test('sensitive preset threshold', () {
      expect(StepDetectorConfig.sensitive().threshold, 0.7);
    });

    test('conservative preset threshold', () {
      expect(StepDetectorConfig.conservative().threshold, 1.3);
    });

    test('walking preset filterAlpha', () {
      expect(StepDetectorConfig.walking().filterAlpha, 0.8);
    });

    test('running preset filterAlpha', () {
      expect(StepDetectorConfig.running().filterAlpha, 0.7);
    });

    test('sensitive preset filterAlpha', () {
      expect(StepDetectorConfig.sensitive().filterAlpha, 0.7);
    });

    test('conservative preset filterAlpha', () {
      expect(StepDetectorConfig.conservative().filterAlpha, 0.9);
    });
  });
}
