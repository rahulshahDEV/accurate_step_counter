import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'models/step_count_event.dart';
import 'models/step_detector_config.dart';
import 'platform/step_counter_platform.dart';
import 'services/native_step_detector.dart';

/// Implementation of the AccurateStepCounter plugin
///
/// This class provides the core functionality for accurate step counting
/// using native Android step detection with optional foreground service.
class AccurateStepCounterImpl {
  final NativeStepDetector _nativeDetector = NativeStepDetector();
  final StepCounterPlatform _platform = StepCounterPlatform.instance;

  StepDetectorConfig? _currentConfig;
  bool _isStarted = false;
  bool _useForegroundService = false;
  Timer? _foregroundStepPollTimer;
  final StreamController<StepCountEvent> _foregroundStepController =
      StreamController<StepCountEvent>.broadcast();
  int _lastForegroundStepCount = 0;

  /// Callback for handling missed steps from terminated state
  /// Parameters: (missedSteps, startTime, endTime)
  Function(int, DateTime, DateTime)? onTerminatedStepsDetected;

  /// Stream of step count events
  ///
  /// Returns events from native detector or foreground service
  /// depending on the Android version and configuration.
  Stream<StepCountEvent> get stepEventStream {
    if (_useForegroundService) {
      return _foregroundStepController.stream;
    }
    return _nativeDetector.stepEventStream;
  }

  /// Current step count since start()
  int get currentStepCount {
    if (_useForegroundService) {
      return _lastForegroundStepCount;
    }
    return _nativeDetector.stepCount;
  }

  /// Whether the step counter is currently active
  bool get isStarted => _isStarted;

  /// Whether foreground service mode is being used
  bool get isUsingForegroundService => _useForegroundService;

  /// Whether native hardware step detector is being used
  Future<bool> isUsingNativeDetector() =>
      _nativeDetector.isUsingHardwareDetector();

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
    _useForegroundService = false;

    // Check if we should use foreground service based on configured API level
    if (Platform.isAndroid &&
        _currentConfig!.useForegroundServiceOnOldDevices) {
      final androidVersion = await _platform.getAndroidVersion();
      final maxApiLevel = _currentConfig!.foregroundServiceMaxApiLevel;
      dev.log('AccurateStepCounter: Android API level is $androidVersion');
      dev.log(
        'AccurateStepCounter: Foreground service max API level is $maxApiLevel',
      );

      // Use foreground service for API ≤ configured maxApiLevel
      if (androidVersion > 0 && androidVersion <= maxApiLevel) {
        dev.log(
          'AccurateStepCounter: Using foreground service for API ≤$maxApiLevel',
        );
        _useForegroundService = true;

        // Start the foreground service
        await _platform.startForegroundService(
          title: _currentConfig!.foregroundNotificationTitle,
          text: _currentConfig!.foregroundNotificationText,
        );

        // Start polling for step count updates
        _startForegroundStepPolling();

        _isStarted = true;
        return;
      }
    }

    // For Android 11+ or iOS, use native step detection
    // Initialize platform channel for OS-level sync (if enabled)
    if (_currentConfig!.enableOsLevelSync && Platform.isAndroid) {
      await _platform.initialize();

      // Sync steps from terminated state
      await _syncStepsFromTerminatedState();
    }

    // Start native step detection
    await _nativeDetector.start(config: _currentConfig);

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

    if (_useForegroundService) {
      _stopForegroundStepPolling();
      await _platform.stopForegroundService();
      _useForegroundService = false;
    } else {
      await _nativeDetector.stop();
    }

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
    if (_useForegroundService) {
      _platform.resetForegroundStepCount();
      _lastForegroundStepCount = 0;
    } else {
      _nativeDetector.resetStepCount();
    }
  }

  /// Start polling for step count updates from foreground service
  void _startForegroundStepPolling() {
    _foregroundStepPollTimer?.cancel();
    _foregroundStepPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollForegroundStepCount(),
    );
  }

  /// Stop polling for step count updates
  void _stopForegroundStepPolling() {
    _foregroundStepPollTimer?.cancel();
    _foregroundStepPollTimer = null;
  }

  /// Poll the foreground service for current step count
  Future<void> _pollForegroundStepCount() async {
    try {
      final stepCount = await _platform.getForegroundStepCount();

      if (stepCount > _lastForegroundStepCount) {
        _lastForegroundStepCount = stepCount;

        if (!_foregroundStepController.isClosed) {
          _foregroundStepController.add(
            StepCountEvent(stepCount: stepCount, timestamp: DateTime.now()),
          );
        }
      }
    } catch (e) {
      dev.log('AccurateStepCounter: Error polling foreground step count: $e');
    }
  }

  /// Get the current configuration being used
  ///
  /// Returns null if not started yet
  StepDetectorConfig? get currentConfig => _currentConfig;

  /// Check if ACTIVITY_RECOGNITION permission is granted (Android only)
  ///
  /// For Android 10+ (API 29+), this permission is required to access
  /// the step counter sensor for OS-level synchronization.
  ///
  /// Returns true if permission is granted or not required, false otherwise.
  ///
  /// Note: You should request this permission before calling start() with
  /// OS-level sync enabled. Use a permission package like 'permission_handler'
  /// to request the permission from the user.
  ///
  /// Example:
  /// ```dart
  /// final hasPermission = await stepCounter.hasActivityRecognitionPermission();
  /// if (!hasPermission) {
  ///   // Use permission_handler or similar to request permission
  ///   await Permission.activityRecognition.request();
  /// }
  /// ```
  Future<bool> hasActivityRecognitionPermission() async {
    return await _platform.hasPermission();
  }

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
    await _nativeDetector.dispose();
    _stopForegroundStepPolling();
    await _foregroundStepController.close();
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
      dev.log(
        'AccurateStepCounter: Checking for steps from terminated state...',
      );

      final result = await _platform.syncStepsFromTerminated();

      if (result == null) {
        dev.log('AccurateStepCounter: No steps to sync from terminated state');
        return null;
      }

      final missedSteps = result['missedSteps'] as int;
      final startTime = result['startTime'] as DateTime;
      final endTime = result['endTime'] as DateTime;

      dev.log(
        'AccurateStepCounter: Syncing $missedSteps steps from terminated state',
      );
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
