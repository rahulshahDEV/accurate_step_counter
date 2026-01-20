import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

import '../models/step_count_event.dart';

/// Step detector using sensors_plus accelerometer
///
/// This provides a Dart-based step detection algorithm using
/// the accelerometer data from the sensors_plus package.
/// Used for foreground service mode on Android 11 and below.
///
/// Includes built-in shake rejection using sliding window validation.
class SensorsStepDetector {
  // Configuration
  double _threshold;
  double _filterAlpha;
  int _minTimeBetweenStepsMs;

  // Shake rejection configuration
  static const double _maxStepsPerSecond =
      4.0; // Max realistic walking/running rate
  static const int _validationWindowMs = 1500; // 1.5 second validation window
  static const int _minPendingSteps = 3; // Minimum steps before confirmation

  // Internal state
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  final StreamController<StepCountEvent> _stepEventController =
      StreamController<StepCountEvent>.broadcast();

  int _stepCount = 0; // Confirmed steps only
  int _pendingStepCount = 0; // Unconfirmed raw detections
  bool _isRunning = false;
  final bool _debugLogging;

  // Low-pass filter state
  double _filteredX = 0.0;
  double _filteredY = 0.0;
  double _filteredZ = 0.0;

  // Peak detection state
  double _previousMagnitude = 0.0;
  bool _wasAboveThreshold = false;
  DateTime? _lastStepTime;

  // Shake rejection state - sliding window validation
  DateTime? _windowStartTime;
  int _windowStartPendingCount = 0;
  int _lastConfirmedPendingCount = 0;

  /// Creates a new SensorsStepDetector
  ///
  /// [threshold] - Movement threshold for step detection (default: 1.0)
  /// [filterAlpha] - Low-pass filter coefficient (default: 0.8)
  /// [minTimeBetweenStepsMs] - Minimum milliseconds between steps (default: 250)
  /// [debugLogging] - Whether to log debug messages
  SensorsStepDetector({
    double threshold = 1.0,
    double filterAlpha = 0.8,
    int minTimeBetweenStepsMs = 250,
    bool debugLogging = false,
  }) : _threshold = threshold,
       _filterAlpha = filterAlpha,
       _minTimeBetweenStepsMs = minTimeBetweenStepsMs,
       _debugLogging = debugLogging;

  /// Stream of step count events
  Stream<StepCountEvent> get stepEventStream => _stepEventController.stream;

  /// Current step count
  int get stepCount => _stepCount;

  /// Whether the detector is currently running
  bool get isRunning => _isRunning;

  /// Start listening to accelerometer and detecting steps
  Future<void> start({
    double? threshold,
    double? filterAlpha,
    int? minTimeBetweenStepsMs,
  }) async {
    if (_isRunning) {
      _log('Already running');
      return;
    }

    // Apply configuration updates if provided
    if (threshold != null) _threshold = threshold;
    if (filterAlpha != null) _filterAlpha = filterAlpha;
    if (minTimeBetweenStepsMs != null) {
      _minTimeBetweenStepsMs = minTimeBetweenStepsMs;
    }

    _log(
      'Starting with config: threshold=$_threshold, filterAlpha=$_filterAlpha, minTime=$_minTimeBetweenStepsMs',
    );

    // Reset state
    _resetState();

    // Start listening to accelerometer
    // Using userAccelerometerEventStream which excludes gravity
    _accelerometerSubscription =
        userAccelerometerEventStream(
          samplingPeriod: const Duration(
            milliseconds: 20,
          ), // ~50Hz for accuracy
        ).listen(
          _handleAccelerometerEvent,
          onError: (error) {
            _log('Accelerometer error: $error');
          },
        );

    _isRunning = true;
    _log('Step detection started');
  }

