import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/step_count_event.dart';
import '../models/step_detector_config.dart';

/// Native step detector using Android's TYPE_STEP_DETECTOR sensor
///
/// This class communicates with the native Kotlin implementation
/// via MethodChannel and EventChannel for real-time step events.
///
/// **Note**: This detector only works on Android. On other platforms,
/// all methods will return gracefully without errors.
class NativeStepDetector {
  static const MethodChannel _channel = MethodChannel('accurate_step_counter');
  static const EventChannel _eventChannel = EventChannel(
    'accurate_step_counter/step_events',
  );

  StreamSubscription<dynamic>? _eventSubscription;
  final StreamController<StepCountEvent> _stepEventController =
      StreamController<StepCountEvent>.broadcast();

  int _stepCount = 0;
  bool _isActive = false;

  /// Stream of step count events from native detector
  Stream<StepCountEvent> get stepEventStream => _stepEventController.stream;

  /// Current step count
  int get stepCount => _stepCount;

  /// Whether the detector is currently active
  bool get isActive => _isActive;

  /// Start native step detection
  ///
  /// [config] - Optional configuration for step detection
  ///
  /// **Note**: This only works on Android. On other platforms, this method
  /// returns immediately without starting detection.
  Future<void> start({StepDetectorConfig? config}) async {
    // Only works on Android
    if (!Platform.isAndroid) {
      dev.log('NativeStepDetector: Not on Android, skipping start');
      return;
    }

    if (_isActive) {
      dev.log('NativeStepDetector: Already active');
      return;
    }

    dev.log('NativeStepDetector: Starting native detection');

    // Reset state
    _stepCount = 0;

    // Start listening to EventChannel
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _onStepEvent,
      onError: (error) {
        dev.log('NativeStepDetector: EventChannel error: $error');
      },
    );

    // Call native start method with config
    try {
      await _channel.invokeMethod('startNativeDetection', {
        'threshold': config?.threshold ?? 1.0,
        'filterAlpha': config?.filterAlpha ?? 0.8,
        'minTimeBetweenStepsMs': config?.minTimeBetweenStepsMs ?? 200,
      });

      _isActive = true;
      dev.log('NativeStepDetector: Started successfully');
    } on PlatformException catch (e) {
      dev.log('NativeStepDetector: Failed to start: ${e.message}');
      _eventSubscription?.cancel();
      _eventSubscription = null;
      rethrow;
    }
  }

  /// Stop native step detection
  Future<void> stop() async {
    if (!Platform.isAndroid || !_isActive) {
      return;
    }

    dev.log('NativeStepDetector: Stopping');

    _eventSubscription?.cancel();
    _eventSubscription = null;

    try {
      await _channel.invokeMethod('stopNativeDetection');
    } on PlatformException catch (e) {
      dev.log('NativeStepDetector: Failed to stop: ${e.message}');
    }

    _isActive = false;
  }

  /// Reset step count to zero
  Future<void> resetStepCount() async {
    _stepCount = 0;

    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod('resetNativeStepCount');
    } on PlatformException catch (e) {
      dev.log('NativeStepDetector: Failed to reset: ${e.message}');
    }
  }

  /// Handle step events from native code
  void _onStepEvent(dynamic event) {
    if (event is Map) {
      final stepCount = event['stepCount'] as int?;
      final timestamp = event['timestamp'] as int?;

      if (stepCount != null) {
        _stepCount = stepCount;

        final stepEvent = StepCountEvent(
          stepCount: stepCount,
          timestamp: timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
              : DateTime.now().toUtc(),
        );

        if (!_stepEventController.isClosed) {
          _stepEventController.add(stepEvent);
        }
      }
    }
  }

  /// Check if using hardware TYPE_STEP_DETECTOR
  Future<bool> isUsingHardwareDetector() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'isUsingHardwareDetector',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _stepEventController.close();
  }
}
