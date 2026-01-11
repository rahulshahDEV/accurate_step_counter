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
class SensorsStepDetector {
  // Configuration
  double _threshold;
  double _filterAlpha;
  int _minTimeBetweenStepsMs;

  // Internal state
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  final StreamController<StepCountEvent> _stepEventController =
      StreamController<StepCountEvent>.broadcast();

  int _stepCount = 0;
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
  }

  /// Handle accelerometer event and detect steps
  ///
  /// Algorithm:
  /// 1. Apply low-pass filter to smooth data
  /// 2. Calculate magnitude
  /// 3. Detect peaks (upward then downward slope)
  /// 4. Validate timing between steps
  void _handleAccelerometerEvent(UserAccelerometerEvent event) {
    final x = event.x;
    final y = event.y;
    final z = event.z;

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

    // Step 4: Peak detection - upward slope
    if (diff > _threshold) {
      _wasAboveThreshold = true;
    }

    // Step 5: Peak detection - downward slope (step complete)
    if (diff < 0 && _wasAboveThreshold) {
      final now = DateTime.now();

      // Validate minimum time between steps
      final canCountStep =
          _lastStepTime == null ||
          now.difference(_lastStepTime!).inMilliseconds >=
              _minTimeBetweenStepsMs;

      if (canCountStep) {
        _stepCount++;
        _lastStepTime = now;

        // Emit step event
        if (!_stepEventController.isClosed) {
          _stepEventController.add(
            StepCountEvent(stepCount: _stepCount, timestamp: now),
          );
        }

        _log('Step detected: $_stepCount');
      }

      _wasAboveThreshold = false;
    }

    // Update for next iteration
    _previousMagnitude = magnitude;
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
