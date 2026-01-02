/// Configuration for the step detection algorithm
///
/// This class allows you to tune the sensitivity and behavior of the step detector
/// to match different use cases (walking vs running, pocket vs hand-held, etc.)
class StepDetectorConfig {
  /// Movement threshold for detecting steps
  ///
  /// Higher values = less sensitive (fewer false positives)
  /// Lower values = more sensitive (may count non-steps)
  ///
  /// Recommended range: 0.5 - 2.0
  /// - Walking: 1.0
  /// - Running: 1.5
  /// - Very sensitive: 0.7
  final double threshold;

  /// Low-pass filter coefficient (alpha)
  ///
  /// Controls how much smoothing is applied to accelerometer data
  /// Higher values = more smoothing, slower response
  /// Lower values = less smoothing, faster response
  ///
  /// Range: 0.0 - 1.0
  /// - Heavy smoothing: 0.9
  /// - Default: 0.8
  /// - Light smoothing: 0.6
  final double filterAlpha;

  /// Minimum time between steps in milliseconds
  ///
  /// Prevents double-counting from sensor noise
  /// Lower values allow faster step detection (running)
  /// Higher values prevent false positives
  ///
  /// Recommended range: 150 - 400 milliseconds
  /// - Running: 150-200ms
  /// - Walking: 200-250ms
  /// - Conservative: 300ms
  final int minTimeBetweenStepsMs;

  /// Whether to use OS-level step counter for validation (Android only)
  ///
  /// When enabled, the plugin will:
  /// - Sync with Android TYPE_STEP_COUNTER sensor
  /// - Recover missed steps after app termination
  /// - Validate step counts on app restart
  ///
  /// Requires ACTIVITY_RECOGNITION permission on Android
  final bool enableOsLevelSync;

  /// Whether to use foreground service on older Android versions
  ///
  /// On older Android versions, the terminated state sync doesn't work reliably.
  /// When this is enabled, a foreground service with persistent notification
  /// will be used to keep counting steps even when app is minimized.
  ///
  /// The Android version threshold is controlled by [foregroundServiceMaxApiLevel].
  /// Defaults to true for reliable step counting on older devices.
  final bool useForegroundServiceOnOldDevices;

  /// The maximum Android API level for which foreground service should be used
  ///
  /// When [useForegroundServiceOnOldDevices] is true and the device's API level
  /// is less than or equal to this value, the foreground service will be used
  /// instead of the normal TYPE_STEP_COUNTER sensor flow.
  ///
  /// Common API levels:
  /// - 29 = Android 10 (default)
  /// - 30 = Android 11
  /// - 31 = Android 12
  /// - 32 = Android 12L
  /// - 33 = Android 13
  /// - 34 = Android 14
  ///
  /// Defaults to 29 (Android 10).
  final int foregroundServiceMaxApiLevel;

  /// Custom notification title when using foreground service
  ///
  /// Only used when [useForegroundServiceOnOldDevices] is true
  /// and running on Android with API level ≤ [foregroundServiceMaxApiLevel].
  final String foregroundNotificationTitle;

  /// Custom notification text when using foreground service
  ///
  /// Only used when [useForegroundServiceOnOldDevices] is true
  /// and running on Android with API level ≤ [foregroundServiceMaxApiLevel].
  final String foregroundNotificationText;

  /// Creates a new step detector configuration
  ///
  /// Example:
  /// ```dart
  /// // Default configuration (balanced)
  /// StepDetectorConfig()
  ///
  /// // High sensitivity for running
  /// StepDetectorConfig(
  ///   threshold: 1.5,
  ///   minTimeBetweenStepsMs: 150,
  /// )
  ///
  /// // Conservative for reducing false positives
  /// StepDetectorConfig(
  ///   threshold: 1.2,
  ///   filterAlpha: 0.9,
  ///   minTimeBetweenStepsMs: 300,
  /// )
  /// ```
  const StepDetectorConfig({
    this.threshold = 1.0,
    this.filterAlpha = 0.8,
    this.minTimeBetweenStepsMs = 200,
    this.enableOsLevelSync = true,
    this.useForegroundServiceOnOldDevices = true,
    this.foregroundServiceMaxApiLevel = 29,
    this.foregroundNotificationTitle = 'Step Counter',
    this.foregroundNotificationText = 'Tracking your steps...',
  }) : assert(threshold > 0, 'Threshold must be positive'),
       assert(
         foregroundServiceMaxApiLevel >= 21 &&
             foregroundServiceMaxApiLevel <= 50,
         'foregroundServiceMaxApiLevel must be between 21 and 50',
       ),
       assert(
         filterAlpha >= 0.0 && filterAlpha <= 1.0,
         'Filter alpha must be between 0.0 and 1.0',
       ),
       assert(
         minTimeBetweenStepsMs > 0,
         'Minimum time between steps must be positive',
       );

