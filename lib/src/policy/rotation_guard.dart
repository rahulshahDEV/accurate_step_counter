/// Inputs to a day-rotation decision.
///
/// The engine produces these from cubit state (`current*`, `last*`) and
/// passes them to [RotationGuard.evaluate] which returns a verdict the
/// engine then applies. Pure — no clocks read inside this file.
class RotationInputs {
  final String currentDate;        // today, yyyy-MM-dd
  final String sessionDate;        // session/cubit-believed date
  final int currentWallMs;         // DateTime.now().millisecondsSinceEpoch
  final int lastRolloverWallMs;    // persisted, 0 if never
  final int processUptimeMs;       // Stopwatch.elapsedMilliseconds
  final int lastRolloverUptimeMs;  // in-memory, 0 if no prior rotation this run

  /// Minimum monotonic / wall-clock gap required to accept a rotation.
  /// 16h covers extreme TZ jumps while blocking rapid-fire clock spin.
  final int minRotationIntervalMs;

  const RotationInputs({
    required this.currentDate,
    required this.sessionDate,
    required this.currentWallMs,
    required this.lastRolloverWallMs,
    required this.processUptimeMs,
    required this.lastRolloverUptimeMs,
    this.minRotationIntervalMs = 16 * 3600 * 1000,
  });
}

enum RotationVerdict {
  /// Same calendar day — nothing to do.
  noChange,
  /// Forward day change, allowed (e.g. normal midnight).
  accept,
  /// Suspected time manipulation or a guard tripped — keep the existing
  /// session date.
  reject,
}

/// Pure rotation-decision engine. No clock reads, no IO, fully deterministic
/// given its inputs — easy to test for every edge case (DST, clock spin,
/// year boundary, reboot replay).
class RotationGuard {
  const RotationGuard();

  /// Returns the verdict for a rotation attempt and, for reject paths, a
  /// human-readable reason suitable for logging into diagnostics.
  RotationDecision evaluate(RotationInputs i) {
    if (i.currentDate == i.sessionDate) {
      return const RotationDecision(verdict: RotationVerdict.noChange);
    }

    final isBackward = i.currentDate.compareTo(i.sessionDate) < 0;
    final wallElapsed = i.currentWallMs - i.lastRolloverWallMs;
    final monoElapsed = i.processUptimeMs - i.lastRolloverUptimeMs;
    final wallGuardArmed = i.lastRolloverWallMs > 0;
    final monoGuardArmed = i.lastRolloverUptimeMs > 0;

    if (isBackward) {
      // Backward rotation: only allowed if we have NO baseline yet (fresh
      // install) or the recorded rotation is older than the guard window
      // (genuine timezone fix, not an attack).
      if (!wallGuardArmed && !monoGuardArmed) {
        return const RotationDecision(verdict: RotationVerdict.accept);
      }
      // Negative wallElapsed means the wall clock went backward — block.
      if (wallElapsed < 0) {
        return const RotationDecision(
          verdict: RotationVerdict.reject,
          reason: 'wall-clock moved backward',
        );
      }
      if (wallElapsed < i.minRotationIntervalMs) {
        return RotationDecision(
          verdict: RotationVerdict.reject,
          reason: 'backward jump within guard window (${wallElapsed ~/ 1000}s)',
        );
      }
      return const RotationDecision(verdict: RotationVerdict.accept);
    }

    // Forward rotation: apply BOTH guards. The wall guard alone defeats
    // the reboot+clock-spin attack (Stopwatch resets on reboot). The
    // monotonic guard alone catches in-process clock spins. We require
    // each armed guard to clear its window.
    final monoFails =
        monoGuardArmed && monoElapsed < i.minRotationIntervalMs;
    final wallFails = wallGuardArmed &&
        wallElapsed >= 0 &&
        wallElapsed < i.minRotationIntervalMs;
    if (monoFails || wallFails) {
      return RotationDecision(
        verdict: RotationVerdict.reject,
        reason: monoFails && wallFails
            ? 'both rotation guards failed'
            : (monoFails ? 'monotonic guard' : 'wall-clock guard'),
        monoElapsedMs: monoElapsed,
        wallElapsedMs: wallElapsed,
      );
    }
    return const RotationDecision(verdict: RotationVerdict.accept);
  }
}

class RotationDecision {
  final RotationVerdict verdict;
  final String? reason;
  final int? monoElapsedMs;
  final int? wallElapsedMs;

  const RotationDecision({
    required this.verdict,
    this.reason,
    this.monoElapsedMs,
    this.wallElapsedMs,
  });
}
