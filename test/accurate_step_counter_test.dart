import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Set up mock method channel for native step detector
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('accurate_step_counter'),
          (MethodCall methodCall) async {
            switch (methodCall.method) {
              case 'resetNativeStepCount':
                return true;
              case 'stopNativeDetection':
                return true;
              case 'getNativeStepCount':
                return 0;
              case 'isNativeDetectionActive':
                return false;
              case 'isUsingHardwareDetector':
                return false;
              default:
                return null;
            }
          },
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('accurate_step_counter'),
          null,
        );
  });

  group('AccurateStepCounter', () {
    late AccurateStepCounter stepCounter;

    setUp(() {
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      if (stepCounter.isStarted) {
        await stepCounter.stop();
      }
      await stepCounter.dispose();
    });

    test('initial step count should be zero', () {
      expect(stepCounter.currentStepCount, 0);
    });

    test('isStarted should be false initially', () {
      expect(stepCounter.isStarted, false);
    });

    test('reset should set step count to zero', () {
      stepCounter.reset();
      expect(stepCounter.currentStepCount, 0);
    });

    test('currentConfig should be null initially', () {
      expect(stepCounter.currentConfig, isNull);
    });
  });

  group('StepDetectorConfig', () {
    test('default constructor creates valid config', () {
      final config = const StepDetectorConfig();
      expect(config.threshold, 1.0);
      expect(config.filterAlpha, 0.8);
      expect(config.minTimeBetweenStepsMs, 200);
      expect(config.enableOsLevelSync, true);
    });

    test('walking preset has correct values', () {
      final config = StepDetectorConfig.walking();
      expect(config.threshold, 1.0);
      expect(config.filterAlpha, 0.8);
      expect(config.minTimeBetweenStepsMs, 250);
      expect(config.enableOsLevelSync, true);
    });

    test('running preset has correct values', () {
      final config = StepDetectorConfig.running();
      expect(config.threshold, 1.5);
      expect(config.filterAlpha, 0.7);
      expect(config.minTimeBetweenStepsMs, 150);
      expect(config.enableOsLevelSync, true);
    });

    test('running allows faster steps than walking', () {
      final walking = StepDetectorConfig.walking();
      final running = StepDetectorConfig.running();
      expect(
        running.minTimeBetweenStepsMs,
        lessThan(walking.minTimeBetweenStepsMs),
      );
    });

    test('sensitive preset has lower threshold', () {
      final sensitive = StepDetectorConfig.sensitive();
      final normal = const StepDetectorConfig();
      expect(sensitive.threshold, lessThan(normal.threshold));
    });

    test('conservative preset has higher threshold', () {
      final conservative = StepDetectorConfig.conservative();
      final normal = const StepDetectorConfig();
      expect(conservative.threshold, greaterThan(normal.threshold));
    });

    test('copyWith creates modified config', () {
      final original = const StepDetectorConfig();
      final modified = original.copyWith(threshold: 2.0);
      expect(modified.threshold, 2.0);
      expect(modified.filterAlpha, original.filterAlpha);
    });
  });

  group('StepCountEvent', () {
    test('creates event with step count and timestamp', () {
      final now = DateTime.now();
      final event = StepCountEvent(stepCount: 42, timestamp: now);
      expect(event.stepCount, 42);
      expect(event.timestamp, now);
    });

    test('equality works correctly', () {
      final now = DateTime.now();
      final event1 = StepCountEvent(stepCount: 42, timestamp: now);
      final event2 = StepCountEvent(stepCount: 42, timestamp: now);
      final event3 = StepCountEvent(stepCount: 43, timestamp: now);

      expect(event1, equals(event2));
      expect(event1, isNot(equals(event3)));
    });
  });

  // ============================================================
  // ANDROID 11 FOREGROUND SERVICE FIX TESTS (v1.7.8)
  // ============================================================

  group('Android 11 Foreground Service Fix', () {
    test('default foregroundServiceMaxApiLevel is 29 (Android 10)', () {
      final config = const StepDetectorConfig();
      expect(config.foregroundServiceMaxApiLevel, 29);
    });

    test('foregroundServiceMaxApiLevel 32 includes Android 11/12', () {
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);
      expect(config.foregroundServiceMaxApiLevel, 32);
      // Android 11 (API 30) <= 32, so foreground service should be used
      expect(30 <= config.foregroundServiceMaxApiLevel, true);
      // Android 12 (API 31) <= 32, so foreground service should be used
      expect(31 <= config.foregroundServiceMaxApiLevel, true);
      // Android 12L (API 32) <= 32, so foreground service should be used
      expect(32 <= config.foregroundServiceMaxApiLevel, true);
      // Android 13 (API 33) > 32, so TYPE_STEP_COUNTER sync should be used
      expect(33 <= config.foregroundServiceMaxApiLevel, false);
    });

    test('foregroundServiceMaxApiLevel bounds validation', () {
      // Min: API 21 (Android 5.0)
      expect(
        () => StepDetectorConfig(foregroundServiceMaxApiLevel: 20),
        throwsA(isA<AssertionError>()),
      );
      // Max: API 50 (future-proof)
      expect(
        () => StepDetectorConfig(foregroundServiceMaxApiLevel: 51),
        throwsA(isA<AssertionError>()),
      );
      // Valid range
      expect(
        StepDetectorConfig(
          foregroundServiceMaxApiLevel: 21,
        ).foregroundServiceMaxApiLevel,
        21,
      );
      expect(
        StepDetectorConfig(
          foregroundServiceMaxApiLevel: 50,
        ).foregroundServiceMaxApiLevel,
        50,
      );
    });

    test('all presets have consistent foregroundServiceMaxApiLevel', () {
      final presets = [
        const StepDetectorConfig(),
        StepDetectorConfig.walking(),
        StepDetectorConfig.running(),
        StepDetectorConfig.sensitive(),
        StepDetectorConfig.conservative(),
      ];
      for (final preset in presets) {
        expect(
          preset.foregroundServiceMaxApiLevel,
          29,
          reason: 'All presets should have default API level 29',
        );
      }
    });

    test('copyWith preserves foregroundServiceMaxApiLevel', () {
      final original = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);
      final modified = original.copyWith(threshold: 2.0);
      expect(modified.foregroundServiceMaxApiLevel, 32);
    });

    test('copyWith can change foregroundServiceMaxApiLevel', () {
      final original = const StepDetectorConfig();
      final modified = original.copyWith(foregroundServiceMaxApiLevel: 31);
      expect(modified.foregroundServiceMaxApiLevel, 31);
    });

    test('config equality includes foregroundServiceMaxApiLevel', () {
      final config1 = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
      final config2 = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
      final config3 = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
    });

    test('config hashCode includes foregroundServiceMaxApiLevel', () {
      final config1 = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
      final config2 = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);

      expect(config1.hashCode, isNot(equals(config2.hashCode)));
    });
  });

  group('Foreground Service Path Selection', () {
    test('API 30 (Android 11) uses foreground service when maxApiLevel=32', () {
      const androidApiLevel = 30;
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);
      final usesForegroundService =
          androidApiLevel <= config.foregroundServiceMaxApiLevel;
      expect(usesForegroundService, true);
    });

    test(
      'API 30 (Android 11) skips foreground service when maxApiLevel=29',
      () {
        const androidApiLevel = 30;
        final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
        final usesForegroundService =
            androidApiLevel <= config.foregroundServiceMaxApiLevel;
        expect(usesForegroundService, false);
      },
    );

    test('API 33 (Android 13) always skips foreground service', () {
      const androidApiLevel = 33;

      // Even with maxApiLevel=32, Android 13 should not use foreground service
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 32);
      final usesForegroundService =
          androidApiLevel <= config.foregroundServiceMaxApiLevel;
      expect(usesForegroundService, false);
    });

    test(
      'API 29 (Android 10) always uses foreground service with default config',
      () {
        const androidApiLevel = 29;
        final config = const StepDetectorConfig();
        final usesForegroundService =
            androidApiLevel <= config.foregroundServiceMaxApiLevel;
        expect(usesForegroundService, true);
      },
    );
  });
}
