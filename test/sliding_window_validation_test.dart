import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Testable subclass to inject events
class TestableStepCounter extends AccurateStepCounter {
  final StreamController<StepCountEvent> _testController =
      StreamController<StepCountEvent>.broadcast();

  // Override to return our controller's stream instead of internal sensors
  @override
  Stream<StepCountEvent> get stepEventStream => _testController.stream;

  // Helper to inject events
  void emitEvent(int steps, DateTime timestamp) {
    _testController.add(StepCountEvent(stepCount: steps, timestamp: timestamp));
  }

  @override
  Future<void> dispose() async {
    await _testController.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite FFI for testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Enable test mode for in-memory database
    DatabaseHelper.setTestMode();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
  });

  tearDownAll(() async {
    DatabaseHelper.clearTestMode();
    await DatabaseHelper.resetInstance();
  });

  group('Sliding Window Validation Tests', () {
    late TestableStepCounter stepCounter;

    setUp(() async {
      // Reset database instance before each test
      await DatabaseHelper.resetInstance();
      stepCounter = TestableStepCounter();
      // Initialize logging to enable the DB and validation logic
      await stepCounter.initializeLogging(debugLogging: false);

      // Ensure we start with a clean state each test if using same box
      await stepCounter.clearStepLogs();
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test(
      '1. Normal walking (approx 2 steps/sec) should pass validation',
      () async {
        // Start logging with walking config (5s warmup, max 3.0 steps/sec)
        await stepCounter.startLogging(
          config: StepRecordConfig(
            warmupDurationMs: 5000,
            minStepsToValidate: 5,
            maxStepsPerSecond: 5.0,
            enableAggregatedMode: true,
          ),
        );

        final startTime = DateTime.now();
        int currentSteps = 0;

        // Simulate 8 seconds of walking at 2 steps/sec
        // This is "slow" enough to pass the max rate check
        for (int i = 0; i < 16; i++) {
          currentSteps += 1;
          stepCounter.emitEvent(
            currentSteps,
            startTime.add(Duration(milliseconds: i * 500)),
          );
        }

        // Wait slightly for async processing
        await Future.delayed(const Duration(milliseconds: 50));

        // Should have passed validation and logged steps
        final total = await stepCounter.getTotalSteps();
        expect(total, greaterThan(0), reason: 'Walking steps should be logged');
      },
    );

    test(
      '2. Shaking (10 steps/sec) should fail sliding window and NOT log',
      () async {
        await stepCounter.startLogging(
          config: StepRecordConfig(
            warmupDurationMs: 5000,
            minStepsToValidate: 5,
            maxStepsPerSecond: 5.0,
            enableAggregatedMode: true,
          ),
        );

        final startTime = DateTime.now();
        int currentSteps = 0;

        // Simulate 3 seconds of shaking (~10 steps/sec)
        // 30 events, 100ms apart
        for (int i = 0; i < 30; i++) {
          currentSteps += 1;
          stepCounter.emitEvent(
            currentSteps,
            startTime.add(Duration(milliseconds: i * 100)),
          );
        }

        await Future.delayed(const Duration(milliseconds: 50));

        final total = await stepCounter.getTotalSteps();
        expect(total, 0, reason: 'High frequency shake should not be logged');
      },
    );

    test('3. Walk (pass) -> Shake (fail) -> Walk (pass) sequence', () async {
      // This tests that validation resets correctly
      await stepCounter.startLogging(
        config: StepRecordConfig(
          warmupDurationMs: 3000, // Shorter warmup for test speed
          minStepsToValidate: 5,
          maxStepsPerSecond: 5.0,
          enableAggregatedMode: true,
        ),
      );

      // PART 1: WALK
      final startTime = DateTime.now();
      int currentSteps = 0; // Cumulative sensors count

      // Walk 4s (passes warmup)
      for (int i = 0; i < 8; i++) {
        currentSteps += 1;
        stepCounter.emitEvent(
          currentSteps,
          startTime.add(Duration(milliseconds: i * 500)),
        );
      }
      await Future.delayed(const Duration(milliseconds: 50));

      final totalAfterWalk = await stepCounter.getTotalSteps();
      expect(
        totalAfterWalk,
        greaterThan(0),
        reason: 'Initial walk should be logged',
      );

      // PART 2: SHAKE
      // Shake for 3s (should be rejected/skipped)
      for (int i = 0; i < 30; i++) {
        currentSteps += 1;
        // Start after previous walk
        stepCounter.emitEvent(
          currentSteps,
          startTime.add(Duration(seconds: 4, milliseconds: i * 100)),
        );
      }
      await Future.delayed(const Duration(milliseconds: 50));

      var totalAfterShake = await stepCounter.getTotalSteps();
      // Total might increase slightly if the very first step of shake is accepted before rate triggers,
      // but essentially it shouldn't log the bulk of shake steps.
      expect(
        totalAfterShake - totalAfterWalk,
        lessThan(5),
        reason: 'Shake steps should be largely skipped',
      );

      // PART 3: WALK AGAIN
      // Walk again (should resume logging)
      for (int i = 0; i < 10; i++) {
        currentSteps += 1;
        stepCounter.emitEvent(
          currentSteps,
          startTime.add(Duration(seconds: 8, milliseconds: i * 500)),
        );
      }
      await Future.delayed(const Duration(milliseconds: 50));

      final totalFinal = await stepCounter.getTotalSteps();
      expect(
        totalFinal,
        greaterThan(totalAfterShake),
        reason: 'Resumed walking should be logged',
      );
    });

    test('4. STRESS TEST: 300 randomized scenarios', () async {
      int passedCount = 0;
      int rejectedCount = 0;

      // Use a consistent start time base but advance it every iteration
      // so DB records don't conflict (though we clear logs)
      DateTime timeBase = DateTime(2025, 1, 1);

      for (int i = 0; i < 300; i++) {
        // Reset state
        await stepCounter.stopLogging();
        await stepCounter.clearStepLogs();

        // Start fresh
        await stepCounter.startLogging(
          config: StepRecordConfig(
            warmupDurationMs: 3000,
            minStepsToValidate: 5, // Need 5 steps
            maxStepsPerSecond: 5.0,
            enableAggregatedMode: true,
          ),
        );

        final isShake = i % 2 == 0; // Even = Shake, Odd = Walk
        timeBase = timeBase.add(const Duration(hours: 1)); // Shift time

        int currentSteps = 0;

        // Configuration
        final stepDelay = isShake ? 100 : 500; // 100ms (10Hz) vs 500ms (2Hz)
        // If Walk: 2Hz * 10 steps = 5 seconds (> 3s warmup). Should pass.
        // If Shake: 10Hz * 50 steps = 5 seconds. Rate 10 > 5. Should fail.
        final stepsToSimulate = isShake ? 50 : 10;

        for (int s = 0; s < stepsToSimulate; s++) {
          currentSteps += 1;
          stepCounter.emitEvent(
            currentSteps,
            timeBase.add(Duration(milliseconds: s * stepDelay)),
          );
        }

        await Future.delayed(const Duration(milliseconds: 10));

        final total = await stepCounter.getTotalSteps();

        if (isShake) {
          if (total == 0) {
            rejectedCount++;
          } else {
            // Debug info if failure
            print('FAILED Shake #$i: Logged $total steps instead of 0');
          }
          expect(total, 0, reason: 'Iteration $i (Shake): Should have 0 steps');
        } else {
          if (total > 0) {
            passedCount++;
          } else {
            print('FAILED Walk #$i: Logged 0 steps');
          }
          // We expect some steps. Since warmup is 3s, first ~3s steps (buffer) are logged once validated.
          // 10 steps * 0.5s = 5s total.
          // Warmup 3s.
          // 5s > 3s, rate 2 < 5. Should pass.
          expect(
            total,
            greaterThan(0),
            reason: 'Iteration $i (Walk): Should have logged steps',
          );
        }
      }

      print('Stress Test Summary:');
      print('  Walks Passed: $passedCount / 150');
      print('  Shakes Rejected: $rejectedCount / 150');

      expect(passedCount, 150);
      expect(rejectedCount, 150);
    });
  });
}
