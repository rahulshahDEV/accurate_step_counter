/// Identifies where steps were recorded
///
/// This enum tracks the app state when steps were counted,
/// useful for debugging and analytics.
@Deprecated('Use StepRecordSource instead')
enum StepLogSource {
  /// Steps counted while app is in foreground
  foreground,

  /// Steps counted while app is backgrounded (via foreground service)
  background,

  /// Steps synced after app was terminated (OS-level sync)
  terminated,
}
