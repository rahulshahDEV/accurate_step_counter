import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/services.dart';

/// Platform interface for native step counter functionality
///
/// This class handles communication with platform-specific code
/// for OS-level step counting (Android TYPE_STEP_COUNTER sensor)
class StepCounterPlatform {
  static const MethodChannel _channel = MethodChannel('accurate_step_counter');

  // EventChannel for foreground service realtime step events
  static const EventChannel _foregroundEventChannel = EventChannel(
    'accurate_step_counter/foreground_step_events',
  );

  static final StepCounterPlatform _instance = StepCounterPlatform._();

  StepCounterPlatform._();

  /// Singleton instance
  static StepCounterPlatform get instance => _instance;

  /// Stream of realtime step events from foreground service
  ///
  /// Emits a map with 'stepCount' and 'timestamp' on each step
  Stream<Map<dynamic, dynamic>> get foregroundStepEventStream {
    return _foregroundEventChannel
        .receiveBroadcastStream()
        .cast<Map<dynamic, dynamic>>();
  }

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
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getLastStepCount',
      );
      if (result == null) return null;

      return {
        'stepCount': result['stepCount'] as int,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(
          result['timestamp'] as int,
        ),
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
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'syncStepsFromTerminated',
      );

      if (result == null) {
        dev.log('No terminated steps to sync');
        return null;
      }

      final syncData = {
        'missedSteps': result['missedSteps'] as int,
        'startTime': DateTime.fromMillisecondsSinceEpoch(
          result['startTime'] as int,
        ),
        'endTime': DateTime.fromMillisecondsSinceEpoch(
          result['endTime'] as int,
        ),
      };

      dev.log(
        'Terminated steps synced: ${syncData['missedSteps']} steps from ${syncData['startTime']} to ${syncData['endTime']}',
      );

      return syncData;
    } on PlatformException catch (e) {
      dev.log('Error syncing terminated steps: ${e.message}', error: e);
      return null;
    }
  }

  /// Get the Android SDK version
  ///
  /// Returns the SDK_INT value (e.g., 29 for Android 10, 30 for Android 11)
  /// Returns -1 on non-Android platforms
  Future<int> getAndroidVersion() async {
    if (!Platform.isAndroid) {
      return -1;
    }

    try {
      final result = await _channel.invokeMethod<int>('getAndroidVersion');
      dev.log('Android version: $result');
      return result ?? -1;
    } on PlatformException catch (e) {
      dev.log('Error getting Android version: ${e.message}', error: e);
      return -1;
    }
  }

  /// Check if the device is manufactured by Samsung (Android only)
  Future<bool> isSamsungDevice() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isSamsungDevice');
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error checking device manufacturer: ${e.message}', error: e);
      return false;
    }
  }

  /// Start the foreground service for step counting
  ///
  /// This is used on Android ≤10 where terminated state sync doesn't work reliably.
  /// Shows a persistent notification while counting steps.
  ///
  /// [title] - Notification title (default: "Step Counter")
  /// [text] - Notification text (default: "Tracking your steps...")
  Future<bool> startForegroundService({
    String title = 'Step Counter',
    String text = 'Tracking your steps...',
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      dev.log('Starting foreground service');
      final result = await _channel.invokeMethod<bool>(
        'startForegroundService',
        {'title': title, 'text': text},
      );
      dev.log('Foreground service started: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error starting foreground service: ${e.message}', error: e);
      return false;
    }
  }

  /// Stop the foreground service
  Future<bool> stopForegroundService() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      dev.log('Stopping foreground service');
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      dev.log('Foreground service stopped: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error stopping foreground service: ${e.message}', error: e);
      return false;
    }
  }

  /// Check if the foreground service is currently running
  Future<bool> isForegroundServiceRunning() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'isForegroundServiceRunning',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log(
        'Error checking foreground service status: ${e.message}',
        error: e,
      );
      return false;
    }
  }

  /// Get the current step count from the foreground service
  Future<int> getForegroundStepCount() async {
    if (!Platform.isAndroid) {
      return 0;
    }

    try {
      final result = await _channel.invokeMethod<int>('getForegroundStepCount');
      return result ?? 0;
    } on PlatformException catch (e) {
      dev.log('Error getting foreground step count: ${e.message}', error: e);
      return 0;
    }
  }

  /// Reset the foreground service step count to zero
  Future<bool> resetForegroundStepCount() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'resetForegroundStepCount',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error resetting foreground step count: ${e.message}', error: e);
      return false;
    }
  }

  /// Update the foreground service step count from Dart
  ///
  /// This is used when step detection is done in Dart (using sensors_plus)
  /// but we need to persist the count in the native foreground service.
  Future<bool> updateForegroundStepCount(int stepCount) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'updateForegroundStepCount',
        {'stepCount': stepCount},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error updating foreground step count: ${e.message}', error: e);
      return false;
    }
  }

  // ============================================================
  // Hybrid Foreground Service Methods
  // ============================================================

  /// Configure foreground service for hybrid architecture
  ///
  /// When enabled, foreground service will auto-start when app is terminated
  /// on devices with Android API <= [maxApiLevel].
  ///
  /// [enabled] - Whether to use foreground service on app termination
  /// [maxApiLevel] - Maximum API level to use foreground service (default: 29 for Android 10)
  /// [title] - Notification title
  /// [text] - Notification text
  Future<bool> configureForegroundServiceOnTerminated({
    required bool enabled,
    required int maxApiLevel,
    String title = 'Step Counter',
    String text = 'Tracking your steps...',
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      dev.log(
        'Configuring foreground service: enabled=$enabled, maxApi=$maxApiLevel',
      );
      final result = await _channel.invokeMethod<bool>(
        'configureForegroundServiceOnTerminated',
        {
          'enabled': enabled,
          'maxApiLevel': maxApiLevel,
          'title': title,
          'text': text,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      dev.log('Error configuring foreground service: ${e.message}', error: e);
      return false;
    }
  }

  /// Sync steps from foreground service (when resuming from terminated state)
  ///
  /// Returns a map with 'stepCount', 'startTime', and 'endTime' if service was running,
  /// or null if no foreground service was active.
  Future<Map<String, dynamic>?> syncStepsFromForegroundService() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      dev.log('Syncing steps from foreground service');
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'syncStepsFromForegroundService',
      );

      if (result == null) {
        dev.log('No foreground service steps to sync');
        return null;
      }

      final syncData = {
        'stepCount': result['stepCount'] as int,
        'startTime': DateTime.fromMillisecondsSinceEpoch(
          result['startTime'] as int,
        ),
        'endTime': DateTime.fromMillisecondsSinceEpoch(
          result['endTime'] as int,
        ),
      };

      dev.log(
        'Foreground service steps synced: ${syncData['stepCount']} steps',
      );

      return syncData;
    } on PlatformException catch (e) {
      dev.log('Error syncing foreground service steps: ${e.message}', error: e);
      return null;
    }
  }
}
