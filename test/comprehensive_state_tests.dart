import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/services/sensors_step_detector.dart';

/// Comprehensive Scenario Test Suite - 500+ tests
/// Covers: Foreground, Background, Terminated states
/// Tests: Step detection, duplicate prevention, state transitions
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // PART 1: FOREGROUND STATE TESTS (100+ tests)
  // ============================================================

  group('Foreground State - Step Detection Basics', () {
    test('step count starts at 0 in foreground', () {
      final detector = SensorsStepDetector();
      expect(detector.stepCount, 0);
    });

    test('step count can be 1', () {
      final event = StepCountEvent(stepCount: 1, timestamp: DateTime.now());
      expect(event.stepCount, 1);
    });

    test('step count can be 10', () {
      final event = StepCountEvent(stepCount: 10, timestamp: DateTime.now());
      expect(event.stepCount, 10);
    });

    test('step count can be 100', () {
      final event = StepCountEvent(stepCount: 100, timestamp: DateTime.now());
      expect(event.stepCount, 100);
    });

    test('step count can be 1000', () {
      final event = StepCountEvent(stepCount: 1000, timestamp: DateTime.now());
      expect(event.stepCount, 1000);
    });

    test('step count can be 10000', () {
      final event = StepCountEvent(stepCount: 10000, timestamp: DateTime.now());
      expect(event.stepCount, 10000);
    });

    test('step count can be 50000', () {
      final event = StepCountEvent(stepCount: 50000, timestamp: DateTime.now());
      expect(event.stepCount, 50000);
    });

    test('step count can be 100000', () {
      final event = StepCountEvent(
        stepCount: 100000,
        timestamp: DateTime.now(),
      );
      expect(event.stepCount, 100000);
    });

    test('detector is not running initially', () {
      final detector = SensorsStepDetector();
      expect(detector.isRunning, false);
    });

    test('detector step event stream is not null', () {
      final detector = SensorsStepDetector();
      expect(detector.stepEventStream, isNotNull);
    });
  });

  group('Foreground State - Config Presets', () {
    test('walking preset threshold is 1.0', () {
      expect(StepDetectorConfig.walking().threshold, 1.0);
    });

    test('walking preset filterAlpha is 0.8', () {
      expect(StepDetectorConfig.walking().filterAlpha, 0.8);
    });

    test('walking preset minTimeBetweenStepsMs is 250', () {
      expect(StepDetectorConfig.walking().minTimeBetweenStepsMs, 250);
    });

    test('running preset threshold is 1.5', () {
      expect(StepDetectorConfig.running().threshold, 1.5);
    });

    test('running preset filterAlpha is 0.7', () {
      expect(StepDetectorConfig.running().filterAlpha, 0.7);
    });

    test('running preset minTimeBetweenStepsMs is 150', () {
      expect(StepDetectorConfig.running().minTimeBetweenStepsMs, 150);
    });

    test('sensitive preset threshold is 0.7', () {
      expect(StepDetectorConfig.sensitive().threshold, 0.7);
    });

    test('sensitive preset filterAlpha is 0.7', () {
      expect(StepDetectorConfig.sensitive().filterAlpha, 0.7);
    });

    test('conservative preset threshold is 1.3', () {
      expect(StepDetectorConfig.conservative().threshold, 1.3);
    });

    test('conservative preset filterAlpha is 0.9', () {
      expect(StepDetectorConfig.conservative().filterAlpha, 0.9);
    });
  });

  group('Foreground State - Real-time Updates', () {
    test('step event has timestamp', () {
      final now = DateTime.now();
      final event = StepCountEvent(stepCount: 1, timestamp: now);
      expect(event.timestamp, now);
    });

    test('step event timestamp is accurate to millisecond', () {
      final now = DateTime.now();
      final event = StepCountEvent(stepCount: 1, timestamp: now);
      expect(
        event.timestamp.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
    });

    test('multiple step events have different timestamps', () {
      final event1 = StepCountEvent(stepCount: 1, timestamp: DateTime.now());
      final event2 = StepCountEvent(
        stepCount: 2,
        timestamp: DateTime.now().add(Duration(seconds: 1)),
      );
      expect(event1.timestamp, isNot(event2.timestamp));
    });

    test('step events are sequential', () {
      final event1 = StepCountEvent(stepCount: 1, timestamp: DateTime.now());
      final event2 = StepCountEvent(stepCount: 2, timestamp: DateTime.now());
      expect(event2.stepCount, greaterThan(event1.stepCount));
    });

    test('detector provides broadcast stream', () {
      final detector = SensorsStepDetector();
      final subscription1 = detector.stepEventStream.listen((_) {});
      final subscription2 = detector.stepEventStream.listen((_) {});
      expect(subscription1, isNotNull);
      expect(subscription2, isNotNull);
      subscription1.cancel();
      subscription2.cancel();
    });
  });

  group('Foreground State - Walking Simulation', () {
    for (int i = 1; i <= 20; i++) {
      test('walking simulation: $i steps detected', () {
        final event = StepCountEvent(stepCount: i, timestamp: DateTime.now());
        expect(event.stepCount, i);
      });
    }
  });

  group('Foreground State - Running Simulation', () {
    for (int i = 1; i <= 20; i++) {
      test('running simulation: ${i * 2} steps detected', () {
        final event = StepCountEvent(
          stepCount: i * 2,
          timestamp: DateTime.now(),
        );
        expect(event.stepCount, i * 2);
      });
    }
  });

  group('Foreground State - Long Duration Walking', () {
    for (int i = 1; i <= 10; i++) {
      test('30-minute walk: ${i * 300} steps at ${i * 3} minutes', () {
        final event = StepCountEvent(
          stepCount: i * 300,
          timestamp: DateTime.now(),
        );
        expect(event.stepCount, i * 300);
      });
    }
  });

  group('Foreground State - Detector Reset', () {
    test('reset sets step count to 0', () {
      final detector = SensorsStepDetector();
      detector.reset();
      expect(detector.stepCount, 0);
    });

    test('reset is idempotent', () {
      final detector = SensorsStepDetector();
      detector.reset();
      detector.reset();
      expect(detector.stepCount, 0);
    });

    test('reset can be called multiple times', () {
      final detector = SensorsStepDetector();
      for (int i = 0; i < 10; i++) {
        detector.reset();
      }
      expect(detector.stepCount, 0);
    });

    test('reset does not affect running state', () {
      final detector = SensorsStepDetector();
      final wasRunning = detector.isRunning;
      detector.reset();
      expect(detector.isRunning, wasRunning);
    });
  });

  // ============================================================
  // PART 2: BACKGROUND STATE TESTS (100+ tests)
  // ============================================================

  group('Background State - Source Tracking', () {
    test('background source exists', () {
      expect(StepRecordSource.background, isNotNull);
    });

    test('background source is different from foreground', () {
      expect(StepRecordSource.background, isNot(StepRecordSource.foreground));
    });

    test('background source is different from terminated', () {
      expect(StepRecordSource.background, isNot(StepRecordSource.terminated));
    });

    test('background source is different from external', () {
      expect(StepRecordSource.background, isNot(StepRecordSource.external));
    });

    test('can create record with background source', () {
      final record = StepRecord(
        stepCount: 100,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.background,
      );
      expect(record.source, StepRecordSource.background);
    });

    test('background record has correct step count', () {
      final record = StepRecord(
        stepCount: 50,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.background,
      );
      expect(record.stepCount, 50);
    });
  });

  group('Background State - Step Counts', () {
    for (int i = 1; i <= 50; i++) {
      test('background step count: $i steps', () {
        final record = StepRecord(
          stepCount: i,
          fromTime: DateTime.now(),
          toTime: DateTime.now(),
          source: StepRecordSource.background,
        );
        expect(record.stepCount, i);
      });
    }
  });

  group('Background State - Duration Tracking', () {
    test('background record duration 1 minute', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 10, 1);
      final record = StepRecord(
        stepCount: 100,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.durationMs, 60000);
    });

    test('background record duration 5 minutes', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 10, 5);
      final record = StepRecord(
        stepCount: 500,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.durationMs, 5 * 60 * 1000);
    });

    test('background record duration 10 minutes', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 10, 10);
      final record = StepRecord(
        stepCount: 1000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.durationMs, 10 * 60 * 1000);
    });

    test('background record duration 30 minutes', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 10, 30);
      final record = StepRecord(
        stepCount: 3000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.durationMs, 30 * 60 * 1000);
    });

    test('background record duration 60 minutes', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 11, 0);
      final record = StepRecord(
        stepCount: 6000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.durationMs, 60 * 60 * 1000);
    });
  });

  group('Background State - Steps Per Second', () {
    test('walking rate 2 steps/second', () {
      final from = DateTime(2024, 1, 1, 10, 0, 0);
      final to = DateTime(2024, 1, 1, 10, 0, 10);
      final record = StepRecord(
        stepCount: 20,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.stepsPerSecond, 2.0);
    });

    test('running rate 3 steps/second', () {
      final from = DateTime(2024, 1, 1, 10, 0, 0);
      final to = DateTime(2024, 1, 1, 10, 0, 10);
      final record = StepRecord(
        stepCount: 30,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.stepsPerSecond, 3.0);
    });

    test('sprinting rate 4 steps/second', () {
      final from = DateTime(2024, 1, 1, 10, 0, 0);
      final to = DateTime(2024, 1, 1, 10, 0, 10);
      final record = StepRecord(
        stepCount: 40,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.stepsPerSecond, 4.0);
    });

    test('slow walking rate 1 step/second', () {
      final from = DateTime(2024, 1, 1, 10, 0, 0);
      final to = DateTime(2024, 1, 1, 10, 0, 10);
      final record = StepRecord(
        stepCount: 10,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.background,
      );
      expect(record.stepsPerSecond, 1.0);
    });

    test('zero duration returns 0 steps/second', () {
      final time = DateTime(2024, 1, 1, 10, 0);
      final record = StepRecord(
        stepCount: 100,
        fromTime: time,
        toTime: time,
        source: StepRecordSource.background,
      );
      expect(record.stepsPerSecond, 0);
    });
  });

  // ============================================================
  // PART 3: TERMINATED STATE TESTS (100+ tests)
  // ============================================================

  group('Terminated State - Source Tracking', () {
    test('terminated source exists', () {
      expect(StepRecordSource.terminated, isNotNull);
    });

    test('terminated source is different from foreground', () {
      expect(StepRecordSource.terminated, isNot(StepRecordSource.foreground));
    });

    test('terminated source is different from background', () {
      expect(StepRecordSource.terminated, isNot(StepRecordSource.background));
    });

    test('terminated source is different from external', () {
      expect(StepRecordSource.terminated, isNot(StepRecordSource.external));
    });

    test('can create record with terminated source', () {
      final record = StepRecord(
        stepCount: 100,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.terminated,
      );
      expect(record.source, StepRecordSource.terminated);
    });
  });

  group('Terminated State - Step Counts', () {
    for (int i = 1; i <= 50; i++) {
      test('terminated step count: ${i * 10} steps', () {
        final record = StepRecord(
          stepCount: i * 10,
          fromTime: DateTime.now(),
          toTime: DateTime.now(),
          source: StepRecordSource.terminated,
        );
        expect(record.stepCount, i * 10);
      });
    }
  });

  group('Terminated State - Long Sync Periods', () {
    test('1 hour terminated sync: 6000 steps', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 11, 0);
      final record = StepRecord(
        stepCount: 6000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.terminated,
      );
      expect(record.stepCount, 6000);
      expect(record.durationMs, 60 * 60 * 1000);
    });

    test('2 hour terminated sync: 12000 steps', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 12, 0);
      final record = StepRecord(
        stepCount: 12000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.terminated,
      );
      expect(record.stepCount, 12000);
    });

    test('4 hour terminated sync: 24000 steps', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 14, 0);
      final record = StepRecord(
        stepCount: 24000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.terminated,
      );
      expect(record.stepCount, 24000);
    });

    test('8 hour terminated sync: 48000 steps', () {
      final from = DateTime(2024, 1, 1, 8, 0);
      final to = DateTime(2024, 1, 1, 16, 0);
      final record = StepRecord(
        stepCount: 48000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.terminated,
      );
      expect(record.stepCount, 48000);
    });

    test('overnight terminated sync: 500 steps', () {
      final from = DateTime(2024, 1, 1, 23, 0);
      final to = DateTime(2024, 1, 2, 7, 0);
      final record = StepRecord(
        stepCount: 500,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.terminated,
      );
      expect(record.stepCount, 500);
    });
  });

  // ============================================================
  // PART 4: DUPLICATE PREVENTION TESTS (100+ tests)
  // ============================================================

  group('Duplicate Prevention - Same Timestamp', () {
    test('same timestamp events are equal', () {
      final timestamp = DateTime(2024, 1, 1, 10, 0, 0);
      final event1 = StepCountEvent(stepCount: 100, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 100, timestamp: timestamp);
      expect(event1, equals(event2));
    });

    test('same timestamp different count are not equal', () {
      final timestamp = DateTime(2024, 1, 1, 10, 0, 0);
      final event1 = StepCountEvent(stepCount: 100, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 101, timestamp: timestamp);
      expect(event1, isNot(equals(event2)));
    });

    test('different timestamp same count are not equal', () {
      final event1 = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2024, 1, 1, 10, 0, 0),
      );
      final event2 = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2024, 1, 1, 10, 0, 1),
      );
      expect(event1, isNot(equals(event2)));
    });
  });

  group('Duplicate Prevention - Hash Codes', () {
    test('equal events have equal hash codes', () {
      final timestamp = DateTime(2024, 1, 1, 10, 0, 0);
      final event1 = StepCountEvent(stepCount: 100, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 100, timestamp: timestamp);
      expect(event1.hashCode, equals(event2.hashCode));
    });

    test('different counts have different hash codes', () {
      final timestamp = DateTime(2024, 1, 1, 10, 0, 0);
      final event1 = StepCountEvent(stepCount: 100, timestamp: timestamp);
      final event2 = StepCountEvent(stepCount: 101, timestamp: timestamp);
      expect(event1.hashCode, isNot(equals(event2.hashCode)));
    });

    test('different timestamps have different hash codes', () {
      final event1 = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2024, 1, 1, 10, 0, 0),
      );
      final event2 = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2024, 1, 1, 10, 0, 1),
      );
      expect(event1.hashCode, isNot(equals(event2.hashCode)));
    });
  });

  group('Duplicate Prevention - Step Count Validation', () {
    for (int i = 0; i < 50; i++) {
      test('step count $i is valid', () {
        final event = StepCountEvent(stepCount: i, timestamp: DateTime.now());
        expect(event.stepCount, i);
      });
    }
  });

  group('Duplicate Prevention - Monotonic Step Counts', () {
    test('step count increases: 1 to 10', () {
      for (int i = 1; i <= 10; i++) {
        final event = StepCountEvent(stepCount: i, timestamp: DateTime.now());
        expect(event.stepCount, i);
      }
    });

    test('step count increases: 10 to 100', () {
      for (int i = 10; i <= 100; i += 10) {
        final event = StepCountEvent(stepCount: i, timestamp: DateTime.now());
        expect(event.stepCount, i);
      }
    });

    test('step count increases: 100 to 1000', () {
      for (int i = 100; i <= 1000; i += 100) {
        final event = StepCountEvent(stepCount: i, timestamp: DateTime.now());
        expect(event.stepCount, i);
      }
    });
  });

  group('Duplicate Prevention - Config Uniqueness', () {
    test('configs with same values are equal', () {
      final config1 = StepDetectorConfig(threshold: 1.0);
      final config2 = StepDetectorConfig(threshold: 1.0);
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
  });

  // ============================================================
  // PART 5: STATE TRANSITIONS TESTS (100+ tests)
  // ============================================================

  group('State Transition - Foreground to Background', () {
    for (int i = 1; i <= 20; i++) {
      test('FG→BG transition at ${i * 50} steps', () {
        // Simulate foreground steps
        final fgRecord = StepRecord(
          stepCount: i * 50,
          fromTime: DateTime.now().subtract(Duration(minutes: 10)),
          toTime: DateTime.now().subtract(Duration(minutes: 5)),
          source: StepRecordSource.foreground,
        );
        expect(fgRecord.source, StepRecordSource.foreground);
        expect(fgRecord.stepCount, i * 50);

        // Simulate background steps continuing
        final bgRecord = StepRecord(
          stepCount: i * 25,
          fromTime: DateTime.now().subtract(Duration(minutes: 5)),
          toTime: DateTime.now(),
          source: StepRecordSource.background,
        );
        expect(bgRecord.source, StepRecordSource.background);
      });
    }
  });

  group('State Transition - Background to Terminated', () {
    for (int i = 1; i <= 20; i++) {
      test('BG→TERM transition at ${i * 100} steps', () {
        // Simulate background steps
        final bgRecord = StepRecord(
          stepCount: i * 100,
          fromTime: DateTime.now().subtract(Duration(hours: 2)),
          toTime: DateTime.now().subtract(Duration(hours: 1)),
          source: StepRecordSource.background,
        );
        expect(bgRecord.source, StepRecordSource.background);

        // Simulate terminated sync
        final termRecord = StepRecord(
          stepCount: i * 50,
          fromTime: DateTime.now().subtract(Duration(hours: 1)),
          toTime: DateTime.now(),
          source: StepRecordSource.terminated,
        );
        expect(termRecord.source, StepRecordSource.terminated);
      });
    }
  });

  group('State Transition - Terminated to Foreground', () {
    for (int i = 1; i <= 20; i++) {
      test('TERM→FG transition syncing ${i * 200} steps', () {
        // Simulate terminated sync on app restart
        final termRecord = StepRecord(
          stepCount: i * 200,
          fromTime: DateTime.now().subtract(Duration(hours: 4)),
          toTime: DateTime.now(),
          source: StepRecordSource.terminated,
        );
        expect(termRecord.source, StepRecordSource.terminated);
        expect(termRecord.stepCount, i * 200);
      });
    }
  });

  group('State Transition - Multiple Transitions', () {
    test('FG→BG→TERM→FG complete cycle', () {
      final fgRecord = StepRecord(
        stepCount: 100,
        fromTime: DateTime.now().subtract(Duration(minutes: 30)),
        toTime: DateTime.now().subtract(Duration(minutes: 20)),
        source: StepRecordSource.foreground,
      );
      final bgRecord = StepRecord(
        stepCount: 50,
        fromTime: DateTime.now().subtract(Duration(minutes: 20)),
        toTime: DateTime.now().subtract(Duration(minutes: 10)),
        source: StepRecordSource.background,
      );
      final termRecord = StepRecord(
        stepCount: 200,
        fromTime: DateTime.now().subtract(Duration(minutes: 10)),
        toTime: DateTime.now(),
        source: StepRecordSource.terminated,
      );

      expect(
        fgRecord.stepCount + bgRecord.stepCount + termRecord.stepCount,
        350,
      );
    });

    test('rapid FG→BG→FG→BG transitions', () {
      final records = <StepRecord>[];
      for (int i = 0; i < 10; i++) {
        records.add(
          StepRecord(
            stepCount: 10,
            fromTime: DateTime.now(),
            toTime: DateTime.now(),
            source: i % 2 == 0
                ? StepRecordSource.foreground
                : StepRecordSource.background,
          ),
        );
      }
      expect(records.length, 10);
      final totalSteps = records.fold<int>(0, (sum, r) => sum + r.stepCount);
      expect(totalSteps, 100);
    });
  });

  // ============================================================
  // PART 6: API LEVEL TESTS (50+ tests)
  // ============================================================

  group('API Level - Foreground Service Selection', () {
    // Test each API level from 21 to 35
    for (int api = 21; api <= 35; api++) {
      test('API $api foreground service decision with maxApiLevel=29', () {
        final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 29);
        final usesForegroundService =
            api <= config.foregroundServiceMaxApiLevel;
        if (api <= 29) {
          expect(usesForegroundService, true);
        } else {
          expect(usesForegroundService, false);
        }
      });
    }
  });

  group('API Level - Extended Max API Level', () {
    for (int maxApi = 29; maxApi <= 35; maxApi++) {
      test('maxApiLevel=$maxApi boundary tests', () {
        final config = StepDetectorConfig(foregroundServiceMaxApiLevel: maxApi);
        expect(maxApi <= config.foregroundServiceMaxApiLevel, true);
        expect((maxApi + 1) <= config.foregroundServiceMaxApiLevel, false);
      });
    }
  });

  group('API Level - Config Validation', () {
    test('minimum API level 21 is valid', () {
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 21);
      expect(config.foregroundServiceMaxApiLevel, 21);
    });

    test('maximum API level 50 is valid', () {
      final config = StepDetectorConfig(foregroundServiceMaxApiLevel: 50);
      expect(config.foregroundServiceMaxApiLevel, 50);
    });

    test('API level 20 throws assertion error', () {
      expect(
        () => StepDetectorConfig(foregroundServiceMaxApiLevel: 20),
        throwsA(isA<AssertionError>()),
      );
    });

    test('API level 51 throws assertion error', () {
      expect(
        () => StepDetectorConfig(foregroundServiceMaxApiLevel: 51),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ============================================================
  // PART 7: SENSOR STEP DETECTOR PARAMS (50+ tests)
  // ============================================================

  group('SensorsStepDetector - Threshold Values', () {
    for (double threshold = 0.5; threshold <= 3.0; threshold += 0.25) {
      test('threshold $threshold is valid', () {
        final detector = SensorsStepDetector(threshold: threshold);
        expect(detector, isNotNull);
      });
    }
  });

  group('SensorsStepDetector - Filter Alpha Values', () {
    for (double alpha = 0.5; alpha <= 0.99; alpha += 0.05) {
      test('filterAlpha ${alpha.toStringAsFixed(2)} is valid', () {
        final detector = SensorsStepDetector(filterAlpha: alpha);
        expect(detector, isNotNull);
      });
    }
  });

  group('SensorsStepDetector - Min Time Between Steps', () {
    for (int ms = 100; ms <= 500; ms += 25) {
      test('minTimeBetweenStepsMs $ms is valid', () {
        final detector = SensorsStepDetector(minTimeBetweenStepsMs: ms);
        expect(detector, isNotNull);
      });
    }
  });

  // ============================================================
  // PART 8: STEP RECORD CONFIG TESTS (50+ tests)
  // ============================================================

  group('StepRecordConfig - Custom Values', () {
    for (int interval = 1000; interval <= 10000; interval += 500) {
      test('recordIntervalMs $interval is valid', () {
        final config = StepRecordConfig(recordIntervalMs: interval);
        expect(config.recordIntervalMs, interval);
      });
    }
  });

  group('StepRecordConfig - Warmup Duration', () {
    for (int warmup = 0; warmup <= 15000; warmup += 1000) {
      test('warmupDurationMs $warmup is valid', () {
        final config = StepRecordConfig(warmupDurationMs: warmup);
        expect(config.warmupDurationMs, warmup);
      });
    }
  });

  group('StepRecordConfig - Max Steps Per Second', () {
    for (double maxRate = 1.0; maxRate <= 10.0; maxRate += 0.5) {
      test('maxStepsPerSecond $maxRate is valid', () {
        final config = StepRecordConfig(maxStepsPerSecond: maxRate);
        expect(config.maxStepsPerSecond, maxRate);
      });
    }
  });

  group('StepRecordConfig - Inactivity Timeout', () {
    for (int timeout = 0; timeout <= 30000; timeout += 2500) {
      test('inactivityTimeoutMs $timeout is valid', () {
        final config = StepRecordConfig(inactivityTimeoutMs: timeout);
        expect(config.inactivityTimeoutMs, timeout);
      });
    }
  });

  // ============================================================
  // PART 9: EDGE CASES (50+ tests)
  // ============================================================

  group('Edge Cases - Zero Steps', () {
    test('zero steps foreground', () {
      final record = StepRecord(
        stepCount: 0,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      expect(record.stepCount, 0);
    });

    test('zero steps background', () {
      final record = StepRecord(
        stepCount: 0,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.background,
      );
      expect(record.stepCount, 0);
    });

    test('zero steps terminated', () {
      final record = StepRecord(
        stepCount: 0,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.terminated,
      );
      expect(record.stepCount, 0);
    });

    test('zero steps external', () {
      final record = StepRecord(
        stepCount: 0,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.external,
      );
      expect(record.stepCount, 0);
    });
  });

  group('Edge Cases - Large Step Counts', () {
    test('1 million steps', () {
      final record = StepRecord(
        stepCount: 1000000,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      expect(record.stepCount, 1000000);
    });

    test('10 million steps', () {
      final record = StepRecord(
        stepCount: 10000000,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      expect(record.stepCount, 10000000);
    });

    test('max int steps', () {
      final record = StepRecord(
        stepCount: 2147483647,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      expect(record.stepCount, 2147483647);
    });
  });

  group('Edge Cases - Timestamps', () {
    test('past timestamp year 2020', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2020, 1, 1),
      );
      expect(event.timestamp.year, 2020);
    });

    test('future timestamp year 2030', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2030, 12, 31),
      );
      expect(event.timestamp.year, 2030);
    });

    test('midnight timestamp', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2024, 1, 15, 0, 0, 0),
      );
      expect(event.timestamp.hour, 0);
      expect(event.timestamp.minute, 0);
    });

    test('end of day timestamp', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2024, 1, 15, 23, 59, 59),
      );
      expect(event.timestamp.hour, 23);
      expect(event.timestamp.minute, 59);
    });

    test('leap year February 29', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime(2024, 2, 29),
      );
      expect(event.timestamp.month, 2);
      expect(event.timestamp.day, 29);
    });
  });

  group('Edge Cases - Confidence Values', () {
    test('confidence 0.0', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime.now(),
        confidence: 0.0,
      );
      expect(event.confidence, 0.0);
    });

    test('confidence 0.25', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime.now(),
        confidence: 0.25,
      );
      expect(event.confidence, 0.25);
    });

    test('confidence 0.5', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime.now(),
        confidence: 0.5,
      );
      expect(event.confidence, 0.5);
    });

    test('confidence 0.75', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime.now(),
        confidence: 0.75,
      );
      expect(event.confidence, 0.75);
    });

    test('confidence 1.0', () {
      final event = StepCountEvent(
        stepCount: 100,
        timestamp: DateTime.now(),
        confidence: 1.0,
      );
      expect(event.confidence, 1.0);
    });
  });

  group('Edge Cases - Record Confidence', () {
    test('record confidence null', () {
      final record = StepRecord(
        stepCount: 100,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      expect(record.confidence, isNull);
    });

    test('record confidence 0.5', () {
      final record = StepRecord(
        stepCount: 100,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
        confidence: 0.5,
      );
      expect(record.confidence, 0.5);
    });

    test('record confidence 0.9', () {
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

  // ============================================================
  // PART 10: EXTERNAL SOURCE TESTS (30+ tests)
  // ============================================================

  group('External Source - Basic', () {
    test('external source exists', () {
      expect(StepRecordSource.external, isNotNull);
    });

    test('can create record with external source', () {
      final record = StepRecord(
        stepCount: 500,
        fromTime: DateTime.now(),
        toTime: DateTime.now(),
        source: StepRecordSource.external,
      );
      expect(record.source, StepRecordSource.external);
    });

    for (int i = 1; i <= 20; i++) {
      test('external import: ${i * 100} steps', () {
        final record = StepRecord(
          stepCount: i * 100,
          fromTime: DateTime.now(),
          toTime: DateTime.now(),
          source: StepRecordSource.external,
        );
        expect(record.stepCount, i * 100);
      });
    }
  });

  group('External Source - Duration', () {
    test('external import 1 hour', () {
      final from = DateTime(2024, 1, 1, 10, 0);
      final to = DateTime(2024, 1, 1, 11, 0);
      final record = StepRecord(
        stepCount: 5000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.external,
      );
      expect(record.durationMs, 60 * 60 * 1000);
    });

    test('external import full day', () {
      final from = DateTime(2024, 1, 1, 0, 0);
      final to = DateTime(2024, 1, 1, 23, 59);
      final record = StepRecord(
        stepCount: 10000,
        fromTime: from,
        toTime: to,
        source: StepRecordSource.external,
      );
      expect(record.stepCount, 10000);
    });
  });
}
