import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Initialize sqflite FFI for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Enable test mode for in-memory database
    DatabaseHelper.setTestMode();

    // Mock method channel for native step detector
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
              case 'getAndroidVersion':
                return 33; // Android 13+
              case 'getOsStepCounterValue':
                return 0;
              case 'getSavedOsStepCounterBaseline':
                return -1;
              case 'saveOsStepCounterBaseline':
                return true;
              case 'initialize':
                return true;
              default:
                return null;
            }
          },
        );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('accurate_step_counter'),
          null,
        );
    DatabaseHelper.clearTestMode();
    await DatabaseHelper.resetInstance();
  });

  group('Write Lock - Race Condition Prevention', () {
    late AccurateStepCounter stepCounter;

    setUp(() async {
      // Reset database instance before each test
      await DatabaseHelper.resetInstance();
      stepCounter = AccurateStepCounter();
    });

    tearDown(() async {
      try {
        await stepCounter.clearStepLogs();
      } catch (_) {}
      await stepCounter.dispose();
    });

    test(
      'Concurrent writeStepsToAggregated calls should not create duplicates',
      () async {
        // Initialize the step counter with logging
        await stepCounter.initializeLogging(debugLogging: true);
        await stepCounter.start(
          config: StepDetectorConfig(
            foregroundServiceMaxApiLevel: 32,
            useForegroundServiceOnOldDevices: false,
          ),
        );
        await stepCounter.startLogging(config: StepRecordConfig.aggregated());

        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);

        // Simulate race condition: Multiple concurrent writes with same data
        // This mimics what happens when multiple widgets call readFootSteps simultaneously
        final results = await Future.wait([
          stepCounter.writeStepsToAggregated(
            stepCount: 1000,
            fromTime: todayStart,
            toTime: now,
            source: StepRecordSource.external,
          ),
          // Delayed by 10ms to simulate real-world timing
          Future.delayed(const Duration(milliseconds: 10), () {
            return stepCounter.writeStepsToAggregated(
              stepCount: 1000,
              fromTime: todayStart,
              toTime: now.add(const Duration(seconds: 2)),
              source: StepRecordSource.external,
            );
          }),
          // Delayed by 20ms
          Future.delayed(const Duration(milliseconds: 20), () {
            return stepCounter.writeStepsToAggregated(
              stepCount: 1000,
              fromTime: todayStart,
              toTime: now.add(const Duration(seconds: 3)),
              source: StepRecordSource.external,
            );
          }),
        ]);

        // Count how many writes succeeded
        final successfulWrites = results.where((r) => r == true).length;

        // Only ONE write should succeed, others should be detected as duplicates
        expect(
          successfulWrites,
          1,
          reason:
              'Only one write should succeed due to mutex lock and in-memory duplicate detection',
        );

        // Verify total step count is correct (not duplicated)
        final totalSteps = await stepCounter.getTodayStepCount();
        expect(
          totalSteps,
          1000,
          reason: 'Total steps should be 1000, not 2000 or 3000',
        );
      },
    );

    test(
      'In-memory duplicate check should catch rapid duplicate writes',
      () async {
        // Initialize the step counter with logging
        await stepCounter.initializeLogging(debugLogging: true);
        await stepCounter.start(
          config: StepDetectorConfig(
            foregroundServiceMaxApiLevel: 32,
            useForegroundServiceOnOldDevices: false,
          ),
        );
        await stepCounter.startLogging(config: StepRecordConfig.aggregated());

        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);

        // First write should succeed
        final result1 = await stepCounter.writeStepsToAggregated(
          stepCount: 500,
          fromTime: todayStart,
          toTime: now,
          source: StepRecordSource.external,
        );
        expect(result1, true, reason: 'First write should succeed');

        // Second write with same data within 30 seconds should be skipped
        final result2 = await stepCounter.writeStepsToAggregated(
          stepCount: 500,
          fromTime: todayStart,
          toTime: now.add(const Duration(seconds: 1)),
          source: StepRecordSource.external,
        );
        expect(
          result2,
          false,
          reason: 'Second write should be skipped by in-memory check',
        );

        // Verify total step count
        final totalSteps = await stepCounter.getTodayStepCount();
        expect(totalSteps, 500, reason: 'Only first write should be counted');
      },
    );

    test(
      'Different step counts should NOT be blocked by in-memory check',
      () async {
        // Initialize the step counter with logging
        await stepCounter.initializeLogging(debugLogging: true);
        await stepCounter.start(
          config: StepDetectorConfig(
            foregroundServiceMaxApiLevel: 32,
            useForegroundServiceOnOldDevices: false,
          ),
        );
        await stepCounter.startLogging(config: StepRecordConfig.aggregated());

        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);

        // First write with 500 steps
        final result1 = await stepCounter.writeStepsToAggregated(
          stepCount: 500,
          fromTime: todayStart,
          toTime: now,
          source: StepRecordSource.external,
        );
        expect(result1, true, reason: 'First write should succeed');

        // Second write with DIFFERENT step count should NOT be blocked by in-memory check
        // (though it might be blocked by database duplicate check due to overlapping time)
        final result2 = await stepCounter.writeStepsToAggregated(
          stepCount: 200, // Different step count
          fromTime: todayStart.add(const Duration(hours: 1)),
          toTime: now.add(const Duration(hours: 1)),
          source: StepRecordSource.external,
        );
        expect(
          result2,
          true,
          reason:
              'Different step count should not be blocked by in-memory check',
        );

        // Verify total step count
        final totalSteps = await stepCounter.getTodayStepCount();
        expect(
          totalSteps,
          700,
          reason: 'Both writes should be counted: 500 + 200',
        );
      },
    );
  });
}
