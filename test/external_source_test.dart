import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/src/models/step_record.dart';
import 'package:accurate_step_counter/src/models/step_record_source.dart';

void main() {
  group('StepRecordSource.external', () {
    test('external source can be used in StepRecord', () {
      final now = DateTime.now();
      final record = StepRecord(
        stepCount: 500,
        fromTime: now.subtract(const Duration(hours: 1)),
        toTime: now,
        source: StepRecordSource.external,
      );

      expect(record.stepCount, 500);
      expect(record.source, StepRecordSource.external);
    });

    test('all StepRecordSource values are unique', () {
      final sources = StepRecordSource.values;
      expect(sources.length, 4);
      expect(sources.contains(StepRecordSource.foreground), true);
      expect(sources.contains(StepRecordSource.background), true);
      expect(sources.contains(StepRecordSource.terminated), true);
      expect(sources.contains(StepRecordSource.external), true);
    });

    test('StepRecordSource.external has correct enum index', () {
      expect(StepRecordSource.external.index, 3);
    });
  });
}
