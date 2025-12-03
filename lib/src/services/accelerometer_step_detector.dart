import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

import '../models/step_count_event.dart';
import '../models/step_detector_config.dart';

/// Accurate step detection using accelerometer data with low-pass filter
///
/// This class implements a peak detection algorithm for reliable step counting:
/// 1. Applies low-pass filter to smooth accelerometer noise
/// 2. Computes magnitude of acceleration vector
/// 3. Detects peaks when magnitude crosses threshold
/// 4. Counts steps on downward slope transitions
/// 5. Prevents double-counting with time-based validation
class AccelerometerStepDetector {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // Configuration
  late StepDetectorConfig _config;

  // Low-pass filter variables
  double _filteredX = 0.0;
  double _filteredY = 0.0;
  double _filteredZ = 0.0;

  // Step detection variables
  double _previousMagnitude = 0.0;
  bool _wasAboveThreshold = false;
  int _stepCount = 0;
  DateTime? _lastStepTime;

  // Stream controller for step events
  final StreamController<StepCountEvent> _stepEventController =
      StreamController<StepCountEvent>.broadcast();

  /// Stream of step count events
  ///
  /// Listen to this stream to receive real-time step detection events
  ///
  /// Example:
  /// ```dart
  /// detector.stepEventStream.listen((event) {
  ///   print('Step detected! Total: ${event.stepCount}');
  /// });
  /// ```
  Stream<StepCountEvent> get stepEventStream => _stepEventController.stream;

  /// Current step count since start()
  int get stepCount => _stepCount;

  /// Whether the detector is currently active
  bool get isActive => _accelerometerSubscription != null;

  /// Start listening to accelerometer events
  ///
  /// [config] - Optional configuration for step detection sensitivity
  ///
  /// Example:
  /// ```dart
  /// await detector.start(config: StepDetectorConfig.walking());
  /// ```
  Future<void> start({StepDetectorConfig? config}) async {
    _config = config ?? const StepDetectorConfig();

    // Reset state
    _stepCount = 0;
    _wasAboveThreshold = false;
    _previousMagnitude = 0.0;
    _lastStepTime = null;
    _filteredX = 0.0;
    _filteredY = 0.0;
    _filteredZ = 0.0;

    // Cancel any existing subscription
    await stop();

    // Subscribe to accelerometer events
    _accelerometerSubscription = accelerometerEventStream().listen(
      _onAccelerometerEvent,
      onError: (error) {
        // Silently handle errors - just stop listening
        stop();
      },
    );
  }

  /// Stop listening to accelerometer events
  Future<void> stop() async {
    await _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }

  /// Reset step count to zero
  ///
  /// This does not stop the detector, only resets the counter
  void resetStepCount() {
    _stepCount = 0;
    _wasAboveThreshold = false;
    _previousMagnitude = 0.0;
    _lastStepTime = null;
  }

  /// Handle accelerometer events and detect steps
  ///
  /// Algorithm:
  /// 1. Apply low-pass filter
  /// 2. Compute magnitude
  /// 3. Detect upward slope (potential peak)
  /// 4. Detect downward slope (step completion)
  /// 5. Validate timing to prevent double-counting
  void _onAccelerometerEvent(AccelerometerEvent event) {
    try {
      // STEP 1: Apply low-pass filter to smooth accelerometer data
      _filteredX = _applyLowPassFilter(_filteredX, event.x, _config.filterAlpha);
      _filteredY = _applyLowPassFilter(_filteredY, event.y, _config.filterAlpha);
      _filteredZ = _applyLowPassFilter(_filteredZ, event.z, _config.filterAlpha);

      // STEP 2: Compute magnitude: sqrt(x² + y² + z²)
      final magnitude = _computeMagnitude(_filteredX, _filteredY, _filteredZ);

      // STEP 3: Compute difference from previous magnitude
      final diff = magnitude - _previousMagnitude;

      // STEP 4: Check if difference exceeds threshold (peak detection)
      if (diff > _config.threshold) {
        // We're on an upward slope (potential peak)
        _wasAboveThreshold = true;
      }

      // STEP 5: Check if difference becomes negative (downward slope)
      // This indicates we've passed the peak
      if (diff < 0 && _wasAboveThreshold) {
        // Verify minimum time between steps to avoid double counting
        final now = DateTime.now();
        if (_lastStepTime == null ||
            now.difference(_lastStepTime!).inMilliseconds >=
                _config.minTimeBetweenStepsMs) {
          // STEP DETECTED!
          _incrementStepCount();
          _lastStepTime = now;
        }

        // Reset flag
        _wasAboveThreshold = false;
      }

      // STEP 6: Update previous magnitude for next iteration
      _previousMagnitude = magnitude;
    } catch (e) {
      // Silently handle errors to avoid crashing the app
      // In production, you might want to log this
    }
  }

  /// Apply low-pass filter to smooth sensor data
  ///
  /// Formula: filtered = alpha * previousFiltered + (1 - alpha) * newValue
  /// - Higher alpha = more smoothing, less responsive
  /// - Lower alpha = less smoothing, more responsive
  double _applyLowPassFilter(
      double previousFiltered, double newValue, double alpha) {
    return alpha * previousFiltered + (1 - alpha) * newValue;
  }

  /// Compute magnitude of acceleration vector
  ///
  /// Formula: magnitude = sqrt(x² + y² + z²)
  double _computeMagnitude(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  /// Increment step count and emit event
  void _incrementStepCount() {
    _stepCount++;

    // Emit step event
    final event = StepCountEvent(
      stepCount: _stepCount,
      timestamp: DateTime.now(),
      confidence: 1.0, // Future: could be based on magnitude strength
    );

    if (!_stepEventController.isClosed) {
      _stepEventController.add(event);
    }
  }

  /// Dispose the detector and clean up resources
  Future<void> dispose() async {
    await stop();
    await _stepEventController.close();
    _stepCount = 0;
    _wasAboveThreshold = false;
    _previousMagnitude = 0.0;
    _lastStepTime = null;
  }
}
