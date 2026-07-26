import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/src/policy/hc_smoothing.dart';

void main() {
  group('smoothHcReading — first read / clock anomalies', () {
    test('first read (previousReadMs == 0): accept incoming', () {
      final d = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 500,
        previousHc: 0,
        nowMs: 1747800000000,
        previousReadMs: 0,
      ));
      expect(d.displayed, 500);
      expect(d.updateRecorded, true);
      expect(d.deferred, false);
    });

    test('zero elapsed (same tick): accept (no division-by-zero)', () {
      final d = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 200,
        previousHc: 100,
        nowMs: 1747800000000,
        previousReadMs: 1747800000000,
      ));
      expect(d.displayed, 200);
      expect(d.updateRecorded, true);
    });

    test('clock went backward (negative elapsed): accept defensively', () {
      final d = smoothHcReading(HcSmoothingInputs(
        incomingHc: 300,
        previousHc: 100,
        nowMs: 1747800000000,
        previousReadMs: 1747800001000, // future relative to nowMs
      ));
      expect(d.displayed, 300);
      expect(d.updateRecorded, true);
    });
  });

  group('smoothHcReading — normal walking growth', () {
    test('100 steps in 30s is within 6 steps/s ceiling: accept', () {
      // 30s * 6 + 100 cushion = 280 max delta. We add 100 — well under.
      final d = smoothHcReading(HcSmoothingInputs(
        incomingHc: 1100,
        previousHc: 1000,
        nowMs: 30000,
        previousReadMs: 0 + 1, // make previousReadMs > 0
      ));
      // previousReadMs=1 means elapsedMs=29999
      expect(d.deferred, false);
      expect(d.displayed, 1100);
    });

    test('exact boundary delta is accepted', () {
      // 1s elapsed, max = 6 + 100 = 106. Delta = 106 → accepted.
      final d = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 206,
        previousHc: 100,
        nowMs: 1000,
        previousReadMs: 1, // 999ms elapsed → 1s ceil
      ));
      expect(d.deferred, false);
      expect(d.displayed, 206);
    });
  });

  group('smoothHcReading — sync events deferred', () {
    test('Samsung A07 scenario: 16k step jump in 15s gets deferred', () {
      // Real-world: G-Fit opens, HC suddenly reports 16308 vs previous 192,
      // delta 16116 in 15s = ~1074/s vs max ~7/s.
      final d = smoothHcReading(HcSmoothingInputs(
        incomingHc: 16308,
        previousHc: 192,
        nowMs: 15000 + 1,
        previousReadMs: 1,
      ));
      expect(d.deferred, true);
      expect(d.displayed, 192);
      expect(d.updateRecorded, false);
    });

    test('deferred call does NOT update recorded state', () {
      // If updateRecorded were true here, the next tick would compare
      // against the inflated value and let the new bump through.
      final d = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 5000,
        previousHc: 100,
        nowMs: 1000,
        previousReadMs: 1,
      ));
      expect(d.updateRecorded, false);
      expect(d.deferred, true);
    });

    test('second read after a deferral: if value sticks, delta is small', () {
      // First read deferred (didn't update recorded). Second read comes 15s
      // later with the same big value — delta from previousHc=192 over 30s
      // is 16116 over 30s = ~537/s, still over the cap so still deferred.
      // The smoothing is conservative on purpose — the cubit's
      // mergeSteps hcDuplication detector is the next line of defence.
      final firstRead = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 16308,
        previousHc: 192,
        nowMs: 15000,
        previousReadMs: 1,
      ));
      expect(firstRead.deferred, true);

      // Caller didn't update recorded values; second read 15s later.
      final secondRead = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 16308,
        previousHc: 192,
        nowMs: 30000,
        previousReadMs: 1,
      ));
      expect(secondRead.deferred, true);
      // After many deferrals the persisted-recorded value will eventually
      // become close enough to accept — but the dedup detector will catch
      // duplication first. This test documents that smoothing alone won't
      // unstick a sustained inflation.
    });
  });

  group('smoothHcReading — custom thresholds', () {
    test('tighter maxStepsPerSecond catches smaller jumps', () {
      final d = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 1200,
        previousHc: 1000,
        nowMs: 1000,
        previousReadMs: 1,
        maxStepsPerSecond: 1,
        jitterCushion: 0,
      ));
      // Max delta = 1 * 1s + 0 = 1. Delta = 200. Deferred.
      expect(d.deferred, true);
    });

    test('larger cushion accepts what default would defer', () {
      final d = smoothHcReading(const HcSmoothingInputs(
        incomingHc: 1200,
        previousHc: 1000,
        nowMs: 1000,
        previousReadMs: 1,
        maxStepsPerSecond: 1,
        jitterCushion: 500, // generous
      ));
      // Max delta = 1 + 500 = 501. Delta = 200. Accepted.
      expect(d.deferred, false);
    });
  });
}
