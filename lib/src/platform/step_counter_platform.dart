import 'dart:io';

import 'package:flutter/services.dart';

/// Platform interface for native step counter functionality
///
/// This class handles communication with platform-specific code
/// for OS-level step counting (Android TYPE_STEP_COUNTER sensor)
class StepCounterPlatform {
  static const MethodChannel _channel =
      MethodChannel('accurate_step_counter');

  static final StepCounterPlatform _instance = StepCounterPlatform._();

  StepCounterPlatform._();

  /// Singleton instance
  static StepCounterPlatform get instance => _instance;

  /// Initialize the platform channel
  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod('initialize');
    } catch (e) {
      // Platform not supported or error occurred
    }
  }

  /// Get current OS-level step count
  ///
  /// Returns null if not available or on unsupported platform
  Future<int?> getOsStepCount() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<int>('getStepCount');
      return result;
    } on PlatformException {
      return null;
    }
  }

  /// Save step count to native SharedPreferences
  ///
  /// [stepCount] - The step count to save
  /// [timestamp] - When this count was recorded
  Future<bool> saveStepCount(int stepCount, DateTime timestamp) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('saveStepCount', {
        'stepCount': stepCount,
        'timestamp': timestamp.millisecondsSinceEpoch,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Get last saved step count from native SharedPreferences
  ///
  /// Returns a map with 'stepCount' and 'timestamp' keys, or null if not found
  Future<Map<String, dynamic>?> getLastStepCount() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getLastStepCount');
      if (result == null) return null;

      return {
        'stepCount': result['stepCount'] as int,
        'timestamp':
            DateTime.fromMillisecondsSinceEpoch(result['timestamp'] as int),
      };
    } on PlatformException {
      return null;
    }
  }

  /// Sync steps from terminated state
  ///
  /// This retrieves and validates steps that were counted while the app
  /// was terminated (killed by user or system)
  ///
  /// Returns a map with:
  /// - 'missedSteps': int - Steps detected while app was closed
  /// - 'startTime': DateTime - When app was closed
  /// - 'endTime': DateTime - When app reopened
  ///
  /// Returns null if no missed steps or validation failed
  Future<Map<String, dynamic>?> syncStepsFromTerminated() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('syncStepsFromTerminated');
      if (result == null) return null;

      return {
        'missedSteps': result['missedSteps'] as int,
        'startTime':
            DateTime.fromMillisecondsSinceEpoch(result['startTime'] as int),
        'endTime':
            DateTime.fromMillisecondsSinceEpoch(result['endTime'] as int),
      };
    } on PlatformException {
      return null;
    }
  }
}
