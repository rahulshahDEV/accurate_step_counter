import 'package:hive/hive.dart';

part 'step_record_source.g.dart';

/// Source of the step record
///
/// Indicates whether steps were recorded while the app was in
/// foreground, background, or from terminated state sync.
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
}

// Backwards compatibility
@Deprecated('Use StepRecordSource instead')
typedef StepLogSource = StepRecordSource;
