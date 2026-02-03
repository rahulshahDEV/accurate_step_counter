import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.setTestMode();
  });

  group('Log Retention Tests', () {
    late AccurateStepCounter stepCounter;

    setUp(() async {
      await DatabaseHelper.resetInstance();
      stepCounter = AccurateStepCounter();
      await stepCounter.initializeLogging(debugLogging: false);
    });

    tearDown(() async {
      await stepCounter.dispose();
      await DatabaseHelper.resetInstance();
    });

    test('Old logs are auto-deleted on startup', () async {
      final now = DateTime.now();
      final oldDate = now.subtract(const Duration(days: 40));
      final recentDate = now.subtract(const Duration(days: 5));

      // 1. Insert old record manually
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 1000,
          fromTime: oldDate,
          toTime: oldDate.add(const Duration(minutes: 30)),
          source: StepRecordSource.foreground,
        ),
      );

      // 2. Insert recent record
      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 500,
          fromTime: recentDate,
          toTime: recentDate.add(const Duration(minutes: 30)),
          source: StepRecordSource.foreground,
        ),
      );

      // Verify count before cleanup
      expect(await stepCounter.getTotalSteps(), 1500);

      // 3. Start logging with retention period (default 30 days)
      await stepCounter.startLogging(
        config: StepRecordConfig(retentionPeriod: const Duration(days: 30)),
      );

      // Wait for async cleanup (it uses unawaited)
      await Future.delayed(const Duration(milliseconds: 500));

      // 4. Verify old logs deleted, recent logs kept
      final total = await stepCounter.getTotalSteps();
      expect(total, 500); // 1000 should be gone

      final logs = await stepCounter.getStepLogs();
      expect(logs.length, 1);
      expect(logs.first.stepCount, 500);
      expect(logs.first.fromTime.day, recentDate.day);
    });

    test('Retention disabled keeps all logs', () async {
      final now = DateTime.now();
      final oldDate = now.subtract(const Duration(days: 40));

      await stepCounter.insertRecord(
        StepRecord(
          stepCount: 1000,
          fromTime: oldDate,
          toTime: oldDate.add(const Duration(minutes: 30)),
          source: StepRecordSource.foreground,
        ),
      );

      // Disable retention
      await stepCounter.startLogging(
        config: StepRecordConfig(retentionPeriod: Duration.zero),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      expect(await stepCounter.getTotalSteps(), 1000);
    });
  });
}
