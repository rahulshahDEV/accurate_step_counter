/// Source of the step record
///
/// Indicates whether steps were recorded while the app was in
/// foreground, background, from terminated state sync, or imported
/// from external sources.
enum StepRecordSource {
  /// Steps recorded while app was in foreground
  foreground,

  /// Steps recorded while app was in background
  background,

  /// Steps synced from terminated state (Android 11+ only)
  terminated,

  /// Steps imported from external sources
  ///
  /// Use this for data imported from:
  /// - Google Fit
  /// - Apple Health
  /// - Samsung Health
  /// - Fitbit
  /// - Other step tracking apps/devices
  external,
}

// Backwards compatibility
@Deprecated('Use StepRecordSource instead')
typedef StepLogSource = StepRecordSource;
