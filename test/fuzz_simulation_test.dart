import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Fuzz test that runs 700+ randomized scenarios
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.setTestMode();
  });

  group('Fuzz Simulation Tests (700+ Scenarios)', () {
    const simulationCount = 750; // Requested 700+
    final random = Random(42); // Seed for reproducibility

    for (var i = 0; i < simulationCount; i++) {
      test('Scenario #$i: Randomized Simulation', () async {
        await runRandomizedScenario(i, random);
      });
    }
  });
}

Future<void> runRandomizedScenario(int seed, Random rng) async {
  // 1. Setup clean environment
  await DatabaseHelper.resetInstance();
  final stepCounter = AccurateStepCounter();
  await stepCounter.initializeLogging(debugLogging: false);
  await stepCounter.clearStepLogs();
  await stepCounter.startLogging(config: StepRecordConfig.aggregated());

  // 2. Generate params
  final scenarioType = rng.nextInt(3); // 0: Normal, 1: Midnight, 2: Mixed
  final baseTime = DateTime.now().subtract(Duration(days: rng.nextInt(365)));
  int expectedTotalSteps = 0;

  try {
    if (scenarioType == 0) {
      // === Normal Walk ===
      // Randomly log batches of steps
      final batches = rng.nextInt(10) + 1; // 1 to 10 batches
      var currentTime = baseTime;

      for (var b = 0; b < batches; b++) {
        final steps = rng.nextInt(500) + 10;
        final durationMinutes = rng.nextInt(60) + 5;
        final endTime = currentTime.add(Duration(minutes: durationMinutes));

        // Direct write effectively simulates distributed logging
        await stepCounter.writeStepsToAggregated(
          stepCount: steps,
          fromTime: currentTime,
          toTime: endTime,
          source: StepRecordSource.foreground,
        );
        expectedTotalSteps += steps;
        currentTime = endTime.add(Duration(minutes: rng.nextInt(30))); // Break
      }
    } else if (scenarioType == 1) {
      // === Midnight Crossing ===
      // Start before midnight, end after
      final startHour = 23;
      final startMin = 59 - rng.nextInt(30); // 23:30 to 23:59
      final startTime = DateTime(
        baseTime.year,
        baseTime.month,
        baseTime.day,
        startHour,
        startMin,
      );

      final durationMins = rng.nextInt(120) + 30; // 30 mins to 2.5 hours
      final endTime = startTime.add(Duration(minutes: durationMins));

      final steps = rng.nextInt(2000) + 500;

      await stepCounter.writeStepsToAggregated(
        stepCount: steps,
        fromTime: startTime,
        toTime: endTime,
        source: StepRecordSource.background,
      );
      expectedTotalSteps += steps;
    } else {
      // === Mixed / External Import ===
      final externalSteps = rng.nextInt(5000) + 100;
      await stepCounter.writeStepsToAggregated(
        stepCount: externalSteps,
        fromTime: baseTime.subtract(const Duration(hours: 5)),
        toTime: baseTime.subtract(const Duration(hours: 4)),
        source: StepRecordSource.external,
      );
      expectedTotalSteps += externalSteps;

      // Add actual steps
      final actualSteps = rng.nextInt(1000) + 100;
      await stepCounter.writeStepsToAggregated(
        stepCount: actualSteps,
        fromTime: baseTime,
        toTime: baseTime.add(const Duration(hours: 1)),
        source: StepRecordSource.foreground,
      );
      expectedTotalSteps += actualSteps;
    }

    // 3. Verify Constraints
    final dbTotal = await stepCounter.getTotalSteps();
    expect(
      dbTotal,
      equals(expectedTotalSteps),
      reason: 'Total steps mismatch in scenario #$seed (Type: $scenarioType)',
    );

    final records = await stepCounter.getStepLogs();

    // Check no negative values
    for (var r in records) {
      expect(r.stepCount, greaterThan(0));
      expect(r.toTime.isAfter(r.fromTime), isTrue);
    }
  } finally {
    await stepCounter.dispose();
    await DatabaseHelper.resetInstance();
  }
}
