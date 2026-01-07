/// Configuration for step logging behavior
///
/// Controls warmup validation, logging intervals, and step rate validation.
///
/// Use presets for common scenarios:
/// ```dart
/// await stepCounter.startLogging(config: StepLoggingConfig.walking());
/// await stepCounter.startLogging(config: StepLoggingConfig.running());
/// ```
class StepLoggingConfig {
  /// Minimum time between log entries in milliseconds
  final int logIntervalMs;

  /// Warmup duration before first log in milliseconds
  ///
  /// During warmup, steps are buffered and validated before logging.
  /// Set to 0 to disable warmup validation.
  final int warmupDurationMs;

  /// Minimum steps required during warmup to validate walking
  final int minStepsToValidate;

  /// Maximum allowed step rate (steps per second)
  ///
  /// Steps exceeding this rate are considered noise and discarded.
  final double maxStepsPerSecond;

  /// Creates a custom step logging configuration
  const StepLoggingConfig({
    this.logIntervalMs = 5000,
    this.warmupDurationMs = 0,
    this.minStepsToValidate = 10,
    this.maxStepsPerSecond = 5.0,
  }) : assert(logIntervalMs > 0, 'Log interval must be positive'),
       assert(warmupDurationMs >= 0, 'Warmup duration must be non-negative'),
       assert(minStepsToValidate > 0, 'Min steps must be positive'),
       assert(maxStepsPerSecond > 0, 'Max steps per second must be positive');

  /// Preset for casual walking
  ///
  /// - 5 second log interval
  /// - 5 second warmup
  /// - 8 steps minimum to validate
  /// - Max 3 steps/second (normal walking pace)
  factory StepLoggingConfig.walking() {
    return const StepLoggingConfig(
      logIntervalMs: 5000,
      warmupDurationMs: 5000,
      minStepsToValidate: 8,
      maxStepsPerSecond: 3.0,
    );
  }

  /// Preset for running/jogging
  ///
  /// - 3 second log interval (faster updates)
  /// - 3 second warmup (quicker validation)
  /// - 10 steps minimum to validate
  /// - Max 5 steps/second (running pace)
  factory StepLoggingConfig.running() {
    return const StepLoggingConfig(
      logIntervalMs: 3000,
      warmupDurationMs: 3000,
      minStepsToValidate: 10,
      maxStepsPerSecond: 5.0,
    );
  }

  /// Preset for high sensitivity (may include false positives)
  ///
  /// - 2 second log interval
  /// - No warmup (immediate logging)
  /// - 3 steps minimum
  /// - Max 6 steps/second
  factory StepLoggingConfig.sensitive() {
    return const StepLoggingConfig(
      logIntervalMs: 2000,
      warmupDurationMs: 0,
      minStepsToValidate: 3,
      maxStepsPerSecond: 6.0,
    );
  }

  /// Preset for conservative logging (fewer false positives)
  ///
  /// - 10 second log interval
  /// - 10 second warmup (thorough validation)
  /// - 15 steps minimum to validate
  /// - Max 2.5 steps/second (strict walking only)
  factory StepLoggingConfig.conservative() {
    return const StepLoggingConfig(
      logIntervalMs: 10000,
      warmupDurationMs: 10000,
      minStepsToValidate: 15,
      maxStepsPerSecond: 2.5,
    );
  }

  /// Preset with no validation (raw logging)
  ///
  /// - 5 second log interval
  /// - No warmup
  /// - No step minimum
  /// - Very high max rate (effectively no limit)
  factory StepLoggingConfig.noValidation() {
    return const StepLoggingConfig(
      logIntervalMs: 5000,
      warmupDurationMs: 0,
      minStepsToValidate: 1,
      maxStepsPerSecond: 100.0,
    );
  }

  /// Creates a copy with modified fields
  StepLoggingConfig copyWith({
    int? logIntervalMs,
    int? warmupDurationMs,
    int? minStepsToValidate,
    double? maxStepsPerSecond,
  }) {
    return StepLoggingConfig(
      logIntervalMs: logIntervalMs ?? this.logIntervalMs,
      warmupDurationMs: warmupDurationMs ?? this.warmupDurationMs,
      minStepsToValidate: minStepsToValidate ?? this.minStepsToValidate,
      maxStepsPerSecond: maxStepsPerSecond ?? this.maxStepsPerSecond,
    );
  }

  @override
  String toString() {
    return 'StepLoggingConfig(logInterval: ${logIntervalMs}ms, warmup: ${warmupDurationMs}ms, '
        'minSteps: $minStepsToValidate, maxRate: $maxStepsPerSecond/s)';
  }
}
