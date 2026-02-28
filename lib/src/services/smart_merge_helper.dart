/// Smart merge utility for combining multiple step count sources.
///
/// This pattern is derived from the Meltdown app's proven step counting
/// architecture, where the highest reliable count from sensor, Health Connect,
/// and server is always preferred.
///
/// Example usage:
/// ```dart
/// final merged = SmartMergeHelper.mergeStepCounts(
///   sensorSteps: await stepCounter.currentStepCount,
///   healthConnectSteps: await health.getTotalSteps(today),
///   serverSteps: serverRecoveredSteps,
///   currentDisplayed: displayedCount,
/// );
/// ```
class SmartMergeHelper {
  const SmartMergeHelper._();

  /// Merge multiple step count sources, returning the highest reliable value.
  ///
  /// This is the key reliability pattern: always take the maximum of all
  /// available sources. This handles cases where:
  /// - Sensor missed steps due to OEM battery optimization
  /// - Health Connect was delayed in syncing
  /// - Server has steps from a previous session
  ///
  /// Parameters:
  /// - [sensorSteps] — Steps from the native sensor (TYPE_STEP_COUNTER)
  /// - [healthConnectSteps] — Steps from Health Connect / Apple Health
  /// - [serverSteps] — Steps recovered from the backend server
  /// - [currentDisplayed] — Currently displayed step count (monotonic guarantee)
  ///
  /// Returns the highest step count from all sources.
  ///
  /// Example:
  /// ```dart
  /// // In your cubit/bloc:
  /// final sensorSteps = await NativeStepService.getTodaySteps();
  /// final hcSteps = await health.getTotalStepsInInterval(startOfDay, now);
  /// final serverSteps = lastServerResponse.stepsToday ?? 0;
  ///
  /// final merged = SmartMergeHelper.mergeStepCounts(
  ///   sensorSteps: sensorSteps,
  ///   healthConnectSteps: hcSteps ?? 0,
  ///   serverSteps: serverSteps,
  ///   currentDisplayed: currentStepCount,
  /// );
  ///
  /// updateUI(merged);
  /// ```
  static int mergeStepCounts({
    required int sensorSteps,
    int healthConnectSteps = 0,
    int serverSteps = 0,
    int currentDisplayed = 0,
  }) {
    int merged = sensorSteps > healthConnectSteps
        ? sensorSteps
        : healthConnectSteps;
    if (merged < serverSteps) merged = serverSteps;
    // Never go backwards — monotonic guarantee
    if (merged < currentDisplayed && currentDisplayed > 0) {
      merged = currentDisplayed;
    }
    return merged;
  }

  /// Merge just sensor and Health Connect, without server or display constraints.
  ///
  /// Simplified version for apps that don't have server-side step recovery.
  ///
  /// Example:
  /// ```dart
  /// final merged = SmartMergeHelper.mergeSensorAndHealth(
  ///   sensorSteps: nativeSteps,
  ///   healthConnectSteps: hcSteps,
  /// );
  /// ```
  static int mergeSensorAndHealth({
    required int sensorSteps,
    required int healthConnectSteps,
  }) {
    return sensorSteps > healthConnectSteps ? sensorSteps : healthConnectSteps;
  }
}
