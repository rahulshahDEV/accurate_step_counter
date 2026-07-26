import '../policy/merge_policy.dart';
import '../policy/step_logic.dart';

/// Smart merge utility for combining multiple step count sources.
///
/// Backed by battle-tested [StepLogic] / [MergePolicy] (HC
/// duplication detection, sensor overcount correction, server floor).
///
/// Host apps supply Health Connect / Apple Health / server values — this
/// package does not depend on a Health Connect SDK.
///
/// Example:
/// ```dart
/// final decision = SmartMergeHelper.merge(
///   sensorSteps: sensorToday,
///   healthConnectSteps: hcToday,
///   serverSteps: serverRecovered,
///   currentDisplayed: displayed,
/// );
/// updateUI(decision.displayed);
/// ```
class SmartMergeHelper {
  const SmartMergeHelper._();

  static const MergePolicy _policy = MergePolicy();

  /// Merge multiple step count sources using production-grade policy.
  ///
  /// Prefer this over [mergeStepCounts] when you need floor bookkeeping or
  /// duplication / overcount flags.
  static MergeDecision merge({
    required int sensorSteps,
    int healthConnectSteps = 0,
    int serverSteps = 0,
    int currentDisplayed = 0,
  }) {
    return _policy.mergeToday(
      MergeInputs(
        hcSteps: healthConnectSteps,
        sensorSteps: sensorSteps,
        currentFloor: currentDisplayed,
        serverRecovered: StepLogic.sanitizeServerSteps(serverSteps),
      ),
    );
  }

  /// Merge multiple step count sources, returning the displayed total.
  ///
  /// Uses [StepLogic] (not naive max). HC duplication and sensor
  /// overcount correction apply when [healthConnectSteps] is provided.
  ///
  /// Parameters:
  /// - [sensorSteps] — Steps from the native sensor (TYPE_STEP_COUNTER)
  /// - [healthConnectSteps] — Steps from Health Connect / Apple Health
  /// - [serverSteps] — Steps recovered from the backend server
  /// - [currentDisplayed] — Currently displayed step count (floor)
  static int mergeStepCounts({
    required int sensorSteps,
    int healthConnectSteps = 0,
    int serverSteps = 0,
    int currentDisplayed = 0,
  }) {
    return merge(
      sensorSteps: sensorSteps,
      healthConnectSteps: healthConnectSteps,
      serverSteps: serverSteps,
      currentDisplayed: currentDisplayed,
    ).displayed;
  }

  /// Merge sensor and Health Connect without server / display floor.
  static int mergeSensorAndHealth({
    required int sensorSteps,
    required int healthConnectSteps,
  }) {
    return merge(
      sensorSteps: sensorSteps,
      healthConnectSteps: healthConnectSteps,
    ).displayed;
  }

  /// Merge yesterday totals with HC-first + asymmetric stability lock.
  static int mergeYesterday({
    required int hcYesterday,
    required int sensorYesterday,
    required int currentYesterday,
  }) {
    return _policy.mergeYesterday(
      hcYesterday: hcYesterday,
      sensorYesterday: sensorYesterday,
      currentYesterday: currentYesterday,
    );
  }
}