  /// Stop listening to accelerometer
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    await _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _isRunning = false;
    _log('Stopped, total steps: $_stepCount');
  }

  /// Reset step count to zero
  void reset() {
    _stepCount = 0;
    _pendingStepCount = 0;
    _resetState();
    _log('Step count reset');
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _stepEventController.close();
  }

  /// Reset internal detection state
  void _resetState() {
    _filteredX = 0.0;
    _filteredY = 0.0;
    _filteredZ = 0.0;
    _previousMagnitude = 0.0;
    _wasAboveThreshold = false;
    _lastStepTime = null;
    // Reset shake rejection state
    _windowStartTime = null;
    _windowStartPendingCount = 0;
    _lastConfirmedPendingCount = 0;
    _pendingStepCount = 0;
  }

  /// Handle accelerometer event and detect steps with shake rejection
  ///
  /// Algorithm:
  /// 1. Apply low-pass filter to smooth data
  /// 2. Calculate magnitude and detect peaks
  /// 3. Track raw detections as "pending" steps
  /// 4. Use sliding window validation to confirm steps (shake rejection)
  /// 5. Only emit confirmed steps
  void _handleAccelerometerEvent(UserAccelerometerEvent event) {
    final x = event.x;
    final y = event.y;
    final z = event.z;
    final now = DateTime.now();

    // Step 1: Apply low-pass filter
    _filteredX = _applyLowPassFilter(_filteredX, x);
    _filteredY = _applyLowPassFilter(_filteredY, y);
    _filteredZ = _applyLowPassFilter(_filteredZ, z);

    // Step 2: Calculate magnitude
    final magnitude = sqrt(
      _filteredX * _filteredX +
          _filteredY * _filteredY +
          _filteredZ * _filteredZ,
    );

    // Step 3: Calculate difference from previous
    final diff = magnitude - _previousMagnitude;
    _previousMagnitude = magnitude;

    // Step 4: Peak detection - upward slope
    if (diff > _threshold) {
      _wasAboveThreshold = true;
    }

    // Step 5: Peak detection - downward slope (raw step detected)
    if (diff < 0 && _wasAboveThreshold) {
      _wasAboveThreshold = false;

      // Validate minimum time between raw detections
      final canCountRaw =
          _lastStepTime == null ||
          now.difference(_lastStepTime!).inMilliseconds >=
              _minTimeBetweenStepsMs;

      if (canCountRaw) {
        _pendingStepCount++;
        _lastStepTime = now;

        // Initialize validation window on first pending step
        if (_windowStartTime == null) {
          _windowStartTime = now;
          _windowStartPendingCount = _pendingStepCount - 1;
          _log('Shake validation window started');
        }
      }
    }

    // Step 6: Sliding window validation for shake rejection
    _validateAndConfirmSteps(now);
  }

  /// Validate pending steps using sliding window and confirm if rate is reasonable
  void _validateAndConfirmSteps(DateTime now) {
    if (_windowStartTime == null) return;

    final windowElapsed = now.difference(_windowStartTime!).inMilliseconds;

    // Wait for validation window to complete
    if (windowElapsed < _validationWindowMs) return;

    // Calculate step rate in this window
    final windowSteps = _pendingStepCount - _windowStartPendingCount;
    final windowSeconds = windowElapsed / 1000.0;
    final stepsPerSecond = windowSteps / windowSeconds;

    if (stepsPerSecond > _maxStepsPerSecond) {
      // Rate too high - likely shake, reject all pending steps in this window
      _log(
        'Shake detected: ${stepsPerSecond.toStringAsFixed(2)}/s > $_maxStepsPerSecond/s - rejecting $windowSteps steps',
      );

      // Reset window but keep pending count (to track continuous shaking)
      _windowStartTime = now;
      _windowStartPendingCount = _pendingStepCount;
      return;
    }

    // Rate is reasonable - check if we have minimum steps to confirm
    if (windowSteps < _minPendingSteps) {
      // Not enough steps yet, extend window
      return;
    }

    // Confirm steps: emit the difference since last confirmation
    final stepsToConfirm = _pendingStepCount - _lastConfirmedPendingCount;
    if (stepsToConfirm > 0) {
      _stepCount += stepsToConfirm;
      _lastConfirmedPendingCount = _pendingStepCount;

      _log(
        'Confirmed $stepsToConfirm steps (rate: ${stepsPerSecond.toStringAsFixed(2)}/s), total: $_stepCount',
      );

      // Emit confirmed step event
      if (!_stepEventController.isClosed) {
        _stepEventController.add(
          StepCountEvent(stepCount: _stepCount, timestamp: now),
        );
      }
    }

    // Advance window for continuous walking
    _windowStartTime = now;
    _windowStartPendingCount = _pendingStepCount;
  }

  /// Apply low-pass filter to smooth accelerometer data
  double _applyLowPassFilter(double previous, double current) {
    return _filterAlpha * previous + (1 - _filterAlpha) * current;
  }

  /// Internal logging helper
  void _log(String message) {
    if (_debugLogging) {
      dev.log('SensorsStepDetector: $message');
    }
  }
}
