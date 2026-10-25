import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real background SQLite isolate writes, watches, closes and reopens',
    (tester) async {
      final store = StepRecordStore(useIsolate: true);
      final start = DateTime.now();
      final end = start.add(const Duration(seconds: 1));
      final record = StepRecord(
        stepCount: 7,
        fromTime: start,
        toTime: end,
        source: StepRecordSource.external,
        idempotencyKey: 'isolate-device-${start.microsecondsSinceEpoch}',
      );
      try {
        await store.initialize().timeout(const Duration(seconds: 10));
        await store.insertRecord(record);
        await store.insertRecord(record);
        await store.insertRecord(
          StepRecord(
            stepCount: 3,
            fromTime: start,
            toTime: start,
            source: StepRecordSource.external,
            idempotencyKey: 'isolate-point-${start.microsecondsSinceEpoch}',
          ),
        );
        expect(await store.readTotalSteps(from: start, to: end), 10);
        expect(
          await store.readTotalSteps(
            from: start,
            to: end,
            excludeSource: StepRecordSource.external,
          ),
          0,
        );
        expect(await store.watchTotalSteps(from: start, to: end).first, 10);
        await store.close().timeout(const Duration(seconds: 10));
        expect(store.isInitialized, isFalse);
        await store.initialize().timeout(const Duration(seconds: 10));
        expect(await store.readTotalSteps(from: start, to: end), 10);
      } finally {
        await store.close();
      }
    },
  );
}
