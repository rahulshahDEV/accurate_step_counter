import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/src/policy/rotation_guard.dart';

void main() {
  const guard = RotationGuard();
  const sixteenHours = 16 * 3600 * 1000;

  // ----- Pure utility scenarios -----

  group('RotationGuard.evaluate — no change', () {
    test('sessionDate == currentDate yields noChange', () {
      final r = guard.evaluate(const RotationInputs(
        currentDate: '2026-05-18',
        sessionDate: '2026-05-18',
        currentWallMs: 0,
        lastRolloverWallMs: 0,
        processUptimeMs: 0,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.noChange);
    });
  });

  group('RotationGuard.evaluate — forward (normal midnight)', () {
    test('cold start (both guards unarmed) accepts forward rotation', () {
      final r = guard.evaluate(const RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: 0, // values irrelevant when guards unarmed
        lastRolloverWallMs: 0,
        processUptimeMs: 0,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.accept);
    });

    test('both guards armed and elapsed >= 16h: accept', () {
      final now = DateTime(2026, 5, 19, 0, 5).millisecondsSinceEpoch;
      final lastRotation = DateTime(2026, 5, 18, 0, 5).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: now,
        lastRolloverWallMs: lastRotation,
        processUptimeMs: 24 * 3600 * 1000,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.accept);
    });

    test('monotonic guard fails (clock-spin within process): reject', () {
      // Wall-clock unarmed, but in-process monotonic shows only 30 min uptime.
      // Attacker spun the date forward without 16h of actual run time.
      final r = guard.evaluate(const RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: 0,
        lastRolloverWallMs: 0,
        processUptimeMs: 30 * 60 * 1000, // 30 min
        lastRolloverUptimeMs: 60 * 1000, // 1 min ago
      ));
      expect(r.verdict, RotationVerdict.reject);
      expect(r.reason, contains('monotonic'));
    });

    test('wall guard fails (reboot + clock-spin): reject', () {
      // Stopwatch was reset (uptime small, lastRolloverUptimeMs = 0) so the
      // monotonic guard alone would let this through — but the persisted
      // wall stamp says we rotated only 30 minutes ago. Wall guard kicks in.
      final nowMs = DateTime(2026, 5, 19, 0, 30).millisecondsSinceEpoch;
      final lastMs = DateTime(2026, 5, 19, 0, 0).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: nowMs,
        lastRolloverWallMs: lastMs,
        processUptimeMs: 1000, // post-reboot, just started
        lastRolloverUptimeMs: 0, // unarmed in-memory guard
      ));
      expect(r.verdict, RotationVerdict.reject);
      expect(r.reason, contains('wall-clock'));
    });

    test('both guards fail: reject with combined reason', () {
      final nowMs = DateTime(2026, 5, 19, 0, 30).millisecondsSinceEpoch;
      final lastMs = DateTime(2026, 5, 19, 0, 0).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: nowMs,
        lastRolloverWallMs: lastMs,
        processUptimeMs: 30 * 60 * 1000,
        lastRolloverUptimeMs: 60 * 1000,
      ));
      expect(r.verdict, RotationVerdict.reject);
      expect(r.reason, contains('both'));
    });

    test('exactly 16h elapsed: accept (boundary)', () {
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: sixteenHours + 1,
        lastRolloverWallMs: 1,
        processUptimeMs: sixteenHours + 1,
        lastRolloverUptimeMs: 1,
      ));
      expect(r.verdict, RotationVerdict.accept);
    });

    test('just under 16h elapsed: reject', () {
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: sixteenHours,
        lastRolloverWallMs: 1,
        processUptimeMs: sixteenHours,
        lastRolloverUptimeMs: 1,
      ));
      expect(r.verdict, RotationVerdict.reject);
    });
  });

  group('RotationGuard.evaluate — backward (TZ shift / clock backward)', () {
    test('cold start: accept (no baseline to fight)', () {
      final r = guard.evaluate(const RotationInputs(
        currentDate: '2026-05-17',
        sessionDate: '2026-05-18',
        currentWallMs: 0,
        lastRolloverWallMs: 0,
        processUptimeMs: 0,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.accept);
    });

    test('backward within guard window: reject', () {
      final nowMs = DateTime(2026, 5, 18, 1, 0).millisecondsSinceEpoch;
      final lastMs = DateTime(2026, 5, 18, 0, 0).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-17',
        sessionDate: '2026-05-18',
        currentWallMs: nowMs,
        lastRolloverWallMs: lastMs,
        processUptimeMs: 3600 * 1000,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.reject);
      expect(r.reason, contains('backward'));
    });

    test('backward after >16h: accept (legit TZ change)', () {
      final nowMs = DateTime(2026, 5, 19, 0, 0).millisecondsSinceEpoch;
      final lastMs = DateTime(2026, 5, 18, 0, 0).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-18',
        sessionDate: '2026-05-19',
        currentWallMs: nowMs,
        lastRolloverWallMs: lastMs,
        processUptimeMs: 24 * 3600 * 1000,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.accept);
    });

    test('wall clock moved backward (negative elapsed): reject', () {
      final nowMs = DateTime(2026, 5, 18, 0, 0).millisecondsSinceEpoch;
      final lastMs = DateTime(2026, 5, 19, 0, 0).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-17',
        sessionDate: '2026-05-18',
        currentWallMs: nowMs,
        lastRolloverWallMs: lastMs,
        processUptimeMs: 3600 * 1000,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.reject);
      expect(r.reason, contains('moved backward'));
    });
  });

  // ----- Real-world attack scenarios -----

  group('RotationGuard.evaluate — clock-spin attack scenarios', () {
    test('attacker spins clock +1 day inside a single session: reject', () {
      // Process up for 5 min, last rotation was 4 min ago, attacker
      // jumped the wall clock 24h forward.
      final originalNow = DateTime(2026, 5, 18, 10, 0).millisecondsSinceEpoch;
      final fakeNow = originalNow + 24 * 3600 * 1000;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: fakeNow,
        lastRolloverWallMs: originalNow,
        processUptimeMs: 5 * 60 * 1000,
        lastRolloverUptimeMs: 60 * 1000,
      ));
      // Monotonic guard catches it: 4 min < 16h
      expect(r.verdict, RotationVerdict.reject);
    });

    test('attacker reboots + spins clock to reset monotonic: still rejected by wall guard', () {
      // After reboot: Stopwatch resets to 0, lastRolloverUptimeMs = 0.
      // But the PERSISTED wall stamp from a previous session is still
      // present and only 30 min ago in wall-clock terms.
      final lastRotationWall =
          DateTime(2026, 5, 18, 12, 0).millisecondsSinceEpoch;
      final postRebootFakeNow =
          DateTime(2026, 5, 18, 12, 30).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: postRebootFakeNow,
        lastRolloverWallMs: lastRotationWall,
        processUptimeMs: 30 * 1000, // post-reboot, 30s up
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.reject);
      expect(r.reason, contains('wall-clock'));
    });

    test('genuine 24h passes between sessions (reboot + next-day open): accept', () {
      // User opened app yesterday at noon, rebooted overnight, opens again
      // at noon today.
      final lastRotation = DateTime(2026, 5, 18, 12, 0).millisecondsSinceEpoch;
      final now = DateTime(2026, 5, 19, 12, 0).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: now,
        lastRolloverWallMs: lastRotation,
        processUptimeMs: 60 * 1000, // fresh process, just opened
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.accept);
    });
  });

  // ----- DST edge case -----

  group('RotationGuard.evaluate — DST boundary', () {
    test('spring-forward 23h day: rotation accepted (>=16h covers it)', () {
      // Wall-clock between two consecutive midnights crossing spring-forward
      // is 23h, not 24h. Still > 16h so the guard accepts.
      final lastRotation = DateTime(2026, 3, 7, 0, 5).millisecondsSinceEpoch;
      final now = lastRotation + 23 * 3600 * 1000;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-03-08',
        sessionDate: '2026-03-07',
        currentWallMs: now,
        lastRolloverWallMs: lastRotation,
        processUptimeMs: 24 * 3600 * 1000,
        lastRolloverUptimeMs: 0,
      ));
      expect(r.verdict, RotationVerdict.accept);
    });
  });

  // ----- Configurable threshold -----

  group('RotationGuard.evaluate — custom threshold', () {
    test('custom 1h threshold accepts after 1h', () {
      final last = DateTime(2026, 5, 18, 10, 0).millisecondsSinceEpoch;
      final now = DateTime(2026, 5, 18, 11, 0).millisecondsSinceEpoch + 1;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: now,
        lastRolloverWallMs: last,
        processUptimeMs: 3600 * 1000 + 1,
        lastRolloverUptimeMs: 0,
        minRotationIntervalMs: 3600 * 1000, // 1h
      ));
      expect(r.verdict, RotationVerdict.accept);
    });

    test('custom 1h threshold rejects under 1h', () {
      final last = DateTime(2026, 5, 18, 10, 0).millisecondsSinceEpoch;
      final now = DateTime(2026, 5, 18, 10, 30).millisecondsSinceEpoch;
      final r = guard.evaluate(RotationInputs(
        currentDate: '2026-05-19',
        sessionDate: '2026-05-18',
        currentWallMs: now,
        lastRolloverWallMs: last,
        processUptimeMs: 30 * 60 * 1000,
        lastRolloverUptimeMs: 60 * 1000,
        minRotationIntervalMs: 3600 * 1000,
      ));
      expect(r.verdict, RotationVerdict.reject);
    });
  });
}
