import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Midnight Split Logic Tests', () {
    late AccurateStepCounter stepCounter;

    setUp(() async {
      stepCounter = AccurateStepCounter();
      await stepCounter.initializeLogging(debugLogging: false);
      await stepCounter.clearStepLogs();
      // Must be in aggregated mode for writeStepsToAggregated
      await stepCounter.startLogging(config: StepRecordConfig.aggregated());
    });

    tearDown(() async {
      await stepCounter.dispose();
    });

    test('1. Standard import within same day generates 1 record', () async {
      final now = DateTime.now();
      // Ensure we are well within the day
      final start = DateTime(now.year, now.month, now.day, 10, 0); // 10:00 AM
      final end = DateTime(now.year, now.month, now.day, 12, 0); // 12:00 PM

      await stepCounter.writeStepsToAggregated(
        stepCount: 1000,
        fromTime: start,
        toTime: end,
        source: StepRecordSource.external,
      );

      final logs = await stepCounter.getStepLogs();
      expect(logs.length, 1);
      expect(logs.first.stepCount, 1000);
      expect(logs.first.fromTime, start);
      expect(logs.first.toTime, end);
    });

    test('2. Import crossing midnight splits into 2 records', () async {
      final now = DateTime.now(); // e.g. 2024-05-20

      // 11:00 PM on Day 1
      final start = DateTime(now.year, now.month, now.day, 23, 0);
      // 01:00 AM on Day 2
      final end = start.add(const Duration(hours: 2));

      // Total 2 hours, 120 steps.
      // Should be 60 steps for Day 1 (1 hour) and 60 steps for Day 2 (1 hour).
      // Logic assumes uniform distribution?
      // Let's check logic: Double ratio = segmentDuration / totalDuration.
      // 1 hr / 2 hr = 0.5. 120 * 0.5 = 60.

      await stepCounter.writeStepsToAggregated(
        stepCount: 120,
        fromTime: start,
        toTime: end,
        source: StepRecordSource.external,
      );

      final logs = await stepCounter.getStepLogs();
      // Sort by time
      logs.sort((a, b) => a.fromTime.compareTo(b.fromTime));

      expect(logs.length, 2, reason: 'Should split into 2 records');

      // Record 1: 23:00 to 00:00 (next day)
      // Note: My implementation uses midnight as cutoff.
      // Logic:
      // nextDay = DateTime(y,m,d+1)
      // currentEnd = nextDay
      // Record toTime = currentEnd

      final rec1 = logs[0];
      final rec2 = logs[1];

      print('Rec1: ${rec1.fromTime} -> ${rec1.toTime} (${rec1.stepCount})');
      print('Rec2: ${rec2.fromTime} -> ${rec2.toTime} (${rec2.stepCount})');

      // Verify Record 1
      expect(rec1.stepCount, 60);
      expect(rec1.fromTime, start);
      // toTime should be midnight
      expect(rec1.toTime.hour, 0);
      expect(rec1.toTime.minute, 0);
      expect(
        rec1.toTime.day,
        start.day + 1,
      ); // Midnight next day? Or end of day?
      // Logic used: nextDay = currentDate.add(days: 1) -> 00:00:00 of next day.
      // So toTime is 00:00:00 of next day.

      // Verify Record 2
      expect(rec2.stepCount, 60);
      expect(rec2.fromTime, rec1.toTime); // Contiguous
      expect(rec2.toTime, end);
    });

    test('3. Import crossing multiple days splits correctly', () async {
      final now = DateTime.now();

      // 11:00 PM on Day 1
      final start = DateTime(now.year, now.month, now.day, 23, 0);
      // 01:00 AM on Day 3 (26 hours later)
      // Day 1: 1hr (23-00)
      // Day 2: 24hr (00-00)
      // Day 3: 1hr (00-01)
      // Total 26 hours.
      final end = start.add(const Duration(hours: 26));

      // Steps: 2600 (100 per hour)
      await stepCounter.writeStepsToAggregated(
        stepCount: 2600,
        fromTime: start,
        toTime: end,
        source: StepRecordSource.external,
      );

      final logs = await stepCounter.getStepLogs();
      logs.sort((a, b) => a.fromTime.compareTo(b.fromTime));

      expect(logs.length, 3);

      // Day 1: 100 steps
      expect(logs[0].stepCount, 100);
      expect(logs[0].durationMs, 3600000); // 1 hour

      // Day 2: 2400 steps
      expect(logs[1].stepCount, 2400);
      expect(logs[1].durationMs, 86400000); // 24 hours

      // Day 3: 100 steps
      expect(logs[2].stepCount, 100);
      expect(logs[2].durationMs, 3600000); // 1 hour
    });
  });
}
