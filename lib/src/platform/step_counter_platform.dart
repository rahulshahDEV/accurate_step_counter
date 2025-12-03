import 'dart:developer' as dev;
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
      dev.log('Platform not Android, skipping initialization');
      return;
    }

    try {
      dev.log('Initializing platform channel');
      await _channel.invokeMethod('initialize');
      dev.log('Platform channel initialized successfully');
    } catch (e) {
      dev.log('Error initializing platform channel: $e', error: e);
    }
  }

  /// Check if ACTIVITY_RECOGNITION permission is granted (Android only)
  ///
  /// For Android 10+ (API 29+), this permission is required to access the step counter sensor.
  /// For lower Android versions, this always returns true.
  ///
  /// Returns true if permission is granted or not required, false otherwise.
  ///
  /// Example:
  /// ```dart
  /// final hasPermission = await StepCounterPlatform.instance.hasPermission();
  /// if (!hasPermission) {
  ///   // Request permission using permission_handler or similar package
  ///   print('Please grant ACTIVITY_RECOGNITION permission');
  /// }
  /// ```
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) {
      return true; // Not required on other platforms
    }

    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error checking permission: ${e.message}', error: e);
      return false;
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
      dev.log('Getting OS step count from platform');
      final result = await _channel.invokeMethod<int>('getStepCount');
      dev.log('OS step count retrieved: $result');
      return result;
    } on PlatformException catch (e) {
      dev.log('Error getting OS step count: ${e.message}', error: e);
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
      dev.log('Saving step count: $stepCount at $timestamp');
      final result = await _channel.invokeMethod<bool>('saveStepCount', {
        'stepCount': stepCount,
        'timestamp': timestamp.millisecondsSinceEpoch,
      });
      dev.log('Step count saved successfully: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error saving step count: ${e.message}', error: e);
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
      dev.log('Syncing steps from terminated state');
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('syncStepsFromTerminated');

      if (result == null) {
        dev.log('No terminated steps to sync');
        return null;
      }

      final syncData = {
        'missedSteps': result['missedSteps'] as int,
        'startTime':
            DateTime.fromMillisecondsSinceEpoch(result['startTime'] as int),
        'endTime':
            DateTime.fromMillisecondsSinceEpoch(result['endTime'] as int),
      };

      dev.log(
          'Terminated steps synced: ${syncData['missedSteps']} steps from ${syncData['startTime']} to ${syncData['endTime']}');

      return syncData;
    } on PlatformException catch (e) {
      dev.log('Error syncing terminated steps: ${e.message}', error: e);
      return null;
    }
  }
}
