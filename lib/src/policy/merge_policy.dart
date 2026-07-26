import 'package:accurate_step_counter/src/policy/step_logic.dart';

/// Inputs to a single merge decision.
///
/// Wraps the bare ints the old StepLogic took so the call sites read like
/// English instead of `mergeSteps(0, 0, 0, 0)`.
class MergeInputs {
  /// Latest Health Connect total for the period, AFTER manual-entry filtering
  /// and AFTER per-tick HC smoothing.
  final int hcSteps;
  /// Latest hardware-sensor total for the period.
  final int sensorSteps;
  /// Floor we already displayed to the user. Lets us reject downward jitter.
  final int currentFloor;
  /// Floor recovered from the server on a fresh install / data wipe.
  final int serverRecovered;

  const MergeInputs({
    required this.hcSteps,
    required this.sensorSteps,
    required this.currentFloor,
    required this.serverRecovered,
  });
}

/// Outcome of a merge — the new displayed value plus the bookkeeping floors.
class MergeDecision {
  final int displayed;
  final int newFloor;
  final int newServerRecovered;
  final bool overcountingDetected;
  final bool hcDuplicationDetected;

  const MergeDecision({
    required this.displayed,
    required this.newFloor,
    required this.newServerRecovered,
    required this.overcountingDetected,
    required this.hcDuplicationDetected,
  });
}

/// Pure-Dart merge policy for the step engine. Stateless — every call takes
/// its inputs explicitly so callers can unit-test deterministically.
///
/// Implementation re-uses the existing [StepLogic] primitives so the 105
/// passing unit tests carry over without modification.
class MergePolicy {
  const MergePolicy();

  /// Merge today's HC + sensor + floors into the value to display.
  MergeDecision mergeToday(MergeInputs inputs) {
    final r = StepLogic.mergeSteps(
      hcSteps: inputs.hcSteps,
      sensorSteps: inputs.sensorSteps,
      currentFloor: inputs.currentFloor,
      serverRecovered: inputs.serverRecovered,
    );
    return MergeDecision(
      displayed: r.todaySteps,
      newFloor: r.newFloor,
      newServerRecovered: r.newServerRecovered,
      overcountingDetected: r.overcountingDetected,
      hcDuplicationDetected: r.hcDuplicationDetected,
    );
  }

  /// Merge yesterday's HC + sensor + confirmed-yesterday into a stable value.
  /// HC-first with duplication detection and asymmetric stability lock —
  /// see [StepLogic.mergeYesterday] for the full policy.
  int mergeYesterday({
    required int hcYesterday,
    required int sensorYesterday,
    required int currentYesterday,
  }) =>
      StepLogic.mergeYesterday(
        hcYesterday: hcYesterday,
        sensorYesterday: sensorYesterday,
        currentYesterday: currentYesterday,
      );

  /// Reject server-returned step values that exceed our sanity ceiling or
  /// are negative. Defends against backend bugs that would otherwise inflate
  /// a user's local count by orders of magnitude.
  int sanitizeServerSteps(int value) => StepLogic.sanitizeServerSteps(value);
}
