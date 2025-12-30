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
}