  /// Creates a preset configuration optimized for walking
  factory StepDetectorConfig.walking() {
    return const StepDetectorConfig(
      threshold: 1.0,
      filterAlpha: 0.8,
      minTimeBetweenStepsMs: 250,
      enableOsLevelSync: true,
      useForegroundServiceOnOldDevices: true,
    );
  }

  /// Creates a preset configuration optimized for running
  factory StepDetectorConfig.running() {
    return const StepDetectorConfig(
      threshold: 1.5,
      filterAlpha: 0.7,
      minTimeBetweenStepsMs: 150,
      enableOsLevelSync: true,
      useForegroundServiceOnOldDevices: true,
    );
  }

  /// Creates a preset configuration with high sensitivity
  ///
  /// Warning: May produce more false positives
  factory StepDetectorConfig.sensitive() {
    return const StepDetectorConfig(
      threshold: 0.7,
      filterAlpha: 0.7,
      minTimeBetweenStepsMs: 180,
      enableOsLevelSync: true,
      useForegroundServiceOnOldDevices: true,
    );
  }

  /// Creates a preset configuration with conservative settings
  ///
  /// Reduces false positives but may miss some steps
  factory StepDetectorConfig.conservative() {
    return const StepDetectorConfig(
      threshold: 1.3,
      filterAlpha: 0.9,
      minTimeBetweenStepsMs: 300,
      enableOsLevelSync: true,
      useForegroundServiceOnOldDevices: true,
    );
  }

  /// Creates a copy of this configuration with the given fields replaced
  StepDetectorConfig copyWith({
    double? threshold,
    double? filterAlpha,
    int? minTimeBetweenStepsMs,
    bool? enableOsLevelSync,
    bool? useForegroundServiceOnOldDevices,
    int? foregroundServiceMaxApiLevel,
    String? foregroundNotificationTitle,
    String? foregroundNotificationText,
  }) {
    return StepDetectorConfig(
      threshold: threshold ?? this.threshold,
      filterAlpha: filterAlpha ?? this.filterAlpha,
      minTimeBetweenStepsMs:
          minTimeBetweenStepsMs ?? this.minTimeBetweenStepsMs,
      enableOsLevelSync: enableOsLevelSync ?? this.enableOsLevelSync,
      useForegroundServiceOnOldDevices:
          useForegroundServiceOnOldDevices ??
          this.useForegroundServiceOnOldDevices,
      foregroundServiceMaxApiLevel:
          foregroundServiceMaxApiLevel ?? this.foregroundServiceMaxApiLevel,
      foregroundNotificationTitle:
          foregroundNotificationTitle ?? this.foregroundNotificationTitle,
      foregroundNotificationText:
          foregroundNotificationText ?? this.foregroundNotificationText,
    );
  }

  @override
  String toString() {
    return 'StepDetectorConfig(threshold: $threshold, filterAlpha: $filterAlpha, '
        'minTimeBetweenStepsMs: $minTimeBetweenStepsMs, enableOsLevelSync: $enableOsLevelSync, '
        'useForegroundServiceOnOldDevices: $useForegroundServiceOnOldDevices, '
        'foregroundServiceMaxApiLevel: $foregroundServiceMaxApiLevel)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is StepDetectorConfig &&
        other.threshold == threshold &&
        other.filterAlpha == filterAlpha &&
        other.minTimeBetweenStepsMs == minTimeBetweenStepsMs &&
        other.enableOsLevelSync == enableOsLevelSync &&
        other.useForegroundServiceOnOldDevices ==
            useForegroundServiceOnOldDevices &&
        other.foregroundServiceMaxApiLevel == foregroundServiceMaxApiLevel &&
        other.foregroundNotificationTitle == foregroundNotificationTitle &&
        other.foregroundNotificationText == foregroundNotificationText;
  }

  @override
  int get hashCode {
    return threshold.hashCode ^
        filterAlpha.hashCode ^
        minTimeBetweenStepsMs.hashCode ^
        enableOsLevelSync.hashCode ^
        useForegroundServiceOnOldDevices.hashCode ^
        foregroundServiceMaxApiLevel.hashCode ^
        foregroundNotificationTitle.hashCode ^
        foregroundNotificationText.hashCode;
  }
}
