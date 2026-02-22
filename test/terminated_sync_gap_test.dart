import 'package:accurate_step_counter/src/models/terminated_sync_gap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminatedSyncGap', () {
    test('gap key is deterministic', () {
      final start = DateTime(2026, 2, 20, 8, 0, 0);
      final end = DateTime(2026, 2, 20, 9, 0, 0);

      final gap1 = TerminatedSyncGap(
        missedSteps: 1200,
        startTime: start,
        endTime: end,
      );
      final gap2 = TerminatedSyncGap(
        missedSteps: 1200,
        startTime: start,
        endTime: end,
      );

      expect(gap1.gapKey, gap2.gapKey);
      expect(gap1.gapKey, contains('|1200'));
    });

    test('same-day gap produces single segment', () {
      final gap = TerminatedSyncGap(
        missedSteps: 500,
        startTime: DateTime(2026, 2, 20, 8, 0, 0),
        endTime: DateTime(2026, 2, 20, 9, 0, 0),
      );

      final segments = gap.splitIntoDailySegments();

      expect(segments.length, 1);
      expect(segments.first.index, 0);
      expect(segments.first.stepCount, 500);
      expect(segments.first.idempotencyKey, contains('terminated_gap|'));
      expect(segments.first.idempotencyKey, endsWith('|seg:0'));
    });

    test('multi-day gap splits and preserves total steps', () {
      final gap = TerminatedSyncGap(
        missedSteps: 1000,
        startTime: DateTime(2026, 2, 20, 23, 0, 0),
        endTime: DateTime(2026, 2, 21, 1, 0, 0),
      );

      final segments = gap.splitIntoDailySegments();

      expect(segments.length, 2);
      expect(
        segments.fold<int>(0, (sum, s) => sum + s.stepCount),
        gap.missedSteps,
      );
      expect(
        segments.first.idempotencyKey,
        isNot(segments.last.idempotencyKey),
      );
    });

    test('non-positive duration falls back to single segment', () {
      final at = DateTime(2026, 2, 20, 10, 0, 0);
      final gap = TerminatedSyncGap(
        missedSteps: 99,
        startTime: at,
        endTime: at,
      );

      final segments = gap.splitIntoDailySegments();

      expect(segments.length, 1);
      expect(segments.first.stepCount, 99);
      expect(segments.first.fromTime, at);
      expect(segments.first.toTime, at);
    });

    test('zero steps produces no segments', () {
      final gap = TerminatedSyncGap(
        missedSteps: 0,
        startTime: DateTime(2026, 2, 20, 10, 0, 0),
        endTime: DateTime(2026, 2, 20, 11, 0, 0),
      );

      expect(gap.splitIntoDailySegments(), isEmpty);
    });
  });
}
