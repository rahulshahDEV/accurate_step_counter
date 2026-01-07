import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'models/step_count_event.dart';
import 'models/step_detector_config.dart';
import 'models/step_log_entry.dart';
import 'models/step_log_source.dart';
import 'platform/step_counter_platform.dart';
import 'services/native_step_detector.dart';
import 'services/step_log_database.dart';

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

  // Step logging
  final StepLogDatabase _stepLogDatabase = StepLogDatabase();
  bool _loggingEnabled = false;
  bool _loggingInitialized = false;
  StreamSubscription<StepCountEvent>? _stepLogSubscription;
  DateTime? _lastLogTime;
  int _lastLoggedStepCount = 0;

  // App lifecycle state tracking for proper source detection
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  int _logIntervalMs = 5000;

  // Warmup validation state
  bool _isInWarmup = false;
  DateTime? _warmupStartTime;
  int _warmupDurationMs = 0;
  int _minStepsToValidate = 10;
  double _maxStepsPerSecond = 5.0;
  int _warmupStartStepCount = 0;

  /// Callback for handling missed steps from terminated state
  /// Parameters: (missedSteps, startTime, endTime)
  Function(int, DateTime, DateTime)? onTerminatedStepsDetected;

  /// Whether step logging to local database is enabled
  bool get isLoggingEnabled => _loggingEnabled;

  /// Whether the step log database has been initialized
  bool get isLoggingInitialized => _loggingInitialized;

  /// Current app lifecycle state (used for source detection)
  AppLifecycleState get appLifecycleState => _appLifecycleState;

  /// Whether the app is currently in the foreground
  bool get isAppInForeground => _appLifecycleState == AppLifecycleState.resumed;

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
    await _stepLogSubscription?.cancel();
    await _foregroundStepController.close();
    await _stepLogDatabase.close();
    _currentConfig = null;
  }

  // ============================================================
  // Step Logging API (Health Connect-like)
  // ============================================================

  /// Initialize the step logging database
  ///
  /// Must be called before using any logging features. Can be called
  /// multiple times safely - subsequent calls are no-ops.
  ///
  /// Example:
  /// ```dart
  /// final stepCounter = AccurateStepCounter();
  /// await stepCounter.initializeLogging();
  /// await stepCounter.start(enableLogging: true);
  /// ```
  Future<void> initializeLogging() async {
    if (_loggingInitialized) return;

    await _stepLogDatabase.initialize();
    _loggingInitialized = true;
    dev.log('AccurateStepCounter: Logging database initialized');
  }

  /// Start auto-logging steps to the local database
  ///
  /// Call [initializeLogging] first. Steps will be logged automatically
  /// as they are detected, with source tracking (foreground/background).
  ///
  /// [logIntervalMs] - Minimum time between log entries in milliseconds.
  ///                   Default is 5000ms (5 seconds) to prevent excessive writes.
  ///
  /// Example:
  /// ```dart
  /// await stepCounter.initializeLogging();
  /// await stepCounter.startLogging();
  /// await stepCounter.start();
  /// ```
  ///
  /// With warmup validation:
  /// ```dart
  /// await stepCounter.startLogging(
  ///   warmupDurationMs: 8000,    // Wait 8 seconds before first log
  ///   minStepsToValidate: 10,   // Need 10+ steps to confirm walking
  ///   maxStepsPerSecond: 5.0,   // Reject unrealistic step rates
  /// );
  /// ```
  Future<void> startLogging({
    int logIntervalMs = 5000,
    int warmupDurationMs = 0,
    int minStepsToValidate = 10,
    double maxStepsPerSecond = 5.0,
  }) async {
    if (!_loggingInitialized) {
      throw StateError(
        'Logging not initialized. Call initializeLogging() first.',
      );
    }

    if (_loggingEnabled) return;

    _loggingEnabled = true;
    _logIntervalMs = logIntervalMs;
    _warmupDurationMs = warmupDurationMs;
    _minStepsToValidate = minStepsToValidate;
    _maxStepsPerSecond = maxStepsPerSecond;
    _isInWarmup = warmupDurationMs > 0;
    _warmupStartTime = null;
    _warmupStartStepCount = 0;
    _lastLogTime = DateTime.now();
    _lastLoggedStepCount = 0;

    // Subscribe to step events for auto-logging
    _stepLogSubscription = stepEventStream.listen((event) {
      _autoLogSteps(event, _logIntervalMs);
    });

    if (_isInWarmup) {
      dev.log(
        'AccurateStepCounter: Step logging started with ${warmupDurationMs}ms warmup',
      );
    } else {
      dev.log('AccurateStepCounter: Step logging started');
    }
  }

  /// Stop auto-logging steps
  Future<void> stopLogging() async {
    await _stepLogSubscription?.cancel();
    _stepLogSubscription = null;
    _loggingEnabled = false;
    dev.log('AccurateStepCounter: Step logging stopped');
  }

  /// Set the current app lifecycle state
  ///
  /// Call this from your WidgetsBindingObserver to properly track
  /// foreground vs background state for step logging.
  ///
  /// Example:
  /// ```dart
  /// class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ///   final stepCounter = AccurateStepCounter();
  ///
  ///   @override
  ///   void initState() {
  ///     super.initState();
  ///     WidgetsBinding.instance.addObserver(this);
  ///   }
  ///
  ///   @override
  ///   void didChangeAppLifecycleState(AppLifecycleState state) {
  ///     stepCounter.setAppState(state);
  ///   }
  /// }
  /// ```
  void setAppState(AppLifecycleState state) {
    _appLifecycleState = state;
    dev.log('AccurateStepCounter: App state changed to $state');

    // If logging is enabled and app goes to background, log current steps
    if (_loggingEnabled &&
        state != AppLifecycleState.resumed &&
        _lastLogTime != null) {
      // Force log current batch before going to background
      final currentCount = currentStepCount;
      if (currentCount > _lastLoggedStepCount) {
        final entry = StepLogEntry(
          stepCount: currentCount - _lastLoggedStepCount,
          fromTime: _lastLogTime!,
          toTime: DateTime.now(),
          source: StepLogSource.foreground,
        );
        _stepLogDatabase.logSteps(entry);
        _lastLogTime = DateTime.now();
        _lastLoggedStepCount = currentCount;
        dev.log('AccurateStepCounter: Logged steps before background');
      }
    }
  }

  /// Auto-log steps based on interval with warmup validation
  void _autoLogSteps(StepCountEvent event, int intervalMs) {
    final now = DateTime.now();

    // === WARMUP PHASE ===
    if (_isInWarmup) {
      // Initialize warmup on first step event
      if (_warmupStartTime == null) {
        _warmupStartTime = now;
        _warmupStartStepCount = event.stepCount;
        dev.log('AccurateStepCounter: Warmup started');
        return;
      }

      final warmupElapsed = now.difference(_warmupStartTime!);
      if (warmupElapsed.inMilliseconds < _warmupDurationMs) {
        // Still in warmup - don't log yet, just track
        return;
      }

      // Warmup complete - validate walking
      final warmupSteps = event.stepCount - _warmupStartStepCount;

      // Validation 1: Minimum steps required
      if (warmupSteps < _minStepsToValidate) {
        // Not enough steps - reset and wait for real walking
        dev.log(
          'AccurateStepCounter: Warmup failed - only $warmupSteps steps (need $_minStepsToValidate)',
        );
        _warmupStartTime = now;
        _warmupStartStepCount = event.stepCount;
        return;
      }

      // Validation 2: Step rate check
      final warmupSeconds = warmupElapsed.inMilliseconds / 1000.0;
      final stepsPerSecond = warmupSteps / warmupSeconds;
      if (stepsPerSecond > _maxStepsPerSecond) {
        // Unrealistic rate - shake or noise, not walking
        dev.log(
          'AccurateStepCounter: Warmup failed - rate ${stepsPerSecond.toStringAsFixed(2)}/s exceeds max $_maxStepsPerSecond/s',
        );
        _warmupStartTime = now;
        _warmupStartStepCount = event.stepCount;
        return;
      }

      // ✓ Walking validated - log warmup steps
      dev.log(
        'AccurateStepCounter: Warmup validated - $warmupSteps steps at ${stepsPerSecond.toStringAsFixed(2)}/s',
      );

      final source = _determineSource();
      final entry = StepLogEntry(
        stepCount: warmupSteps,
        fromTime: _warmupStartTime!,
        toTime: now,
        source: source,
        confidence: event.confidence,
      );

      _stepLogDatabase.logSteps(entry);
      dev.log(
        'AccurateStepCounter: Logged $warmupSteps warmup steps (source: $source)',
      );

      // Exit warmup mode
      _isInWarmup = false;
      _lastLogTime = now;
      _lastLoggedStepCount = event.stepCount;
      return;
    }

    // === NORMAL LOGGING (after warmup) ===

    if (_lastLogTime == null) {
      _lastLogTime = now;
      _lastLoggedStepCount = event.stepCount;
      return;
    }

    final elapsed = now.difference(_lastLogTime!);
    if (elapsed.inMilliseconds >= intervalMs) {
      final newSteps = event.stepCount - _lastLoggedStepCount;

      if (newSteps > 0) {
        // Validate step rate
        final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
        final stepsPerSecond = newSteps / elapsedSeconds;

        if (stepsPerSecond > _maxStepsPerSecond) {
          // Unrealistic rate - skip this batch
          dev.log(
            'AccurateStepCounter: Skipping $newSteps steps - rate ${stepsPerSecond.toStringAsFixed(2)}/s too high',
          );
          _lastLogTime = now;
          _lastLoggedStepCount = event.stepCount;
          return;
        }

        final source = _determineSource();
        final entry = StepLogEntry(
          stepCount: newSteps,
          fromTime: _lastLogTime!,
          toTime: now,
          source: source,
          confidence: event.confidence,
        );

        _stepLogDatabase.logSteps(entry);
        dev.log(
          'AccurateStepCounter: Logged $newSteps steps (source: $source)',
        );
      }

      _lastLogTime = now;
      _lastLoggedStepCount = event.stepCount;
    }
  }

  /// Determine the step log source based on current mode and app state
  StepLogSource _determineSource() {
    if (_useForegroundService) {
      // Old Android with foreground service - counts in background
      return StepLogSource.background;
    } else if (_appLifecycleState == AppLifecycleState.resumed) {
      // New Android, app in foreground
      return StepLogSource.foreground;
    } else {
      // New Android, app in background (paused, inactive, etc.)
      return StepLogSource.background;
    }
  }

  /// Log steps from terminated state sync
  ///
  /// Note: Only requires logging to be initialized, not enabled,
  /// so terminated steps are logged even before startLogging() is called.
  Future<void> _logTerminatedSteps(
    int stepCount,
    DateTime fromTime,
    DateTime toTime,
  ) async {
    // Only require initialized, not enabled - terminated steps should
    // always be logged if database is ready, regardless of auto-logging state
    if (!_loggingInitialized) {
      dev.log(
        'AccurateStepCounter: Skipping terminated steps log - database not initialized',
      );
      return;
    }

    final entry = StepLogEntry(
      stepCount: stepCount,
      fromTime: fromTime,
      toTime: toTime,
      source: StepLogSource.terminated,
    );

    await _stepLogDatabase.logSteps(entry);
    dev.log('AccurateStepCounter: Logged $stepCount terminated steps');
  }

  /// Manually log a step entry
  ///
  /// Useful for recording steps from external sources or correcting data.
  ///
  /// Example:
  /// ```dart
  /// await stepCounter.logSteps(StepLogEntry(
  ///   stepCount: 100,
  ///   fromTime: DateTime.now().subtract(Duration(hours: 1)),
  ///   toTime: DateTime.now(),
  ///   source: StepLogSource.foreground,
  /// ));
  /// ```
  Future<void> logSteps(StepLogEntry entry) async {
    if (!_loggingInitialized) {
      throw StateError(
        'Logging not initialized. Call initializeLogging() first.',
      );
    }
    await _stepLogDatabase.logSteps(entry);
  }

  /// Get total step count from logs (aggregate)
  ///
  /// [from] - Optional start time filter (inclusive)
  /// [to] - Optional end time filter (inclusive)
  ///
  /// Example:
  /// ```dart
  /// // Get all-time total
  /// final total = await stepCounter.getTotalSteps();
  ///
  /// // Get today's total
  /// final today = DateTime.now();
  /// final startOfDay = DateTime(today.year, today.month, today.day);
  /// final todaySteps = await stepCounter.getTotalSteps(
  ///   from: startOfDay,
  ///   to: today,
  /// );
  /// ```
  Future<int> getTotalSteps({DateTime? from, DateTime? to}) async {
    _ensureLoggingInitialized();
    return await _stepLogDatabase.getTotalSteps(from: from, to: to);
  }

  /// Get step count by source
  ///
  /// Example:
  /// ```dart
  /// final fgSteps = await stepCounter.getStepsBySource(StepLogSource.foreground);
  /// final bgSteps = await stepCounter.getStepsBySource(StepLogSource.background);
  /// final termSteps = await stepCounter.getStepsBySource(StepLogSource.terminated);
  /// ```
  Future<int> getStepsBySource(
    StepLogSource source, {
    DateTime? from,
    DateTime? to,
  }) async {
    _ensureLoggingInitialized();
    return await _stepLogDatabase.getStepsBySource(source, from: from, to: to);
  }

  /// Get all step log entries
  ///
  /// [from] - Optional start time filter
  /// [to] - Optional end time filter
  /// [source] - Optional source filter
  ///
  /// Example:
  /// ```dart
  /// final allLogs = await stepCounter.getStepLogs();
  /// final bgLogs = await stepCounter.getStepLogs(source: StepLogSource.background);
  /// ```
  Future<List<StepLogEntry>> getStepLogs({
    DateTime? from,
    DateTime? to,
    StepLogSource? source,
  }) async {
    _ensureLoggingInitialized();
    return await _stepLogDatabase.getStepLogs(
      from: from,
      to: to,
      source: source,
    );
  }

  /// Watch total step count in real-time
  ///
  /// Emits updates whenever new steps are logged.
  ///
  /// Example:
  /// ```dart
  /// stepCounter.watchTotalSteps().listen((total) {
  ///   print('Total steps: $total');
  /// });
  /// ```
  Stream<int> watchTotalSteps({DateTime? from, DateTime? to}) {
    _ensureLoggingInitialized();
    return _stepLogDatabase.watchTotalSteps(from: from, to: to);
  }

  /// Watch all step logs in real-time
  ///
  /// Emits updates whenever logs are added or modified.
  ///
  /// Example:
  /// ```dart
  /// stepCounter.watchStepLogs().listen((logs) {
  ///   for (final log in logs) {
  ///     print('${log.stepCount} steps from ${log.source}');
  ///   }
  /// });
  /// ```
  Stream<List<StepLogEntry>> watchStepLogs({
    DateTime? from,
    DateTime? to,
    StepLogSource? source,
  }) {
    _ensureLoggingInitialized();
    return _stepLogDatabase.watchStepLogs(from: from, to: to, source: source);
  }

  /// Get step statistics for a date range
  ///
  /// Returns a map with various statistics including:
  /// - totalSteps, entryCount, averagePerEntry, averagePerDay
  /// - foregroundSteps, backgroundSteps, terminatedSteps
  ///
  /// Example:
  /// ```dart
  /// final stats = await stepCounter.getStepStats();
  /// print('Total: ${stats['totalSteps']}');
  /// print('Daily average: ${stats['averagePerDay']}');
  /// ```
  Future<Map<String, dynamic>> getStepStats({
    DateTime? from,
    DateTime? to,
  }) async {
    _ensureLoggingInitialized();
    return await _stepLogDatabase.getStepStats(from: from, to: to);
  }

  /// Clear all step logs
  ///
  /// Use with caution - this permanently deletes all logged data.
  Future<void> clearStepLogs() async {
    _ensureLoggingInitialized();
    await _stepLogDatabase.clearLogs();
    dev.log('AccurateStepCounter: All step logs cleared');
  }

  /// Delete step logs older than a specific date
  ///
  /// Example:
  /// ```dart
  /// // Delete logs older than 30 days
  /// await stepCounter.deleteStepLogsBefore(
  ///   DateTime.now().subtract(Duration(days: 30)),
  /// );
  /// ```
  Future<void> deleteStepLogsBefore(DateTime date) async {
    _ensureLoggingInitialized();
    await _stepLogDatabase.deleteLogsBefore(date);
    dev.log('AccurateStepCounter: Deleted logs before $date');
  }

  /// Ensure logging is initialized, throw if not
  void _ensureLoggingInitialized() {
    if (!_loggingInitialized) {
      throw StateError(
        'Logging not initialized. Call initializeLogging() first.',
      );
    }
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

      // Log terminated steps to database if logging is enabled
      await _logTerminatedSteps(missedSteps, startTime, endTime);

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
