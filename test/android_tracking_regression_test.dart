import 'dart:async';

import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/database/database_helper.dart';
import 'package:accurate_step_counter/src/platform/step_counter_platform.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNativePlatform implements StepCounterPlatform {
  final events = StreamController<int>.broadcast(sync: true);
  int today = 0;
  int starts = 0;
  bool permission = true;
  bool running = false;
  int? minuteLimit;
  int? hourLimit;
  Map<String, dynamic>? rotation;

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasNativeStepSensor() async => true;
  @override
  Future<void> configureNativeStepService({
    required int maxStepsPerMinute,
    required int maxStepsPerHour,
  }) async {
    minuteLimit = maxStepsPerMinute;
    hourLimit = maxStepsPerHour;
  }

  @override
  Future<bool> startNativeStepService() async {
    starts++;
    running = true;
    return true;
  }

  @override
  Future<bool> stopNativeStepService() async {
    running = false;
    return true;
  }

  @override
  Future<bool> isNativeStepServiceRunning() async => running;
  @override
  Future<void> resetNativeStepState() async {
    running = false;
    today = 0;
    rotation = null;
  }

  @override
  Future<bool> nativeNeedsCalibration() async => false;
  @override
  Future<void> setNativeInitialOffset(int offset) async => today += offset;
  @override
  Future<int> getNativeTodaySteps() async => today;
  @override
  Future<int> getNativeYesterdaySteps() async => 0;
  @override
  Stream<int> get nativeStepServiceStream => events.stream;
  @override
  Future<Map<String, dynamic>?> consumeLastRotation() async {
    final result = rotation;
    rotation = null;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNativePlatform native;
  late AccurateStepCounterImpl steps;
  late DateTime now;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.setTestMode();
  });

  setUp(() async {
    await DatabaseHelper.resetInstance();
    now = DateTime(2026, 7, 25, 12);
    native = FakeNativePlatform();
    steps = AccurateStepCounterImpl.testing(platform: native, now: () => now);
  });

  tearDown(() async {
    await steps.dispose();
    await native.events.close();
    await DatabaseHelper.resetInstance();
  });

  tearDownAll(DatabaseHelper.clearTestMode);

  Future<void> start() => steps.startTracking(useBackgroundIsolate: false);

  Future<void> emit(int value) async {
    final delivered = steps.stepEventStream.firstWhere(
      (e) => e.stepCount == value,
    );
    native.today = value;
    native.events.add(value);
    await delivered.timeout(const Duration(seconds: 3));
  }

  test(
    'concurrent and repeated startup create one service and observe lifecycle',
    () async {
      await Future.wait([start(), start(), start()]);
      await start();
      expect(native.starts, 1);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(steps.appLifecycleState, AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(steps.appLifecycleState, AppLifecycleState.resumed);
    },
  );

  test('permission denial fails before database or sensor startup', () async {
    native.permission = false;
    await expectLater(start(), throwsStateError);
    expect(native.starts, 0);
    expect(steps.isLoggingInitialized, isFalse);
    expect(steps.isStarted, isFalse);
  });

  test(
    'stop requested during startup waits and leaves tracking stopped',
    () async {
      await Future.wait([start(), steps.stop()]);
      expect(native.starts, 1);
      expect(steps.isStarted, isFalse);
      expect(steps.isLoggingEnabled, isFalse);
    },
  );

  test('repeated startup recovers a service killed outside Dart', () async {
    await start();
    native.running = false;
    await start();
    expect(native.starts, 2);
    expect(steps.isStarted, isTrue);
  });

  test(
    'daily hardware reset uses the explicit stop and clear sequence',
    () async {
      native.today = 40;
      await start();
      // ignore: deprecated_member_use, deprecated_member_use_from_same_package
      expect(steps.reset, throwsUnsupportedError);
      await steps.stop();
      await steps.clearStepLogs();
      await steps.resetNativeStepState();
      await start();
      expect(await steps.getTodayStepCount(), 0);
      now = now.add(const Duration(seconds: 10));
      await emit(3);
      expect(await steps.getTodayStepCount(), 3);
    },
  );

  test('a record beginning at midnight is excluded from yesterday', () async {
    now = DateTime(2026, 7, 26);
    await steps.initializeLogging();
    await steps.insertRecord(
      StepRecord(
        stepCount: 5,
        fromTime: now,
        toTime: now.add(const Duration(seconds: 1)),
        source: StepRecordSource.external,
      ),
    );
    expect(await steps.getYesterdayStepCount(), 0);
  });

  test('an instantaneous midnight record belongs to its new day', () async {
    now = DateTime(2026, 7, 26);
    await steps.initializeLogging();
    await steps.insertRecord(
      StepRecord(
        stepCount: 5,
        fromTime: now,
        toTime: now,
        source: StepRecordSource.external,
      ),
    );
    expect(await steps.getTodayStepCount(), 5);
    expect(await steps.getYesterdayStepCount(), 0);
  });

  test('a historical day range excludes the following midnight', () async {
    now = DateTime(2026, 7, 28, 12);
    await steps.initializeLogging();
    final midnight = DateTime(2026, 7, 26);
    await steps.insertRecord(
      StepRecord(
        stepCount: 5,
        fromTime: midnight.subtract(const Duration(seconds: 1)),
        toTime: midnight,
        source: StepRecordSource.external,
      ),
    );
    await steps.insertRecord(
      StepRecord(
        stepCount: 7,
        fromTime: midnight,
        toTime: midnight.add(const Duration(seconds: 1)),
        source: StepRecordSource.external,
      ),
    );
    expect(
      await steps.getStepsInRange(DateTime(2026, 7, 25), DateTime(2026, 7, 25)),
      5,
    );
  });

  test(
    'running preset configures the native service for running cadence',
    () async {
      await steps.startTracking(
        useBackgroundIsolate: false,
        detectorConfig: StepDetectorConfig.running(),
      );
      expect(native.minuteLimit, 240);
      expect(native.hourLimit, 14400);
    },
  );

  test(
    'first native delta is stored and an import does not duplicate session steps',
    () async {
      native.today = 20;
      await start();
      now = now.add(const Duration(seconds: 10));
      await emit(25);
      expect(await steps.getTotalSteps(), 25);
      expect(steps.aggregatedStepCount, 25);
      await steps.writeStepsToAggregated(
        stepCount: 10,
        fromTime: now.subtract(const Duration(minutes: 5)),
        toTime: now,
      );
      expect(steps.aggregatedStepCount, 35);
      expect(await steps.getTotalSteps(), 35);
      now = now.add(const Duration(seconds: 10));
      await emit(30);
      expect(await steps.getTotalSteps(), 40);
      expect(steps.aggregatedStepCount, 40);
      await steps.stop();
      native.today = 50;
      await start();
      expect(await steps.getTotalSteps(), 60);
      now = now.add(const Duration(seconds: 10));
      await emit(55);
      expect(await steps.getTotalSteps(), 65);
    },
  );

  test(
    'a stored baseline never becomes a synthetic hardware increment',
    () async {
      await steps.initializeLogging();
      await steps.insertRecord(
        StepRecord(
          stepCount: 45000,
          fromTime: now.subtract(const Duration(hours: 2)),
          toTime: now,
          source: StepRecordSource.external,
        ),
      );
      await start();
      now = now.add(const Duration(seconds: 10));
      await emit(3);
      expect(await steps.getTotalSteps(), 45003);
      expect(steps.aggregatedStepCount, 45003);
      expect(steps.currentStepCount, 3);
    },
  );

  test(
    'an empty native total can recover SQLite even after sensor baseline registration',
    () async {
      await steps.initializeLogging();
      await steps.insertRecord(
        StepRecord(
          stepCount: 100,
          fromTime: now.subtract(const Duration(hours: 1)),
          toTime: now,
          source: StepRecordSource.foreground,
        ),
      );
      // nativeNeedsCalibration reports false, as it can once the first zero-delta
      // hardware sample has arrived before Dart completes service startup.
      await steps.insertRecord(
        StepRecord(
          stepCount: 10,
          fromTime: now.subtract(const Duration(minutes: 5)),
          toTime: now,
          source: StepRecordSource.external,
        ),
      );
      await start();
      expect(native.today, 100);
      now = now.add(const Duration(seconds: 10));
      await emit(103);
      expect(await steps.getTotalSteps(), 113);
    },
  );

  test('equal-sized process-death gaps reconcile on every restart', () async {
    for (final total in [100, 200, 300]) {
      native.today = total;
      await start();
      expect(await steps.getTotalSteps(), total);
      await steps.stop();
    }
    expect(native.starts, 3);
  });

  test(
    'midnight resets floors and a subscribed today stream uses the new date',
    () async {
      await start();
      final totals = <int>[];
      final subscription = steps.watchTodaySteps().listen(totals.add);
      now = DateTime(2026, 7, 25, 23, 59, 50);
      await emit(100);
      expect(await steps.getTotalSteps(), 100);
      await steps.writeStepsToAggregated(
        stepCount: 10,
        fromTime: now.subtract(const Duration(minutes: 5)),
        toTime: now,
      );

      now = DateTime(2026, 7, 26, 0, 0, 10);
      native.rotation = {
        'date': '2026-07-26',
        'previousDate': '2026-07-25',
        'previousToday': 150,
      };
      await emit(3);
      expect(await steps.getTodayStepCount(), 3);
      expect(steps.aggregatedStepCount, 3);
      expect(await steps.getYesterdayStepCount(), 160);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(totals.last, 3);
      await subscription.cancel();
    },
  );

  test(
    'a multi-day restore fills the actual old date without inventing yesterday',
    () async {
      now = DateTime(2026, 7, 28, 12);
      native.rotation = {
        'date': '2026-07-28',
        'previousDate': '2026-07-25',
        'previousToday': 80,
      };
      await start();
      expect(await steps.getYesterdayStepCount(), 0);
      expect(
        await steps.getStepsInRange(
          DateTime(2026, 7, 25),
          DateTime(2026, 7, 25),
        ),
        80,
      );
      expect(await steps.getTodayStepCount(), 0);
    },
  );

  test(
    'failed buffered storage remains available for a successful retry',
    () async {
      await start();
      now = now.add(const Duration(seconds: 10));
      await emit(10);
      final db = await DatabaseHelper().database;
      await db.execute('''
      CREATE TRIGGER reject_step_insert BEFORE INSERT ON step_records
      BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    ''');
      await expectLater(
        steps.getTotalSteps(),
        throwsA(isA<DatabaseException>()),
      );
      await db.execute('DROP TRIGGER reject_step_insert');
      expect(await steps.getTotalSteps(), 10);
      expect(await steps.getTotalSteps(), 10);
    },
  );
}
