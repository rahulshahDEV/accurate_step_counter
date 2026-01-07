import 'package:hive/hive.dart';

part 'step_log_source.g.dart';

/// Identifies where steps were recorded
///
/// This enum tracks the app state when steps were counted,
/// useful for debugging and analytics.
@HiveType(typeId: 1)
enum StepLogSource {
  /// Steps counted while app is in foreground
  @HiveField(0)
  foreground,

  /// Steps counted while app is backgrounded (via foreground service)
  @HiveField(1)
  background,

  /// Steps synced after app was terminated (OS-level sync)
  @HiveField(2)
  terminated,
}
