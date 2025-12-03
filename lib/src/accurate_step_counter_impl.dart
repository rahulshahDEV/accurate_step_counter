import 'dart:async';
import 'dart:developer' as dev;

import 'models/step_count_event.dart';
import 'models/step_detector_config.dart';
import 'platform/step_counter_platform.dart';
import 'services/accelerometer_step_detector.dart';

/// Implementation of the AccurateStepCounter plugin
///
/// This class provides the core functionality for accurate step counting
/// using accelerometer-based detection with optional OS-level synchronization.
class AccurateStepCounterImpl {
  final AccelerometerStepDetector _accelerometerDetector =
      AccelerometerStepDetector();
  final StepCounterPlatform _platform = StepCounterPlatform.instance;

  StepDetectorConfig? _currentConfig;
  bool _isStarted = false;

  /// Callback for handling missed steps from terminated state
  /// Parameters: (missedSteps, startTime, endTime)
  Function(int, DateTime, DateTime)? onTerminatedStepsDetected;

  /// Stream of step count events from the accelerometer detector
  Stream<StepCountEvent> get stepEventStream =>
      _accelerometerDetector.stepEventStream;

  /// Current step count since start()
  int get currentStepCount => _accelerometerDetector.stepCount;

  /// Whether the step counter is currently active
  bool get isStarted => _isStarted;

  /// Start step detection
  ///
  /// [config] - Optional configuration for step detection sensitivity
  ///
  /// Example:
  /// ```dart
  /// // Start with default config
  /// await stepCounter.start();
  ///
  /// // Start with custom config
  /// await stepCounter.start(
  ///   config: StepDetectorConfig.walking(),
  /// );
  ///
  /// // Start with fine-tuned parameters
  /// await stepCounter.start(
  ///   config: StepDetectorConfig(
  ///     threshold: 1.2,
  ///     filterAlpha: 0.85,
  ///   ),
  /// );
  /// ```
  ///
  /// Throws [StateError] if already started
  Future<void> start({StepDetectorConfig? config}) async {
    if (_isStarted) {
      throw StateError('Step counter is already started');
    }

    _currentConfig = config ?? const StepDetectorConfig();

    // Initialize platform channel for OS-level sync (if enabled)
    if (_currentConfig!.enableOsLevelSync) {
      await _platform.initialize();

      // Sync steps from terminated state
      await _syncStepsFromTerminatedState();
    }

    // Start accelerometer-based detection
    await _accelerometerDetector.start(config: _currentConfig);

    _isStarted = true;
  }

  /// Stop step detection
  ///
  /// This stops the accelerometer listening but preserves the current step count.
  /// Call [reset] if you want to clear the step count as well.
  ///
  /// Example:
  /// ```dart
  /// await stepCounter.stop();
  /// print('Stopped at: ${stepCounter.currentStepCount} steps');
  /// ```
  Future<void> stop() async {
    if (!_isStarted) {
      return;
    }

    await _accelerometerDetector.stop();
    _isStarted = false;
  }

  /// Reset the step counter to zero
  ///
  /// This does not stop the detector if it's running.
  /// Use this to start counting from zero while continuing detection.
  ///
  /// Example:
  /// ```dart
  /// // Reset counter but keep detecting
  /// stepCounter.reset();
  ///
  /// // Stop and reset
  /// await stepCounter.stop();
  /// stepCounter.reset();
  /// ```
  void reset() {
    _accelerometerDetector.resetStepCount();
  }

  /// Get the current configuration being used
  ///
  /// Returns null if not started yet
  StepDetectorConfig? get currentConfig => _currentConfig;

  /// Dispose the step counter and release all resources
  ///
  /// Call this when you're completely done with the step counter
  /// (e.g., in your widget's dispose method)
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void dispose() {
  ///   stepCounter.dispose();
  ///   super.dispose();
  /// }
  /// ```
  Future<void> dispose() async {
    await stop();
    await _accelerometerDetector.dispose();
    _currentConfig = null;
  }

  /// Get steps from OS-level step counter (Android only)
  ///
  /// This is useful for validating the accelerometer count against
  /// the device's native step counter.
  ///
  /// Returns null if OS-level counting is not available or disabled
  ///
  /// Example:
  /// ```dart
  /// final osSteps = await stepCounter.getOsStepCount();
  /// if (osSteps != null) {
  ///   print('OS reports: $osSteps steps');
  ///   print('Our count: ${stepCounter.currentStepCount} steps');
  /// }
  /// ```
  Future<int?> getOsStepCount() async {
    if (_currentConfig?.enableOsLevelSync != true) {
      return null;
    }

    try {
      return await _platform.getOsStepCount();
    } catch (e) {
      return null;
    }
  }

  /// Save current state for recovery after app termination (Android only)
  ///
  /// This is called automatically during normal operation,
  /// but you can call it manually to ensure state is saved.
  ///
  /// Example:
  /// ```dart
  /// // Before app might be terminated
  /// await stepCounter.saveState();
  /// ```
  Future<void> saveState() async {
    if (_currentConfig?.enableOsLevelSync != true) {
      return;
    }

    try {
      final osCount = await _platform.getOsStepCount();
      if (osCount != null) {
        await _platform.saveStepCount(osCount, DateTime.now());
      }
    } catch (e) {
      // Silently fail
    }
  }

  /// Sync steps from terminated state (Android only)
  ///
  /// This method is called automatically during start() when OS-level sync
  /// is enabled. It retrieves steps that were counted while the app was
  /// terminated and notifies via the [onTerminatedStepsDetected] callback.
  ///
  /// Returns the synced data or null if no steps were missed.
  Future<Map<String, dynamic>?> _syncStepsFromTerminatedState() async {
    try {
      dev.log('AccurateStepCounter: Checking for steps from terminated state...');

      final result = await _platform.syncStepsFromTerminated();

      if (result == null) {
        dev.log('AccurateStepCounter: No steps to sync from terminated state');
        return null;
      }

      final missedSteps = result['missedSteps'] as int;
      final startTime = result['startTime'] as DateTime;
      final endTime = result['endTime'] as DateTime;

      dev.log('AccurateStepCounter: Syncing $missedSteps steps from terminated state');
      dev.log('AccurateStepCounter: Time range: $startTime to $endTime');

      // Notify via callback if registered
      if (onTerminatedStepsDetected != null) {
        onTerminatedStepsDetected!(missedSteps, startTime, endTime);
      }

      return result;
    } catch (e) {
      dev.log('AccurateStepCounter: Error syncing steps after termination: $e');
      return null;
    }
  }

  /// Manually sync steps from terminated state
  ///
  /// This is called automatically during start(), but you can call it manually
  /// if needed. Requires OS-level sync to be enabled.
  ///
  /// Returns a map with 'missedSteps', 'startTime', and 'endTime' if steps
  /// were synced, or null if no steps were missed or sync is disabled.
  ///
  /// Example:
  /// ```dart
  /// final result = await stepCounter.syncTerminatedSteps();
  /// if (result != null) {
  ///   print('Synced ${result['missedSteps']} steps');
  /// }
  /// ```
  Future<Map<String, dynamic>?> syncTerminatedSteps() async {
    if (_currentConfig?.enableOsLevelSync != true) {
      return null;
    }

    return await _syncStepsFromTerminatedState();
  }
}
