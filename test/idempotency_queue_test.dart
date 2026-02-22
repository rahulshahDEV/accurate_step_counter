import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.setTestMode();
  });

  tearDownAll(() async {
    DatabaseHelper.clearTestMode();
    await DatabaseHelper.resetInstance();
  });

  group('StepRecordStore single-writer and idempotency', () {
    late StepRecordStore store;

    setUp(() async {
      await DatabaseHelper.resetInstance();
      store = StepRecordStore();
      await store.initialize();
      await store.deleteAllRecords();
    });

    tearDown(() async {
      await store.close();
      await DatabaseHelper.resetInstance();
    });

    test('duplicate idempotency key is ignored (concurrent inserts)', () async {
      final now = DateTime(2026, 1, 1, 10, 0);
      final record = StepRecord(
        stepCount: 100,
        fromTime: now.subtract(const Duration(minutes: 10)),
        toTime: now,
        source: StepRecordSource.external,
        idempotencyKey: 'dup-key-1',
      );

      await Future.wait([
        store.insertRecord(record),
        store.insertRecord(record),
      ]);

      final logs = await store.readRecords();
      final total = await store.readTotalSteps();

      expect(logs.length, 1);
      expect(total, 100);
      expect(logs.first.idempotencyKey, 'dup-key-1');
    });

    test('concurrent unique inserts persist all records', () async {
      final base = DateTime(2026, 1, 2, 8, 0);
      final writes = List<Future<void>>.generate(120, (i) {
        final from = base.add(Duration(minutes: i));
        final to = from.add(const Duration(minutes: 1));
        return store.insertRecord(
          StepRecord(
            stepCount: 1,
            fromTime: from,
            toTime: to,
            source: StepRecordSource.foreground,
            idempotencyKey: 'unique-$i',
          ),
        );
      });

      await Future.wait(writes);

      expect(await store.getRecordCount(), 120);
      expect(await store.readTotalSteps(), 120);
    });
  });

  group('AccurateStepCounter deterministic idempotency key', () {
    late AccurateStepCounter stepCounter;

    setUp(() async {
      await DatabaseHelper.resetInstance();
      stepCounter = AccurateStepCounter();
      await stepCounter.initializeLogging();
      await stepCounter.clearStepLogs();
    });

    tearDown(() async {
      await stepCounter.dispose();
      await DatabaseHelper.resetInstance();
    });

    test(
      'insertRecord without key auto-generates deterministic dedupe key',
      () async {
        final from = DateTime(2026, 1, 3, 7, 0);
        final to = DateTime(2026, 1, 3, 7, 15);
        final record = StepRecord(
          stepCount: 250,
          fromTime: from,
          toTime: to,
          source: StepRecordSource.external,
        );

        await stepCounter.insertRecord(record);
        await stepCounter.insertRecord(record);

        final logs = await stepCounter.getStepLogs();
        final total = await stepCounter.getTotalSteps();

        expect(logs.length, 1);
        expect(total, 250);
        expect(logs.first.idempotencyKey, isNotNull);
      },
    );
  });
}
