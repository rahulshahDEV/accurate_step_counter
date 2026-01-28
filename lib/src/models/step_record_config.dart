/// Configuration for step recording behavior
///
/// Controls warmup validation, recording intervals, step rate validation,
/// and inactivity detection.
///
/// Use presets for common scenarios:
/// ```dart
/// await stepCounter.startRecording(config: StepRecordConfig.walking());
/// await stepCounter.startRecording(config: StepRecordConfig.running());
/// ```
class StepRecordConfig {
  /// Minimum time between record entries in milliseconds
  final int recordIntervalMs;

  /// Warmup duration before first record in milliseconds
  ///
  /// During warmup, steps are buffered and validated before recording.
  /// Set to 0 to disable warmup validation.
  final int warmupDurationMs;

  /// Minimum steps required during warmup to validate walking
  final int minStepsToValidate;

  /// Maximum allowed step rate (steps per second)
  ///
  /// Steps exceeding this rate are considered noise and discarded.
  final double maxStepsPerSecond;

  /// Inactivity timeout in milliseconds
  ///
  /// When set > 0, recording will pause after this duration of no steps.
  /// The current session is logged and a new session starts on next step.
  /// Set to 0 to disable inactivity detection.
  final int inactivityTimeoutMs;

  /// Enable aggregated step counter mode
  ///
  /// When true:
  /// - Steps are written to SQLite on EVERY step detected (not interval-based)
  /// - On app start, loads today's steps from midnight to now
  /// - Provides seamless aggregation like Health Connect
  /// - Use watchAggregatedStepCounter() to get live + stored count
  ///
  /// When false:
  /// - Uses interval-based batch recording (recordIntervalMs)
  /// - Traditional logging behavior
  final bool enableAggregatedMode;

  /// Creates a custom step recording configuration
  const StepRecordConfig({
    this.recordIntervalMs = 5000,
    this.warmupDurationMs = 0,
    this.minStepsToValidate = 10,
    this.maxStepsPerSecond = 5.0,
    this.inactivityTimeoutMs = 0,
    this.enableAggregatedMode = false,
  }) : assert(recordIntervalMs > 0, 'Record interval must be positive'),
       assert(warmupDurationMs >= 0, 'Warmup duration must be non-negative'),
       assert(minStepsToValidate > 0, 'Min steps must be positive'),
       assert(maxStepsPerSecond > 0, 'Max steps per second must be positive'),
       assert(
         inactivityTimeoutMs >= 0,
         'Inactivity timeout must be non-negative',
       );

  /// Preset for casual walking
  ///
  /// - 5 second record interval
  /// - 5 second warmup
  /// - 8 steps minimum to validate
  /// - Max 3 steps/second (normal walking pace)
  /// - 10 second inactivity timeout
  factory StepRecordConfig.walking() {
    return const StepRecordConfig(
      recordIntervalMs: 5000,
      warmupDurationMs: 5000,
      minStepsToValidate: 8,
      maxStepsPerSecond: 3.0,
      inactivityTimeoutMs: 10000,
    );
  }

  /// Preset for running/jogging
  ///
  /// - 3 second record interval (faster updates)
  /// - 3 second warmup (quicker validation)
  /// - 10 steps minimum to validate
  /// - Max 5 steps/second (running pace)
  /// - 8 second inactivity timeout
  factory StepRecordConfig.running() {
    return const StepRecordConfig(
      recordIntervalMs: 3000,
      warmupDurationMs: 3000,
      minStepsToValidate: 10,
      maxStepsPerSecond: 5.0,
      inactivityTimeoutMs: 8000,
    );
  }

  /// Preset for high sensitivity (may include false positives)
  ///
  /// - 2 second record interval
  /// - No warmup (immediate recording)
  /// - 3 steps minimum
  /// - Max 6 steps/second
  /// - No inactivity timeout
  factory StepRecordConfig.sensitive() {
    return const StepRecordConfig(
      recordIntervalMs: 2000,
      warmupDurationMs: 0,
      minStepsToValidate: 3,
      maxStepsPerSecond: 6.0,
      inactivityTimeoutMs: 0,
    );
  }

  /// Preset for conservative recording (fewer false positives)
  ///
  /// - 10 second record interval
  /// - 10 second warmup (thorough validation)
  /// - 15 steps minimum to validate
  /// - Max 2.5 steps/second (strict walking only)
  /// - 15 second inactivity timeout
  factory StepRecordConfig.conservative() {
    return const StepRecordConfig(
      recordIntervalMs: 10000,
      warmupDurationMs: 10000,
      minStepsToValidate: 15,
      maxStepsPerSecond: 2.5,
      inactivityTimeoutMs: 15000,
    );
  }

  /// Preset with no validation (raw recording)
  ///
  /// - 5 second record interval
  /// - No warmup
  /// - No step minimum
  /// - Very high max rate (effectively no limit)
  /// - No inactivity timeout
  factory StepRecordConfig.noValidation() {
    return const StepRecordConfig(
      recordIntervalMs: 5000,
      warmupDurationMs: 0,
      minStepsToValidate: 1,
      maxStepsPerSecond: 100.0,
      inactivityTimeoutMs: 0,
    );
  }

  /// Preset for aggregated mode (Health Connect-like)
  ///
  /// - Continuous recording (every step)
  /// - No warmup (immediate counting)
  /// - 1 step minimum
  /// - Max 5 steps/second
  /// - No inactivity timeout
  /// - Aggregated mode enabled
  factory StepRecordConfig.aggregated() {
    return const StepRecordConfig(
      recordIntervalMs: 1000, // Not used in aggregated mode
      warmupDurationMs: 0, // No warmup by default
      minStepsToValidate: 1,
      maxStepsPerSecond: 5.0,
      inactivityTimeoutMs: 0,
      enableAggregatedMode: true,
    );
  }

  /// Creates a copy with modified fields
  StepRecordConfig copyWith({
    int? recordIntervalMs,
    int? warmupDurationMs,
    int? minStepsToValidate,
    double? maxStepsPerSecond,
    int? inactivityTimeoutMs,
    bool? enableAggregatedMode,
  }) {
    return StepRecordConfig(
      recordIntervalMs: recordIntervalMs ?? this.recordIntervalMs,
      warmupDurationMs: warmupDurationMs ?? this.warmupDurationMs,
      minStepsToValidate: minStepsToValidate ?? this.minStepsToValidate,
      maxStepsPerSecond: maxStepsPerSecond ?? this.maxStepsPerSecond,
      inactivityTimeoutMs: inactivityTimeoutMs ?? this.inactivityTimeoutMs,
      enableAggregatedMode: enableAggregatedMode ?? this.enableAggregatedMode,
    );
  }

  @override
  String toString() {
    return 'StepRecordConfig(interval: ${recordIntervalMs}ms, warmup: ${warmupDurationMs}ms, '
        'minSteps: $minStepsToValidate, maxRate: $maxStepsPerSecond/s, '
        'inactivity: ${inactivityTimeoutMs}ms, aggregated: $enableAggregatedMode)';
  }
}

// Backwards compatibility
@Deprecated('Use StepRecordConfig instead')
typedef StepLoggingConfig = StepRecordConfig;
