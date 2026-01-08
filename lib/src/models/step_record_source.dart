import 'package:hive/hive.dart';

part 'step_record_source.g.dart';

/// Source of the step record
///
/// Indicates whether steps were recorded while the app was in
/// foreground, background, from terminated state sync, or imported
/// from external sources.
@HiveType(typeId: 2)
enum StepRecordSource {
  /// Steps recorded while app was in foreground
  @HiveField(0)
  foreground,

  /// Steps recorded while app was in background
  @HiveField(1)
  background,

  /// Steps synced from terminated state (Android 11+ only)
  @HiveField(2)
  terminated,

  /// Steps imported from external sources
  ///
  /// Use this for data imported from:
  /// - Google Fit
  /// - Apple Health
  /// - Samsung Health
  /// - Fitbit
  /// - Other step tracking apps/devices
  @HiveField(3)
  external,
}

// Backwards compatibility
@Deprecated('Use StepRecordSource instead')
typedef StepLogSource = StepRecordSource;
