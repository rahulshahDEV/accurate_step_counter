import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'models/step_count_event.dart';
import 'models/step_detector_config.dart';
import 'models/step_record.dart';
import 'models/step_record_config.dart';
import 'models/step_record_source.dart';
import 'models/step_runtime_state.dart';
import 'models/terminated_sync_gap.dart';
import 'platform/step_counter_platform.dart';
import 'services/native_step_detector.dart';
import 'services/sensors_step_detector.dart';
import 'services/step_record_store.dart';

/// Implementation of the AccurateStepCounter plugin
///
/// This class provides the core functionality for accurate step counting
/// using native Android step detection with optional foreground service.
///
/// Includes:
/// - Real-time step counting
/// - Aggregated logging with SQLite
/// - Warmup validation logic for noise filtering
/// - Foreground service management
/// - Terminated state step recovery

/// Helper class for buffered writes
class PendingStep {
  final int stepCount;
  final DateTime fromTime;
  final DateTime toTime;
  final StepRecordSource source;
  final double confidence;

  PendingStep({
    required this.stepCount,
    required this.fromTime,
    required this.toTime,
    required this.source,
    required this.confidence,
  });
}

class AccurateStepCounterImpl with WidgetsBindingObserver {
  AccurateStepCounterImpl()
    : _platform = StepCounterPlatform.instance,
      _now = DateTime.now,
      _isAndroid = Platform.isAndroid;

  @visibleForTesting
  AccurateStepCounterImpl.testing({
    required StepCounterPlatform platform,
    required DateTime Function() now,
  }) : _platform = platform,
       _now = now,
       _isAndroid = true;

  final DateTime Function() _now;
  final bool _isAndroid;
  Future<void>? _startTrackingInFlight;
  Future<void>? _rotationInFlight;
  Future<void>? _dayRolloverInFlight;
  Map<String, dynamic>? _pendingNativeRotation;
  Future<void> _loggingQueue = Future<void>.value();
  Future<void>? _writeFlushInFlight;
  Future<void> _nativeEventQueue = Future<void>.value();
  Future<void> _externalWriteChain = Future<void>.value();
  DateTime? _sessionDay;
  Timer? _dayBoundaryTimer;
  bool _observingLifecycle = false;
  bool _disposed = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setAppState(state);

  final NativeStepDetector _nativeDetector = NativeStepDetector();
  final StepCounterPlatform _platform;

  StepDetectorConfig? _currentConfig;
  bool _isStarted = false;
  bool _useForegroundService = false;
  final StreamController<StepCountEvent> _foregroundStepController =
      StreamController<StepCountEvent>.broadcast();
  int _lastForegroundStepCount = 0;

  // Sensors plus step detector for foreground service mode
  SensorsStepDetector? _sensorsStepDetector;
  StreamSubscription<StepCountEvent>? _sensorsStepSubscription;

  // Branch-style native step service mode
  bool _useNativeStepService = false;
  StreamSubscription<int>? _nativeServiceStepSubscription;

  // Step recording
  StepRecordStore? _stepRecordStore;
  bool _recordingEnabled = false;
  bool _storeInitialized = false;
  bool _useBackgroundIsolate = false;
  bool _debugLogging = false;
  bool _performanceTracing = false;
  StepRuntimeState _runtimeState = StepRuntimeState.uninitialized;
  StreamSubscription<StepCountEvent>? _stepRecordSubscription;
  DateTime? _lastRecordTime;
  int _lastRecordedStepCount = 0;

  // App lifecycle state tracking for proper source detection
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  int _recordIntervalMs = 5000;

  // Aggregated mode tracking
  bool _aggregatedModeEnabled = false;

  /// Steps loaded from database at initialization (today's stored steps)
  int _aggregatedStoredSteps = 0;

  /// Steps counted in current session (since last init/restart)
  int _currentSessionSteps = 0;

  /// Base step count from native detector at session start
  int _sessionBaseStepCount = 0;
  final StreamController<int> _aggregatedStepController =
      StreamController<int>.broadcast();

  // Warmup validation state
  bool _isInWarmup = false;
  DateTime? _warmupStartTime;
  int _warmupDurationMs = 0;
  int _minStepsToValidate = 10;
  double _maxStepsPerSecond = 5.0;
  int _warmupStartStepCount = 0;

  // Sliding window validation state
  DateTime? _lastWarmupCheckTime;
  int _warmupWindowStartStepCount = 0;

  // Inactivity timeout tracking
  int _inactivityTimeoutMs = 0;
  Timer? _inactivityTimer;

  // Write lock to prevent concurrent writeStepsToAggregated calls
  // This prevents race conditions where multiple writes happen before duplicate check completes
  final List<PendingStep> _writeBuffer = [];
  Timer? _writeBufferFlushTimer;

  // Track last external write to detect near-duplicate writes
  DateTime? _lastExternalWriteTime;
  int? _lastExternalWriteSteps;
  DateTime? _lastExternalWriteFromTime;

  // Terminated-sync single-flight and session-level dedupe.
  Future<Map<String, dynamic>?>? _terminatedSyncInFlight;
  final Set<String> _processedTerminatedGapKeys = <String>{};

  // Stream emission throttling for low-end device optimization
  // Limits UI updates to max 10Hz instead of 50Hz
  DateTime? _lastStreamEmitTime;
  static const _minStreamEmitInterval = Duration(milliseconds: 100);

  /// Callback for handling missed steps from terminated state
  /// Parameters: (missedSteps, startTime, endTime)
  Function(int, DateTime, DateTime)? onTerminatedStepsDetected;

  /// Whether step logging to local database is enabled
  bool get isLoggingEnabled => _recordingEnabled;

  /// Whether the step log database has been initialized
  bool get isLoggingInitialized => _storeInitialized;

  /// Current app lifecycle state (used for source detection)
  AppLifecycleState get appLifecycleState => _appLifecycleState;

  /// Whether the app is currently in the foreground
  bool get isAppInForeground => _appLifecycleState == AppLifecycleState.resumed;

  StepRuntimeState _activeRuntimeState() {
    return isAppInForeground
        ? StepRuntimeState.detectingForeground
        : StepRuntimeState.detectingBackground;
  }

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

  /// Current detector count: today's total for the hardware service, or a
  /// session count for legacy detectors.
  int get currentStepCount {
    if (_useForegroundService) {
      return _lastForegroundStepCount;
    }
    return _nativeDetector.stepCount;
  }

  /// Whether the step counter is currently active
  bool get isStarted => _isStarted;

  /// Current runtime state of the step counter engine.
  StepRuntimeState get runtimeState => _runtimeState;

  /// Whether foreground service mode is being used
  bool get isUsingForegroundService => _useForegroundService;

  /// Whether native hardware step detector is being used
  Future<bool> isUsingNativeDetector() =>
      _nativeDetector.isUsingHardwareDetector();

  /// Whether the native step service (TYPE_STEP_COUNTER foreground service) is being used.
  ///
  /// This is the recommended detection mode on Android — uses the hardware
  /// TYPE_STEP_COUNTER sensor via a foreground service for reliable
  /// background counting.
  bool get isUsingNativeStepService => _useNativeStepService;

  /// Check whether the native step service is currently running on the device.
  ///
  /// This queries the actual Android service state, not just the Dart-side flag.
  /// Use this to verify the service survived OEM battery optimization.
  ///
  /// Example:
  /// ```dart
  /// final running = await stepCounter.isNativeStepServiceRunning();
  /// if (!running) {
  ///   // Service was killed, restart it
  ///   await stepCounter.start();
  /// }
  /// ```
  Future<bool> isNativeStepServiceRunning() =>
      _platform.isNativeStepServiceRunning();

  /// Set native service notification display only (does not poison sensor baseline).
  Future<void> setNativeNotificationDisplay(int value) =>
      _platform.setNotificationDisplay(value);

  /// Force-update native today steps (mutates offset — prefer notification display).
  Future<void> forceUpdateNativeTodaySteps(int value) =>
      _platform.forceUpdateTodaySteps(value);

  /// Consume last native midnight rotation stamp (idempotent clear-on-read).
  Future<Map<String, dynamic>?> consumeNativeLastRotation() =>
      _platform.consumeLastRotation();

  /// Clear all native step state (logout / account switch).
  Future<void> resetNativeStepState() async {
    if (_isStarted) await stop();
    await _platform.resetNativeStepState();
    _lastForegroundStepCount = 0;
    final now = _now();
    final stored = _storeInitialized
        ? await _stepRecordStore!.readTotalSteps(
            from: DateTime(now.year, now.month, now.day),
            to: now,
          )
        : 0;

    _aggregatedStoredSteps = stored;
    _currentSessionSteps = 0;
    _sessionBaseStepCount = 0;
    _lastRecordedStepCount = 0;
    _pendingNativeRotation = null;
  }

  /// Start step detection
  ///
  /// On Android, prefers the hardware TYPE_STEP_COUNTER foreground service
  /// on all supported API levels. Devices without a counter sensor can use
  /// [NativeStepDetector] or the explicitly enabled accelerometer fallback.
  ///
  /// [config] - Optional configuration for step detection sensitivity
  ///
  /// Throws [StateError] if already started
  Future<void> start({StepDetectorConfig? config}) async {
    if (_disposed) throw StateError('Create a new counter after dispose().');
    if (!_isAndroid) {
      throw UnsupportedError('Step tracking requires Android API 24 or newer.');
    }
    if (!await _platform.hasPermission()) {
      throw StateError(
        'Grant ACTIVITY_RECOGNITION before starting step tracking.',
      );
    }
    await _ensureCurrentDay();
    if (_isStarted) {
      throw StateError('Step counter is already started');
    }

    final sw = Stopwatch()..start();
    _setRuntimeState(StepRuntimeState.starting, reason: 'startCalled');
    try {
      _currentConfig = config ?? const StepDetectorConfig();
      _useForegroundService = false;
      _useNativeStepService = false;

      if (_isAndroid) {
        await _traceAsync('start.platformInitialize', () async {
          await _platform.initialize();
          return;
        });

        // Primary path (all Android 24+): TYPE_STEP_COUNTER FGS
        final hasSensor = await _traceAsync(
          'start.hasNativeStepSensor',
          _platform.hasNativeStepSensor,
        );

        // Legacy terminated-prefs sync only when the native FGS cannot run.
        // When TYPE_STEP_COUNTER service is available it is the source of truth
        // (own prefs + reboot/midnight recovery) — dual sync caused double fills.
        if (!hasSensor && _currentConfig!.enableOsLevelSync) {
          await _traceAsync('start.syncTerminatedSteps', () async {
            await _syncStepsFromTerminatedState();
            return;
          });
        }

        if (hasSensor) {
          await _platform.configureNativeStepService(
            maxStepsPerMinute: _currentConfig!.nativeMaxStepsPerMinute,
            maxStepsPerHour: _currentConfig!.nativeMaxStepsPerHour,
          );
          final nativeServiceStarted = await _traceAsync(
            'start.startNativeStepService',
            _platform.startNativeStepService,
          );

          if (nativeServiceStarted) {
            _useNativeStepService = true;
            _useForegroundService = true;
            _lastForegroundStepCount = await _platform.getNativeTodaySteps();

            // Safe calibration: seed offset from SQLite today only when
            // sensor baseline is unset and stored steps are sane (≤40k).
            await _traceAsync('start.calibrateIfNeeded', () async {
              await _calibrateNativeServiceIfNeeded();
              return;
            });

            _nativeServiceStepSubscription = _platform.nativeStepServiceStream
                .listen(
                  (steps) {
                    _queueNativeSteps(steps);
                  },
                  onError: (error) {
                    _log('native step service stream error: $error');
                  },
                );

            // Catch midnight rollover that happened while app was dead
            await _drainNativeRotation();

            _isStarted = true;
            _setRuntimeState(_activeRuntimeState(), reason: 'startComplete');
            _logPerf('start.total took ${sw.elapsedMilliseconds}ms');
            return;
          }

          throw StateError(
            'The Android step service could not start. Start tracking while the app is visible and check activity permission.',
          );
        }

        // Optional legacy FGS + sensors_plus for old devices when config asks
        final androidVersion = await _platform.getAndroidVersion();
        final maxApiLevel = _currentConfig!.foregroundServiceMaxApiLevel;
        if (_currentConfig!.useForegroundServiceOnOldDevices &&
            androidVersion > 0 &&
            androidVersion <= maxApiLevel) {
          _log('Fallback: sensors_plus + legacy FGS for API ≤$maxApiLevel');
          _useForegroundService = true;

          await _traceAsync('start.startForegroundService', () async {
            await _platform.startForegroundService(
              title: _currentConfig!.foregroundNotificationTitle,
              text: _currentConfig!.foregroundNotificationText,
            );
            return;
          });

          final sensorsThreshold = _normalizeThresholdForSensors(
            _currentConfig!.threshold,
          );
          _sensorsStepDetector = SensorsStepDetector(
            threshold: sensorsThreshold,
            filterAlpha: _currentConfig!.filterAlpha,
            minTimeBetweenStepsMs: _currentConfig!.minTimeBetweenStepsMs,
            debugLogging: _debugLogging,
          );
          await _sensorsStepDetector!.start();
          _sensorsStepSubscription = _sensorsStepDetector!.stepEventStream
              .listen(
                (event) {
                  _lastForegroundStepCount = event.stepCount;
                  if (!_foregroundStepController.isClosed) {
                    _foregroundStepController.add(event);
                  }
                  _platform.updateForegroundStepCount(event.stepCount);
                },
                onError: (error) {
                  _log('sensors_plus error: $error');
                },
              );

          _isStarted = true;
          _setRuntimeState(_activeRuntimeState(), reason: 'startComplete');
          _logPerf('start.total took ${sw.elapsedMilliseconds}ms');
          return;
        }

        // Last fallback: NativeStepDetector (TYPE_STEP_DETECTOR / accel)
        await _traceAsync('start.nativeDetectorStart', () async {
          await _nativeDetector.start(config: _currentConfig);
          return;
        });

        _isStarted = true;
        _setRuntimeState(_activeRuntimeState(), reason: 'startComplete');
        _logPerf('start.total took ${sw.elapsedMilliseconds}ms');
        return;
      }
    } catch (_) {
      _setRuntimeState(StepRuntimeState.error, reason: 'startFailed');
      rethrow;
    }
  }

  Future<void> _queueNativeSteps(int steps) {
    return _nativeEventQueue = _nativeEventQueue
        .then((_) async {
          await _drainNativeRotation();
          await _ensureCurrentDay();
          // Log only sensor-source counts. A stored/display floor must never
          // flow back through this stream as if it were new physical steps.
          if (steps < 0) return;
          _lastForegroundStepCount = steps;
          if (!_foregroundStepController.isClosed) {
            _foregroundStepController.add(
              StepCountEvent(stepCount: steps, timestamp: _now().toUtc()),
            );
          }
        })
        .catchError((Object error, StackTrace stack) {
          _log('Native event processing failed: $error');
        });
  }

  /// Seed native offset from SQLite today when calibration needed.
  Future<void> _calibrateNativeServiceIfNeeded() async {
    try {
      final sensorToday = await _platform.getNativeTodaySteps();
      if (sensorToday > 0) return;

      if (!_storeInitialized || _stepRecordStore == null) return;

      final now = _now();
      final storedToday = await _readNativeStoredSteps(
        DateTime(now.year, now.month, now.day),
        now,
      );
      if (storedToday <= 0 || storedToday > 80000) return;

      await _platform.setNativeInitialOffset(storedToday);
      _lastForegroundStepCount = storedToday;
      _log('Calibrated native offset from SQLite today=$storedToday');
    } catch (e) {
      _log('Calibration skipped: $e');
    }
  }

  /// Count native-tagged records independently from imported external records.
  Future<int> _readNativeStoredSteps(DateTime start, DateTime end) {
    // A single aggregate query avoids mixing snapshots if an import commits
    // while native recovery is reading the same day's records.
    return _stepRecordStore!.readTotalSteps(
      from: start,
      to: end,
      excludeSource: StepRecordSource.external,
    );
  }

  /// Drain and persist native historical counts without consuming external imports.
  Future<void> _drainNativeRotation() {
    return _rotationInFlight ??= _performRotationDrain().whenComplete(() {
      _rotationInFlight = null;
    });
  }

  Future<void> _performRotationDrain() async {
    await _ensureCurrentDay();
    _pendingNativeRotation ??= await _platform.consumeLastRotation();
    final rotation = _pendingNativeRotation;
    if (rotation == null || !_storeInitialized) return;
    final previousToday = rotation['previousToday'] as int? ?? 0;
    final anchor = _parseRotationDate(rotation['date'] as String? ?? '');
    if (anchor == null || previousToday <= 0) {
      _pendingNativeRotation = null;
      return;
    }
    final previous =
        _parseRotationDate(rotation['previousDate'] as String? ?? '') ??
        DateTime(anchor.year, anchor.month, anchor.day - 1);
    final start = DateTime(previous.year, previous.month, previous.day);
    final end = DateTime(previous.year, previous.month, previous.day + 1);
    final existing = await _readNativeStoredSteps(
      start,
      end.subtract(const Duration(milliseconds: 1)),
    );
    if (previousToday > existing) {
      await _safeInsertRecord(
        StepRecord(
          stepCount: previousToday - existing,
          fromTime: start,
          toTime: end,
          source: StepRecordSource.terminated,
          confidence: 1.0,
          idempotencyKey:
              'native_rotation|${start.toIso8601String()}|$previousToday',
        ),
      );
    }
    _pendingNativeRotation = null;
  }

  Future<void> _ensureCurrentDay() {
    return _dayRolloverInFlight ??= _performDayRollover().whenComplete(() {
      _dayRolloverInFlight = null;
    });
  }

  Future<void> _performDayRollover() async {
    final now = _now();
    final day = DateTime(now.year, now.month, now.day);
    if (_sessionDay == day) return;
    if (_sessionDay == null) {
      _sessionDay = day;
      return;
    }
    await _loggingQueue;
    await _flushWriteBuffer();
    _sessionDay = day;
    final stored = _storeInitialized
        ? await _stepRecordStore!.readTotalSteps(from: day, to: now)
        : 0;
    _aggregatedStoredSteps = stored;
    _currentSessionSteps = 0;
    _sessionBaseStepCount = 0;
    _lastRecordedStepCount = 0;
    _lastRecordTime = day.toUtc();
    _lastForegroundStepCount = 0;

    _lastStreamEmitTime = null;
    _resetWarmupState();
    _emitAggregatedCount(stored);
    if (!_foregroundStepController.isClosed) {
      _foregroundStepController.add(
        StepCountEvent(stepCount: 0, timestamp: now.toUtc()),
      );
    }
  }

  void _scheduleDayBoundary() {
    _dayBoundaryTimer?.cancel();
    final now = _now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _dayBoundaryTimer = Timer(next.difference(now), () async {
      try {
        await _ensureCurrentDay();
        if (_useNativeStepService) await _drainNativeRotation();
      } catch (error) {
        _log('Day rollover failed: $error');
      } finally {
        if (_recordingEnabled) _scheduleDayBoundary();
      }
    });
  }

  /// Stop step detection
  ///
  /// Flushes logging and stops the detector/service while preserving history.
  /// Clear history and native state explicitly for logout or an account switch.
  ///
  /// Example:
  /// ```dart
  /// await stepCounter.stop();
  /// print('Stopped at: ${stepCounter.currentStepCount} steps');
  /// ```
  Future<void> stop() async {
    try {
      await _startTrackingInFlight;
    } catch (_) {
      // Startup reports its own failure; stop still releases partial resources.
    }
    await _stopInternal();
  }

  Future<void> _stopInternal() async {
    if (_recordingEnabled) await stopLogging();
    if (!_isStarted) {
      return;
    }

    _setRuntimeState(StepRuntimeState.stopping, reason: 'stopCalled');
    try {
      if (_useForegroundService) {
        if (_useNativeStepService) {
          await _nativeServiceStepSubscription?.cancel();
          _nativeServiceStepSubscription = null;
          await _nativeEventQueue;
          await _platform.stopNativeStepService();
          _useNativeStepService = false;
        } else {
          // Stop sensors_plus step detection
          await _sensorsStepSubscription?.cancel();
          _sensorsStepSubscription = null;
          await _sensorsStepDetector?.stop();
          _sensorsStepDetector = null;
          await _platform.stopForegroundService();
        }

        _useForegroundService = false;
      } else {
        await _nativeDetector.stop();
      }

      _isStarted = false;
      _setRuntimeState(StepRuntimeState.stopped, reason: 'stopComplete');
    } catch (_) {
      _setRuntimeState(StepRuntimeState.error, reason: 'stopFailed');
      rethrow;
    }
  }

  /// Reset a legacy session detector to zero.
  ///
  /// Hardware service counts are persisted daily totals. Use [stop],
  /// [clearStepLogs], and [resetNativeStepState] to clear those totals explicitly.
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
  @Deprecated(
    'For daily hardware totals use stop(), clearStepLogs(), and resetNativeStepState().',
  )
  void reset() {
    if (_useNativeStepService) {
      throw UnsupportedError(
        'Clear hardware daily totals with stop(), clearStepLogs(), and resetNativeStepState().',
      );
    }
    if (_useForegroundService) {
      _platform.resetForegroundStepCount();
      _sensorsStepDetector?.reset();
      _lastForegroundStepCount = 0;
    } else {
      _nativeDetector.resetStepCount();
    }
  }

  /// Normalize threshold for SensorsStepDetector
  ///
  /// The NativeStepDetector uses raw accelerometer magnitude thresholds,
  /// typically in the 10-20 range. SensorsStepDetector uses magnitude
  /// DIFFERENCE thresholds, which are much smaller (0.5-2.0 range).
  ///
  /// This method normalizes thresholds that appear to be in native scale
  /// down to the sensors_plus scale.
  double _normalizeThresholdForSensors(double threshold) {
    // If threshold is already in sensors_plus range, use it as-is
    if (threshold <= 5.0) {
      return threshold;
    }

    // Normalize high thresholds (native detector scale) to sensors_plus scale
    // Native thresholds are typically 10-20, sensors_plus expects 0.5-2.0
    // Using a scaling factor of 10 to convert
    final normalized = threshold / 10.0;

    // Clamp to sensible range for sensors_plus (0.5 - 2.0)
    return normalized.clamp(0.5, 2.0);
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

  /// Check if TYPE_STEP_COUNTER sensor exists for native service mode.
  Future<bool> hasNativeStepServiceSensor() async {
    return await _platform.hasNativeStepSensor();
  }

  /// Native service today step count (Android only).
  Future<int> getNativeServiceTodaySteps() async {
    return await _platform.getNativeTodaySteps();
  }

  /// Native service yesterday step count (Android only).
  Future<int> getNativeServiceYesterdaySteps() async {
    return await _platform.getNativeYesterdaySteps();
  }

  /// Native service battery optimization state (Android only).
  Future<bool> isNativeServiceBatteryOptimized() async {
    return await _platform.isBatteryOptimized();
  }

  /// Open battery optimization settings for native service mode.
  Future<bool> requestNativeServiceBatteryOptimizationExclusion() async {
    return await _platform.requestBatteryOptimization();
  }

  /// Whether the OS is restricting this app via battery optimization.
  ///
  /// Short alias for [isNativeServiceBatteryOptimized].
  Future<bool> isBatteryOptimized() => isNativeServiceBatteryOptimized();

  /// Prompt the user to exclude this app from battery optimization.
  ///
  /// Short alias for [requestNativeServiceBatteryOptimizationExclusion].
  Future<bool> requestBatteryOptimization() =>
      requestNativeServiceBatteryOptimizationExclusion();

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
    if (_disposed) return;
    try {
      await _startTrackingInFlight;
    } catch (_) {}
    _disposed = true;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    _dayBoundaryTimer?.cancel();
    // Stop logging first so buffered SQLite writes flush and the periodic
    // flush timer cannot hit a closed store.
    if (_recordingEnabled || _writeBuffer.isNotEmpty) {
      await stopLogging();
    } else {
      _writeBufferFlushTimer?.cancel();
      _writeBufferFlushTimer = null;
    }

    await stop();
    await _nativeDetector.dispose();
    await _nativeServiceStepSubscription?.cancel();
    _nativeServiceStepSubscription = null;
    _useNativeStepService = false;
    await _sensorsStepDetector?.dispose();
    _sensorsStepDetector = null;
    await _stepRecordSubscription?.cancel();
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    await _foregroundStepController.close();
    await _aggregatedStepController.close();
    await _stepRecordStore?.close();
    _stepRecordStore = null;
    _storeInitialized = false;
    _currentConfig = null;
    _setRuntimeState(StepRuntimeState.uninitialized, reason: 'disposed');
  }

  // ============================================================
  // Simplified API (recommended for most apps)
  // ============================================================

  /// One-shot setup: database → TYPE_STEP_COUNTER FGS → aggregated logging.
  ///
  /// This is the recommended entry point for Flutter apps. After permissions:
  ///
  /// ```dart
  /// final steps = AccurateStepCounter();
  /// await steps.startTracking();
  /// steps.watchTodaySteps().listen(print);
  /// ```
  ///
  /// Order is fixed so calibration and native↔SQLite reconcile work.
  /// Prefer this over calling [initializeLogging], [start], [startLogging]
  /// separately.
  Future<void> startTracking({
    bool useBackgroundIsolate = true,
    bool debugLogging = false,
    bool performanceTracing = false,
    StepDetectorConfig? detectorConfig,
    StepRecordConfig? loggingConfig,
  }) {
    if (_disposed) {
      return Future.error(StateError('Create a new counter after dispose().'));
    }
    if (_startTrackingInFlight != null) return _startTrackingInFlight!;
    return _startTrackingInFlight = _startTracking(
      useBackgroundIsolate: useBackgroundIsolate,
      debugLogging: debugLogging,
      performanceTracing: performanceTracing,
      detectorConfig: detectorConfig,
      loggingConfig: loggingConfig,
    ).whenComplete(() => _startTrackingInFlight = null);
  }

  Future<void> _startTracking({
    required bool useBackgroundIsolate,
    required bool debugLogging,
    required bool performanceTracing,
    StepDetectorConfig? detectorConfig,
    StepRecordConfig? loggingConfig,
  }) async {
    if (!_isAndroid) {
      throw UnsupportedError('Step tracking requires Android API 24 or newer.');
    }
    if (!await _platform.hasPermission()) {
      if (_isStarted) await _stopInternal();
      throw StateError(
        'Grant ACTIVITY_RECOGNITION before starting step tracking.',
      );
    }
    if (_isStarted && _recordingEnabled) {
      if (!_useNativeStepService ||
          await _platform.isNativeStepServiceRunning()) {
        return;
      }
      await _stopInternal();
    }
    try {
      await initializeLogging(
        debugLogging: debugLogging,
        useBackgroundIsolate: useBackgroundIsolate,
        performanceTracing: performanceTracing,
      );
      if (!_isStarted) await start(config: detectorConfig);
      await startLogging(
        config:
            loggingConfig ??
            StepRecordConfig.aggregated(
              useBackgroundIsolate: useBackgroundIsolate,
            ),
      );
      if (!_observingLifecycle) {
        WidgetsBinding.instance.addObserver(this);
        _observingLifecycle = true;
      }
    } catch (_) {
      if (_isStarted) await _stopInternal();
      _setRuntimeState(StepRuntimeState.error, reason: 'startTrackingFailed');
      rethrow;
    }
  }

  /// Alias for [startTracking] (kept for older docs / call sites).
  Future<void> initSteps({
    bool debugLogging = false,
    bool performanceTracing = false,
  }) {
    return startTracking(
      debugLogging: debugLogging,
      performanceTracing: performanceTracing,
    );
  }

  /// Get today's step count (since midnight)
  ///
  /// Returns the best available total: `max(SQLite, native FGS today)` when
  /// the hardware service is active, so process-death gaps are not lost.
  ///
  /// Works even if step detection is not currently active.
  ///
  /// Example:
  /// ```dart
  /// final todaySteps = await stepCounter.getTodayStepCount();
  /// print('Steps today: $todaySteps');
  /// ```
  Future<int> getTodayStepCount() async {
    _ensureLoggingInitialized();
    await _ensureCurrentDay();
    await _flushPendingWritesIfNeeded();
    final now = _now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final sqlite = await _stepRecordStore!.readTotalSteps(
      from: startOfToday,
      to: now,
    );
    if (_useNativeStepService) {
      final native = await _platform.getNativeTodaySteps();
      final merged = native > sqlite ? native : sqlite;

      return merged;
    }

    return sqlite;
  }

  /// Alias for [getTodayStepCount].
  Future<int> getTodaySteps() => getTodayStepCount();

  /// Get yesterday's step count
  ///
  /// Returns the total steps recorded yesterday (full 24-hour period).
  /// Prefers native yesterday when the FGS is active and higher than SQLite.
  ///
  /// Example:
  /// ```dart
  /// final yesterdaySteps = await stepCounter.getYesterdayStepCount();
  /// print('Steps yesterday: $yesterdaySteps');
  /// ```
  Future<int> getYesterdayStepCount() async {
    _ensureLoggingInitialized();
    await _flushPendingWritesIfNeeded();
    final now = _now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = DateTime(now.year, now.month, now.day - 1);
    final sqlite = await _stepRecordStore!.readTotalSteps(
      from: startOfYesterday,
      to: startOfToday.subtract(const Duration(milliseconds: 1)),
    );
    if (_useNativeStepService) {
      final native = await _platform.getNativeYesterdaySteps();
      return native > sqlite ? native : sqlite;
    }
    return sqlite;
  }

  /// Alias for [getYesterdayStepCount].
  Future<int> getYesterdaySteps() => getYesterdayStepCount();

  /// Get step count for a custom date range
  ///
  /// [start] - Start of the date range (will be set to midnight)
  /// [end] - End of the date range (will be set to end of day or now if today)
  ///
  /// Example:
  /// ```dart
  /// // Get steps for last 7 days
  /// final weekSteps = await stepCounter.getStepCount(
  ///   start: DateTime.now().subtract(Duration(days: 7)),
  ///   end: DateTime.now(),
  /// );
  /// ```
  Future<int> getStepCount({
    required DateTime start,
    required DateTime end,
  }) async {
    _ensureLoggingInitialized();
    await _flushPendingWritesIfNeeded();

    // Set start to midnight of start date
    final startMidnight = DateTime(start.year, start.month, start.day);

    // Set end to midnight of end date, or now if end is today
    final now = _now();
    final endMidnight = DateTime(end.year, end.month, end.day);
    final isEndToday =
        endMidnight.year == now.year &&
        endMidnight.month == now.month &&
        endMidnight.day == now.day;

    final endTime = isEndToday ? now : endMidnight.add(const Duration(days: 1));

    return await _stepRecordStore!.readTotalSteps(
      from: startMidnight,
      to: endTime,
    );
  }

  /// Watch today's step count in real-time
  ///
  /// Returns a stream that emits the current total immediately,
  /// then updates whenever new steps are logged or received from native service.
  ///
  /// Example:
  /// ```dart
  /// stepCounter.watchTodaySteps().listen((steps) {
  ///   print('Steps today: $steps');
  /// });
  /// ```
  Stream<int> watchTodaySteps() {
    _ensureLoggingInitialized();
    late StreamController<int> controller;
    StreamSubscription<void>? sqliteSub;
    StreamSubscription<StepCountEvent>? eventSub;
    Future<void> refreshQueue = Future<void>.value();
    int? lastEmitted;

    void refresh() {
      refreshQueue = refreshQueue
          .then((_) async {
            await _ensureCurrentDay();
            final now = _now();
            final stored = await _stepRecordStore!.readTotalSteps(
              from: DateTime(now.year, now.month, now.day),
              to: now,
            );
            final current = _now();
            if (DateTime(current.year, current.month, current.day) !=
                DateTime(now.year, now.month, now.day)) {
              refresh();
              return;
            }

            var total = stored;
            if (_useNativeStepService && _lastForegroundStepCount > total) {
              total = _lastForegroundStepCount;
            }
            if (_aggregatedModeEnabled && aggregatedStepCount > total) {
              total = aggregatedStepCount;
            }

            if (!controller.isClosed && total != lastEmitted) {
              lastEmitted = total;
              controller.add(total);
            }
          })
          .catchError((Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          });
    }

    controller = StreamController<int>(
      onListen: () {
        // Subscribe before the initial query so no write can fall in a gap.
        // The query uses the current date each time, including after midnight.
        sqliteSub = _stepRecordStore!.recordChanges.listen((_) => refresh());
        eventSub = stepEventStream.listen(
          (_) => refresh(),
          onDone: () => unawaited(controller.close()),
        );
        refresh();
      },
      onCancel: () async {
        await sqliteSub?.cancel();
        await eventSub?.cancel();
      },
    );
    return controller.stream;
  }

  // ============================================================
  // Step Logging API (Advanced - Health Connect-like)
  // ============================================================

  /// Initialize the step logging database
  ///
  /// Must be called before using any logging features. Can be called
  /// multiple times safely - subsequent calls are no-ops.
  ///
  /// [debugLogging] - If true, logs debug messages to console. Default: false.
  /// Set to `kDebugMode` to only log in debug builds.
  ///
  /// Example:
  /// ```dart
  /// import 'package:flutter/foundation.dart';
  ///
  /// await stepCounter.initializeLogging(debugLogging: kDebugMode);
  /// await stepCounter.start();
  /// ```
  ///
  /// [useBackgroundIsolate] - When true, database operations run in a background
  /// isolate to prevent UI blocking on low-end devices. Default: false.
  /// Note: This can also be set via [StepRecordConfig.useBackgroundIsolate] when
  /// calling [startLogging]. The value from [startLogging] takes precedence.
  Future<void> initializeLogging({
    bool debugLogging = false,
    bool useBackgroundIsolate = false,
    bool performanceTracing = false,
  }) async {
    if (_disposed) throw StateError('Create a new counter after dispose().');
    if (_storeInitialized) {
      _debugLogging = _debugLogging || debugLogging;
      _performanceTracing = _performanceTracing || performanceTracing;
      if (!_isStarted) {
        _setRuntimeState(
          StepRuntimeState.initialized,
          reason: 'initializeLoggingAlreadyInitialized',
        );
      }
      return;
    }

    _setRuntimeState(
      StepRuntimeState.initializing,
      reason: 'initializeLoggingStart',
    );

    try {
      _debugLogging = debugLogging;
      _performanceTracing = performanceTracing;
      _useBackgroundIsolate = useBackgroundIsolate;
      _stepRecordStore = StepRecordStore(
        useIsolate: useBackgroundIsolate,
        performanceTracing: _performanceTracing,
      );
      await _traceAsync('initializeLogging.storeInit', () async {
        await _stepRecordStore!.initialize();
        return;
      });
      _storeInitialized = true;
      _log('Logging database initialized (isolate: $useBackgroundIsolate)');
      if (!_isStarted) {
        _setRuntimeState(
          StepRuntimeState.initialized,
          reason: 'initializeLoggingComplete',
        );
      }
    } catch (_) {
      _setRuntimeState(
        StepRuntimeState.error,
        reason: 'initializeLoggingFailed',
      );
      rethrow;
    }
  }

  /// Internal logging helper - only logs if debugLogging is enabled
  void _log(String message) {
    if (_debugLogging) {
      dev.log('AccurateStepCounter: $message');
    }
  }

  void _setRuntimeState(StepRuntimeState nextState, {String? reason}) {
    if (_runtimeState == nextState) return;
    final previous = _runtimeState;
    _runtimeState = nextState;
    final reasonSuffix = reason == null ? '' : ' ($reason)';
    _log('Runtime state: $previous -> $nextState$reasonSuffix');
  }

  /// Performance logging helper for ANR diagnostics.
  void _logPerf(String message) {
    if (_performanceTracing) {
      dev.log('AccurateStepCounter[perf]: $message');
    }
  }

  /// Measure async operation duration when performance tracing is enabled.
  Future<T> _traceAsync<T>(String label, Future<T> Function() operation) async {
    if (!_performanceTracing) {
      return operation();
    }
    final sw = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      _logPerf('$label took ${sw.elapsedMilliseconds}ms');
    }
  }

  /// Emit aggregated step count to stream with throttling
  ///
  /// This method limits stream emissions to max 10Hz (100ms minimum interval)
  /// to reduce UI rebuilds on low-end devices. The latest value is always
  /// stored and will be emitted on the next allowed interval.
  void _emitAggregatedCount(int count) {
    if (_aggregatedStepController.isClosed) return;

    final now = _now();

    if (_lastStreamEmitTime == null ||
        now.difference(_lastStreamEmitTime!) >= _minStreamEmitInterval) {
      _aggregatedStepController.add(count);
      _lastStreamEmitTime = now;
    }
  }

  /// Flush pending buffered writes before read APIs that expect fresh data.
  Future<void> _flushPendingWritesIfNeeded() async {
    await _nativeEventQueue;
    await _loggingQueue;
    if (_aggregatedModeEnabled && _writeBuffer.isNotEmpty) {
      await _flushWriteBuffer();
    }
  }

  /// Start auto-logging steps to the local database
  ///
  /// Call [initializeLogging] first. Steps will be logged automatically
  /// as they are detected, with source tracking (foreground/background).
  ///
  /// Use [config] for convenient presets or custom configuration:
  ///
  /// ```dart
  /// // Using presets
  /// await stepCounter.startLogging(config: StepRecordConfig.walking());
  /// await stepCounter.startLogging(config: StepRecordConfig.running());
  /// await stepCounter.startLogging(config: StepRecordConfig.conservative());
  /// await stepCounter.startLogging(config: StepRecordConfig.aggregated());
  ///
  /// // Custom configuration
  /// await stepCounter.startLogging(
  ///   config: StepRecordConfig(
  ///     warmupDurationMs: 8000,
  ///     minStepsToValidate: 10,
  ///     maxStepsPerSecond: 5.0,
  ///     enableAggregatedMode: true,
  ///   ),
  /// );
  /// ```
  ///
  /// Available presets:
  /// - [StepRecordConfig.walking] - Casual walking (5s warmup, 3 steps/sec max)
  /// - [StepRecordConfig.running] - Running/jogging (3s warmup, 5 steps/sec max)
  /// - [StepRecordConfig.sensitive] - High sensitivity (no warmup)
  /// - [StepRecordConfig.conservative] - Strict validation (10s warmup)
  /// - [StepRecordConfig.noValidation] - Raw logging (no validation)
  /// - [StepRecordConfig.aggregated] - Health Connect-like (continuous recording)
  /// - [StepRecordConfig.lowEndDevice] - Optimized for low-end devices (isolate enabled)
  Future<void> startLogging({StepRecordConfig? config}) async {
    if (!_storeInitialized) {
      throw StateError(
        'Logging not initialized. Call initializeLogging() first.',
      );
    }

    if (_recordingEnabled) return;
    final sw = Stopwatch()..start();

    // Use provided config or default
    final cfg = config ?? const StepRecordConfig();

    // If config requests isolate mode but store wasn't initialized with it,
    // recreate the store with isolate support
    if (cfg.useBackgroundIsolate && !_useBackgroundIsolate) {
      _log('Switching to background isolate mode');
      await _stepRecordStore?.close();
      _useBackgroundIsolate = true;
      _stepRecordStore = StepRecordStore(
        useIsolate: true,
        performanceTracing: _performanceTracing,
      );
      await _traceAsync('startLogging.switchToIsolateInit', () async {
        await _stepRecordStore!.initialize();
        return;
      });
    }

    _recordingEnabled = true;
    _aggregatedModeEnabled = cfg.enableAggregatedMode;
    _recordIntervalMs = cfg.recordIntervalMs;
    _warmupDurationMs = cfg.warmupDurationMs;
    _minStepsToValidate = cfg.minStepsToValidate;
    _maxStepsPerSecond = cfg.maxStepsPerSecond;
    _inactivityTimeoutMs = cfg.inactivityTimeoutMs;
    _isInWarmup = cfg.warmupDurationMs > 0;
    _warmupStartTime = null;
    _warmupStartStepCount = 0;
    _lastRecordTime = _now().toUtc();
    _lastRecordedStepCount = 0;
    _writeBuffer.clear();
    _writeBufferFlushTimer?.cancel();
    _writeBufferFlushTimer = null;

    // Initialize aggregated mode with today's data
    if (_aggregatedModeEnabled) {
      await _traceAsync('startLogging.initializeAggregatedMode', () async {
        await _initializeAggregatedMode();
        return;
      });
      // Start buffer flush timer (every 3 seconds)
      _writeBufferFlushTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _flushWriteBuffer().catchError((Object error) {
          _log('Buffered writes retained for retry: $error');
        }),
      );
    }

    // Automatic log retention cleanup
    if (cfg.retentionPeriod > Duration.zero) {
      // Run in background to avoid delaying startup
      unawaited(_cleanupOldLogs(cfg.retentionPeriod));
    }

    _scheduleDayBoundary();

    // Subscribe to step events for auto-logging
    _stepRecordSubscription = stepEventStream.listen((event) {
      _loggingQueue = _loggingQueue
          .then((_) async {
            if (_aggregatedModeEnabled) {
              await _autoLogStepsContinuous(event);
            } else {
              await _autoLogSteps(event, _recordIntervalMs);
            }
          })
          .catchError((Object error, StackTrace stack) {
            _log('Step logging failed: $error');
          });
    });

    if (_aggregatedModeEnabled) {
      _log(
        'Aggregated step logging started - loaded $_aggregatedStoredSteps steps from today',
      );
    } else if (_isInWarmup) {
      _log('Step logging started with $cfg');
    } else {
      _log('Step logging started (no warmup)');
    }
    _logPerf('startLogging.total took ${sw.elapsedMilliseconds}ms');
  }

  /// Stop auto-logging steps
  Future<void> stopLogging() async {
    _dayBoundaryTimer?.cancel();
    _dayBoundaryTimer = null;
    await _stepRecordSubscription?.cancel();
    _stepRecordSubscription = null;
    await _loggingQueue;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _writeBufferFlushTimer?.cancel();
    _writeBufferFlushTimer = null;
    _recordingEnabled = false;
    _aggregatedModeEnabled = false;
    _log('Step logging stopped');
    // Flush any remaining steps
    await _flushWriteBuffer();
  }

  /// Reset warmup state for new walking session
  void _resetWarmupState() {
    _isInWarmup = _warmupDurationMs > 0;
    _warmupStartTime = null;
    _warmupStartStepCount = 0;
    _lastWarmupCheckTime = null;
    _warmupWindowStartStepCount = 0;
    _log('Warmup state reset - new session will require validation');
  }

  /// Handle inactivity timeout - end current session and reset warmup
  void _handleInactivityTimeout() {
    _log('Inactivity timeout triggered - ending current session');
    _resetWarmupState();
  }

  /// Start or restart the inactivity timer
  void _startInactivityTimer() {
    if (_inactivityTimeoutMs <= 0) return;

    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(
      Duration(milliseconds: _inactivityTimeoutMs),
      _handleInactivityTimeout,
    );
  }

  /// Clean up old logs based on retention period
  Future<void> _cleanupOldLogs(Duration retentionPeriod) async {
    try {
      final cutoff = _now().subtract(retentionPeriod);
      _log('Cleaning up logs older than $cutoff');
      await _stepRecordStore!.deleteRecordsBefore(cutoff);
    } catch (e) {
      _log('Error cleaning up old logs: $e');
    }
  }

  /// Initialize aggregated mode by loading today's steps
  Future<void> _initializeAggregatedMode() async {
    await _ensureCurrentDay();
    final now = _now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    var nativeBaseline = currentStepCount;
    // Load today's steps from SQLite
    var todaySteps = await _stepRecordStore!.readTotalSteps(
      from: startOfToday,
      to: now,
    );

    // Reconcile native FGS → SQLite so process-death gaps are not lost
    if (_useNativeStepService) {
      try {
        final nativeToday = await _platform.getNativeTodaySteps();
        nativeBaseline = nativeToday;
        final recordedNative = await _readNativeStoredSteps(startOfToday, now);
        if (nativeToday > recordedNative) {
          final gap = nativeToday - recordedNative;
          final dayKey =
              '${startOfToday.year}-'
              '${startOfToday.month.toString().padLeft(2, '0')}-'
              '${startOfToday.day.toString().padLeft(2, '0')}';
          await _stepRecordStore!.insertRecord(
            StepRecord(
              stepCount: gap,
              fromTime: startOfToday,
              toTime: now,
              source: StepRecordSource.terminated,
              confidence: 1.0,
              idempotencyKey: 'native_reconcile|$dayKey|$nativeToday',
            ),
          );
          todaySteps = await _stepRecordStore!.readTotalSteps(
            from: startOfToday,
            to: now,
          );
          _log('Reconciled native→SQLite gap=$gap (today=$todaySteps)');
        }
      } catch (e) {
        _log('Native reconcile skipped: $e');
      }
    }

    // Store today's steps from database (after reconcile)
    _aggregatedStoredSteps = todaySteps;
    // Reset session tracking against current sensor reading
    _currentSessionSteps = 0;
    _sessionBaseStepCount = nativeBaseline;
    _lastRecordedStepCount = _sessionBaseStepCount;

    // Emit initial value to stream immediately
    if (!_aggregatedStepController.isClosed) {
      _aggregatedStepController.add(_aggregatedStoredSteps);
      _lastStreamEmitTime = _now();
    }

    _log('Initialized aggregated mode: $todaySteps steps from today');
  }

  /// Auto-log steps continuously (write on every step) for aggregated mode
  Future<void> _autoLogStepsContinuous(StepCountEvent event) async {
    final now = event.timestamp;

    // Restart inactivity timer on every step
    _startInactivityTimer();

    // === WARMUP PHASE ===
    if (_isInWarmup) {
      // Initialize warmup on first step event
      if (_warmupStartTime == null) {
        _warmupStartTime = now;
        _warmupStartStepCount = event.stepCount;
        _lastWarmupCheckTime = now;
        _warmupWindowStartStepCount = event.stepCount;
        _log('Warmup started');
        return;
      }

      final warmupElapsed = now.difference(_warmupStartTime!);

      // Sliding window validation (check every 2 seconds)
      if (_lastWarmupCheckTime != null) {
        final windowElapsed = now.difference(_lastWarmupCheckTime!);
        if (windowElapsed.inMilliseconds >= 2000) {
          final windowSteps = event.stepCount - _warmupWindowStartStepCount;
          final windowSeconds = windowElapsed.inMilliseconds / 1000.0;
          final windowRate = windowSteps / windowSeconds;

          if (windowRate > _maxStepsPerSecond) {
            dev.log(
              'AccurateStepCounter: Warmup failed (window) - rate ${windowRate.toStringAsFixed(2)}/s',
            );
            _warmupStartTime = now;
            _warmupStartStepCount = event.stepCount;
            _lastWarmupCheckTime = now;
            _warmupWindowStartStepCount = event.stepCount;
            return;
          }

          // Window passed - advance window
          _lastWarmupCheckTime = now;
          _warmupWindowStartStepCount = event.stepCount;
        }
      } else {
        _lastWarmupCheckTime = now;
        _warmupWindowStartStepCount = event.stepCount;
      }

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

      // ✓ Walking validated - log warmup steps as a single batch
      dev.log(
        'AccurateStepCounter: Warmup validated - $warmupSteps steps at ${stepsPerSecond.toStringAsFixed(2)}/s',
      );

      // Log warmup steps as a single batch entry (more efficient than individual)
      final source = _determineSource();
      final entry = StepRecord(
        stepCount: warmupSteps,
        fromTime: _warmupStartTime!,
        toTime: now,
        source: source,
        confidence: event.confidence,
      );
      await _safeInsertRecord(entry);

      _log('Logged $warmupSteps warmup steps');

      // Exit warmup mode
      _isInWarmup = false;
      _lastRecordTime = now;
      _lastRecordedStepCount = event.stepCount;

      // Update session steps tracking
      _currentSessionSteps += warmupSteps;

      // Emit aggregated count (stored from DB + new session steps)
      _emitAggregatedCount(_aggregatedStoredSteps + _currentSessionSteps);
      return;
    }

    // === CONTINUOUS LOGGING (after warmup) ===

    final newSteps = event.stepCount - _lastRecordedStepCount;

    if (newSteps > 0) {
      // Validate step rate if there's a time gap
      if (!_useNativeStepService && _lastRecordTime != null) {
        final elapsed = now.difference(_lastRecordTime!);
        final elapsedSeconds = elapsed.inMilliseconds / 1000.0;

        if (elapsedSeconds > 0) {
          final stepsPerSecond = newSteps / elapsedSeconds;

          if (stepsPerSecond > _maxStepsPerSecond) {
            // Unrealistic rate - skip this batch
            dev.log(
              'AccurateStepCounter: Skipping $newSteps steps - rate ${stepsPerSecond.toStringAsFixed(2)}/s too high',
            );
            _lastRecordTime = now;
            _lastRecordedStepCount = event.stepCount;
            return;
          }
        }
      }

      final source = _determineSource();
      final lastTime = _lastRecordTime!;

      // Update state immediately to prevent potential race conditions
      _lastRecordTime = now;
      _lastRecordedStepCount = event.stepCount;

      // Buffer the write instead of hitting DB immediately
      _bufferSteps(newSteps, lastTime, now, source, event.confidence);

      _log('Buffered $newSteps steps (source: $source)');

      // Update session steps tracking
      _currentSessionSteps += newSteps;

      // Emit aggregated count (stored from DB + new session steps + buffered pending)
      // Note: buffered steps are part of _currentSessionSteps implicitly
      // Use throttled emission to reduce UI updates on low-end devices
      _emitAggregatedCount(_aggregatedStoredSteps + _currentSessionSteps);
    } else {
      // Just update tracking if no new steps (or negative due to reset)
      _lastRecordTime = now;
      _lastRecordedStepCount = event.stepCount;
    }
  }

  /// Set the current app lifecycle state
  ///
  /// Call this from your WidgetsBindingObserver to properly track
  /// foreground vs background state for step logging.
  ///
  /// This method is safe to call during cold starts - it handles cases
  /// where the SQLite database may be closed and needs reopening.
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
    _log('App state changed to $state');
    if (_isStarted) {
      _setRuntimeState(_activeRuntimeState(), reason: 'appLifecycleChanged');
    }

    // On resume, drain midnight rotation stamps missed while backgrounded
    if (state == AppLifecycleState.resumed && _useNativeStepService) {
      unawaited(_handleResumeDrain());
    }

    // If logging is enabled and app goes to background, log current steps
    if (_recordingEnabled &&
        state != AppLifecycleState.resumed &&
        _lastRecordTime != null) {
      if (_aggregatedModeEnabled) {
        unawaited(
          _loggingQueue.then((_) => _flushWriteBuffer()).catchError((
            Object error,
          ) {
            _log('Background flush retained for retry: $error');
          }),
        );
        return;
      }
      // Force log current batch before going to background
      final currentCount = currentStepCount;
      if (currentCount > _lastRecordedStepCount) {
        final entry = StepRecord(
          stepCount: currentCount - _lastRecordedStepCount,
          fromTime: _lastRecordTime!,
          toTime: _now(),
          source: StepRecordSource.foreground,
        );
        // Use async insertion with error handling for cold start safety
        _safeInsertRecord(entry);
        _lastRecordTime = _now();
        _lastRecordedStepCount = currentCount;
        _log('Logged steps before background');
      }
    }
  }

  Future<void> _handleResumeDrain() async {
    try {
      await _drainNativeRotation();
      await _queueNativeSteps(await _platform.getNativeTodaySteps());
    } catch (error) {
      _log('Resume reconciliation failed: $error');
    }
  }

  /// Safely insert a record with error handling for closed box scenarios
  ///
  /// This is used during lifecycle transitions where the box might be closed
  /// due to Android killing the app. The StepRecordStore now handles this
  /// internally, but this wrapper provides additional safety.
  String _buildIdempotencyKey(
    int stepCount,
    DateTime fromTime,
    DateTime toTime,
    StepRecordSource source,
  ) {
    final fromMs = fromTime.toUtc().millisecondsSinceEpoch;
    final toMs = toTime.toUtc().millisecondsSinceEpoch;
    return '${source.name}|$fromMs|$toMs|$stepCount';
  }

  Future<void> _safeInsertRecord(StepRecord entry) async {
    try {
      final normalizedEntry = entry.idempotencyKey == null
          ? entry.copyWith(
              idempotencyKey: _buildIdempotencyKey(
                entry.stepCount,
                entry.fromTime,
                entry.toTime,
                entry.source,
              ),
            )
          : entry;
      await _stepRecordStore!.insertRecord(normalizedEntry);
    } catch (e) {
      _log('Error inserting record (will retry): $e');
      rethrow;
    }
  }

  /// Auto-log steps based on interval with warmup validation
  Future<void> _autoLogSteps(StepCountEvent event, int intervalMs) async {
    final now = event.timestamp;

    // Restart inactivity timer on every step
    _startInactivityTimer();

    // === WARMUP PHASE ===
    if (_isInWarmup) {
      // Initialize warmup on first step event
      if (_warmupStartTime == null) {
        _warmupStartTime = now;
        _warmupStartStepCount = event.stepCount;
        _lastWarmupCheckTime = now;
        _warmupWindowStartStepCount = event.stepCount;
        _log('Warmup started');
        return;
      }

      final warmupElapsed = now.difference(_warmupStartTime!);

      // Sliding window validation (check every 2 seconds)
      if (_lastWarmupCheckTime != null) {
        final windowElapsed = now.difference(_lastWarmupCheckTime!);
        if (windowElapsed.inMilliseconds >= 2000) {
          final windowSteps = event.stepCount - _warmupWindowStartStepCount;
          final windowSeconds = windowElapsed.inMilliseconds / 1000.0;
          final windowRate = windowSteps / windowSeconds;

          if (windowRate > _maxStepsPerSecond) {
            dev.log(
              'AccurateStepCounter: Warmup failed (window) - rate ${windowRate.toStringAsFixed(2)}/s',
            );
            _warmupStartTime = now;
            _warmupStartStepCount = event.stepCount;
            _lastWarmupCheckTime = now;
            _warmupWindowStartStepCount = event.stepCount;
            return;
          }

          // Window passed - advance window
          _lastWarmupCheckTime = now;
          _warmupWindowStartStepCount = event.stepCount;
        }
      } else {
        _lastWarmupCheckTime = now;
        _warmupWindowStartStepCount = event.stepCount;
      }

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
      final entry = StepRecord(
        stepCount: warmupSteps,
        fromTime: _warmupStartTime!,
        toTime: now,
        source: source,
        confidence: event.confidence,
      );

      await _safeInsertRecord(entry);
      dev.log(
        'AccurateStepCounter: Logged $warmupSteps warmup steps (source: $source)',
      );

      // Exit warmup mode
      _isInWarmup = false;
      _lastRecordTime = now;
      _lastRecordedStepCount = event.stepCount;
      return;
    }

    // === NORMAL LOGGING (after warmup) ===

    if (_lastRecordTime == null) {
      _lastRecordTime = now;
      _lastRecordedStepCount = event.stepCount;
      return;
    }

    final elapsed = now.difference(_lastRecordTime!);
    if (elapsed.inMilliseconds >= intervalMs) {
      final newSteps = event.stepCount - _lastRecordedStepCount;

      if (newSteps > 0) {
        // Validate step rate
        final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
        final stepsPerSecond = newSteps / elapsedSeconds;

        if (stepsPerSecond > _maxStepsPerSecond) {
          // Unrealistic rate - skip this batch
          dev.log(
            'AccurateStepCounter: Skipping $newSteps steps - rate ${stepsPerSecond.toStringAsFixed(2)}/s too high',
          );
          _lastRecordTime = now;
          _lastRecordedStepCount = event.stepCount;
          return;
        }

        final source = _determineSource();
        final lastTime = _lastRecordTime!;

        // Update state first
        _lastRecordTime = now;
        _lastRecordedStepCount = event.stepCount;

        await _logDistributedSteps(
          newSteps,
          lastTime,
          now,
          source,
          confidence: event.confidence,
        );
        dev.log(
          'AccurateStepCounter: Logged $newSteps steps (source: $source)',
        );
      } else {
        _lastRecordTime = now;
        _lastRecordedStepCount = event.stepCount;
      }
    }
  }

  /// Log steps with distribution across days if needed
  Future<void> _logDistributedSteps(
    int stepCount,
    DateTime fromTime,
    DateTime toTime,
    StepRecordSource source, {
    double confidence = 1.0,
  }) async {
    fromTime = fromTime.toLocal();
    toTime = toTime.toLocal();
    // Check if time range spans across days
    final fromDate = DateTime(fromTime.year, fromTime.month, fromTime.day);
    final toDate = DateTime(toTime.year, toTime.month, toTime.day);

    // If same day, log as single entry
    if (fromDate == toDate) {
      final entry = StepRecord(
        stepCount: stepCount,
        fromTime: fromTime,
        toTime: toTime,
        source: source,
        confidence: confidence,
      );
      await _safeInsertRecord(entry);
      return;
    }

    // Multiple days - distribute steps proportionally
    final totalDurationMs = toTime.difference(fromTime).inMilliseconds;
    if (totalDurationMs <= 0) {
      // Should not happen for valid ranges, but safety check
      final entry = StepRecord(
        stepCount: stepCount,
        fromTime: fromTime,
        toTime: toTime,
        source: source,
        confidence: confidence,
      );
      await _safeInsertRecord(entry);
      return;
    }

    int remainingSteps = stepCount;
    DateTime currentStart = fromTime;

    while (currentStart.isBefore(toTime)) {
      final currentDate = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day,
      );
      // End of this day (first millisecond of next day, calculated to avoid gaps)
      // Actually using midnight of next day is cleaner for comparison
      final nextDay = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day + 1,
      );
      final currentEnd = nextDay.isBefore(toTime) ? nextDay : toTime;

      // Calculate proportion
      final segmentDurationMs = currentEnd
          .difference(currentStart)
          .inMilliseconds;
      final proportion = segmentDurationMs / totalDurationMs;

      int segmentSteps;
      if (currentEnd == toTime) {
        // Last segment gets remainder
        segmentSteps = remainingSteps;
      } else {
        segmentSteps = (stepCount * proportion).round();
        remainingSteps -= segmentSteps;
      }

      if (segmentSteps > 0) {
        final entry = StepRecord(
          stepCount: segmentSteps,
          fromTime: currentStart,
          toTime: currentEnd,
          source: source,
          confidence: confidence,
        );
        await _safeInsertRecord(entry);
      }

      currentStart = currentEnd;
    }
  }

  /// Determine the step log source based on current mode and app state
  StepRecordSource _determineSource() {
    if (_useForegroundService) {
      // Old Android with foreground service - counts in background
      return StepRecordSource.background;
    } else if (_appLifecycleState == AppLifecycleState.resumed) {
      // New Android, app in foreground
      return StepRecordSource.foreground;
    } else {
      // New Android, app in background (paused, inactive, etc.)
      return StepRecordSource.background;
    }
  }

  Future<bool> _isTerminatedGapAlreadyLogged(TerminatedSyncGap gap) async {
    if (!_storeInitialized || _stepRecordStore == null) {
      return false;
    }

    final segments = gap.splitIntoDailySegments();
    if (segments.isEmpty) {
      return false;
    }

    for (final segment in segments) {
      final exists = await _stepRecordStore!.hasDuplicateRecord(
        fromTime: segment.fromTime,
        toTime: segment.toTime,
        stepCount: segment.stepCount,
        source: StepRecordSource.terminated,
      );
      if (!exists) {
        return false;
      }
    }

    return true;
  }

  /// Log steps from terminated state sync using deterministic gap-based keys.
  ///
  /// If the time range spans multiple days, steps are distributed proportionally
  /// across each day to ensure accurate daily step counts.
  ///
  /// Note: Only requires logging to be initialized, not enabled,
  /// so terminated steps are logged even before startLogging() is called.
  Future<void> _logTerminatedSteps(TerminatedSyncGap gap) async {
    // Only require initialized, not enabled - terminated steps should
    // always be logged if database is ready, regardless of auto-logging state
    if (!_storeInitialized) {
      dev.log(
        'AccurateStepCounter: Skipping terminated steps log - database not initialized',
      );
      return;
    }

    final segments = gap.splitIntoDailySegments();
    for (final segment in segments) {
      await _safeInsertRecord(
        StepRecord(
          stepCount: segment.stepCount,
          fromTime: segment.fromTime,
          toTime: segment.toTime,
          source: StepRecordSource.terminated,
          idempotencyKey: segment.idempotencyKey,
        ),
      );
    }

    _log(
      'Logged ${gap.missedSteps} terminated steps '
      '(${segments.length} segment(s), key=${gap.gapKey})',
    );
  }

  /// Manually log a step entry
  ///
  /// Useful for recording steps from external sources or correcting data.
  ///
  /// Example:
  /// ```dart
  /// await stepCounter.insertRecord(StepRecord(
  ///   stepCount: 100,
  ///   fromTime: DateTime.now().subtract(Duration(hours: 1)),
  ///   toTime: DateTime.now(),
  ///   source: StepRecordSource.foreground,
  /// ));
  /// ```
  Future<void> insertRecord(StepRecord entry) async {
    if (!_storeInitialized) {
      throw StateError(
        'Logging not initialized. Call initializeLogging() first.',
      );
    }
    await _safeInsertRecord(entry);
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
    await _flushPendingWritesIfNeeded();
    return await _stepRecordStore!.readTotalSteps(from: from, to: to);
  }

  /// Get combined steps for today and yesterday
  ///
  /// Convenience method for getting the last 2 days of steps.
  ///
  /// Example:
  /// ```dart
  /// final combinedSteps = await stepCounter.getTodayAndYesterdaySteps();
  /// print('Steps (today + yesterday): $combinedSteps');
  /// ```
  Future<int> getTodayAndYesterdaySteps() async {
    _ensureLoggingInitialized();
    await _flushPendingWritesIfNeeded();
    final now = _now();
    final startOfYesterday = DateTime(now.year, now.month, now.day - 1);
    return await _stepRecordStore!.readTotalSteps(
      from: startOfYesterday,
      to: now,
    );
  }

  /// Get steps for a custom date range
  ///
  /// [startDate] - Start date (will be set to midnight)
  /// [endDate] - End date (will be set to midnight or now if today)
  ///
  /// Example:
  /// ```dart
  /// // Get steps for last 7 days
  /// final weekSteps = await stepCounter.getStepsInRange(
  ///   DateTime.now().subtract(Duration(days: 7)),
  ///   DateTime.now(),
  /// );
  ///
  /// // Get steps for a specific date
  /// final specificDate = DateTime(2025, 1, 15);
  /// final stepsOnDate = await stepCounter.getStepsInRange(
  ///   specificDate,
  ///   specificDate,
  /// );
  /// ```
  Future<int> getStepsInRange(DateTime startDate, DateTime endDate) async {
    _ensureLoggingInitialized();
    await _flushPendingWritesIfNeeded();

    // Set start to midnight of startDate
    final start = DateTime(startDate.year, startDate.month, startDate.day);

    // Set end to midnight of endDate, or now if endDate is today
    final now = _now();
    final endOfEndDate = DateTime(endDate.year, endDate.month, endDate.day);
    final isEndDateToday =
        endOfEndDate.year == now.year &&
        endOfEndDate.month == now.month &&
        endOfEndDate.day == now.day;

    final end = isEndDateToday
        ? now
        : DateTime(
            endDate.year,
            endDate.month,
            endDate.day + 1,
          ).subtract(const Duration(milliseconds: 1));

    return await _stepRecordStore!.readTotalSteps(from: start, to: end);
  }

  /// Get step count by source
  ///
  /// Example:
  /// ```dart
  /// final fgSteps = await stepCounter.getStepsBySource(StepRecordSource.foreground);
  /// final bgSteps = await stepCounter.getStepsBySource(StepRecordSource.background);
  /// final termSteps = await stepCounter.getStepsBySource(StepRecordSource.terminated);
  /// final externalSteps = await stepCounter.getStepsBySource(StepRecordSource.external);
  /// ```
  Future<int> getStepsBySource(
    StepRecordSource source, {
    DateTime? from,
    DateTime? to,
  }) async {
    _ensureLoggingInitialized();
    await _flushPendingWritesIfNeeded();
    return await _stepRecordStore!.readStepsBySource(
      source,
      from: from,
      to: to,
    );
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
  /// final bgLogs = await stepCounter.getStepLogs(source: StepRecordSource.background);
  /// ```
  Future<List<StepRecord>> getStepLogs({
    DateTime? from,
    DateTime? to,
    StepRecordSource? source,
  }) async {
    _ensureLoggingInitialized();
    await _flushPendingWritesIfNeeded();
    return await _stepRecordStore!.readRecords(
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
    return _stepRecordStore!.watchTotalSteps(from: from, to: to);
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
  Stream<List<StepRecord>> watchStepLogs({
    DateTime? from,
    DateTime? to,
    StepRecordSource? source,
  }) {
    _ensureLoggingInitialized();
    return _stepRecordStore!.watchRecords(from: from, to: to, source: source);
  }

  /// Watch aggregated step count (stored + live) in real-time
  ///
  /// This is the Health Connect-like API that combines:
  /// - All steps stored in SQLite from today (midnight to now)
  /// - Current live steps being detected
  ///
  /// When the app restarts:
  /// - Automatically loads today's stored steps
  /// - Continues counting from that point
  /// - No double-counting, seamless aggregation
  ///
  /// IMPORTANT: You must call startLogging() with aggregated mode enabled:
  /// ```dart
  /// await stepCounter.startLogging(config: StepRecordConfig.aggregated());
  /// ```
  ///
  /// Example usage:
  /// ```dart
  /// // Initialize
  /// await stepCounter.initializeLogging();
  /// await stepCounter.start();
  /// await stepCounter.startLogging(config: StepRecordConfig.aggregated());
  ///
  /// // Watch aggregated count
  /// stepCounter.watchAggregatedStepCounter().listen((totalSteps) {
  ///   print('Total steps today: $totalSteps');
  /// });
  /// ```
  ///
  /// This stream emits:
  /// - Initial value when subscribed (today's stored steps)
  /// - Updates on every new step detected
  /// - Updates when app is restarted (loads from SQLite)
  Stream<int> watchAggregatedStepCounter() {
    _ensureLoggingInitialized();

    if (!_aggregatedModeEnabled) {
      throw StateError(
        'Aggregated mode not enabled. Call startLogging() with '
        'StepRecordConfig.aggregated() or set enableAggregatedMode: true',
      );
    }

    return Stream<int>.multi((controller) {
      final subscription = _aggregatedStepController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.add(_aggregatedStoredSteps + _currentSessionSteps);
      controller.onCancel = subscription.cancel;
    });
  }

  /// Get current aggregated step count (stored + live)
  ///
  /// Synchronous getter for current aggregated count.
  /// Use [watchAggregatedStepCounter] for real-time updates.
  ///
  /// Example:
  /// ```dart
  /// final totalSteps = stepCounter.aggregatedStepCount;
  /// print('Current total: $totalSteps');
  /// ```
  int get aggregatedStepCount {
    if (!_aggregatedModeEnabled) {
      throw StateError(
        'Aggregated mode not enabled. Call startLogging() with '
        'StepRecordConfig.aggregated() or set enableAggregatedMode: true',
      );
    }
    // Return stored steps + current session steps (not raw currentStepCount!)
    return _aggregatedStoredSteps + _currentSessionSteps;
  }

  /// Manually write steps to aggregated database
  ///
  /// This method allows you to insert steps directly into the database,
  /// which will automatically update the aggregated count and notify
  /// all listeners of [watchAggregatedStepCounter].
  ///
  /// Perfect for:
  /// - Importing steps from external sources (Google Fit, Apple Health, etc.)
  /// - Manually correcting step counts
  /// - Syncing steps from other devices
  /// - Batch importing historical data
  ///
  /// IMPORTANT: Only works when aggregated mode is enabled.
  ///
  /// Parameters:
  /// - [stepCount] - Number of steps to write (must be positive)
  /// - [fromTime] - Start time of the activity
  /// - [toTime] - End time of the activity (defaults to now)
  /// - [source] - Source of the steps (defaults to external)
  ///
  /// Example:
  /// ```dart
  /// // Import from Google Fit (recommended - use external source)
  /// await stepCounter.writeStepsToAggregated(
  ///   stepCount: 5000,
  ///   fromTime: DateTime.now().subtract(Duration(hours: 2)),
  ///   toTime: DateTime.now(),
  ///   source: StepRecordSource.external, // Mark as external data
  /// );
  ///
  /// // Import from Apple Health
  /// await stepCounter.writeStepsToAggregated(
  ///   stepCount: 3500,
  ///   fromTime: startOfDay,
  ///   toTime: endOfDay,
  ///   source: StepRecordSource.external,
  /// );
  ///
  /// // Manual correction (if needed)
  /// await stepCounter.writeStepsToAggregated(
  ///   stepCount: 100,
  ///   fromTime: DateTime.now().subtract(Duration(hours: 1)),
  ///   toTime: DateTime.now(),
  ///   source: StepRecordSource.foreground,
  /// );
  /// ```
  ///
  /// After writing, the aggregated stream will automatically emit the new total.
  /// Writes steps to the aggregated database with optional duplicate detection
  ///
  /// Returns `true` if steps were written, `false` if skipped due to duplicate.
  ///
  /// [stepCount] - Number of steps to write (must be positive)
  /// [fromTime] - Start time of the activity
  /// [toTime] - End time of the activity (defaults to now)
  /// [source] - Source of the steps (defaults to external)
  /// [skipIfDuplicate] - If true, skips writing if duplicate record exists (default: true)
  ///
  /// Example:
  /// ```dart
  /// // Safe external import with duplicate prevention (recommended)
  /// final wasWritten = await stepCounter.writeStepsToAggregated(
  ///   stepCount: 5000,
  ///   fromTime: DateTime.now().subtract(Duration(hours: 2)),
  ///   toTime: DateTime.now(),
  ///   source: StepRecordSource.external,
  ///   skipIfDuplicate: true, // Default - prevents duplicate imports
  /// );
  /// if (!wasWritten) {
  ///   print('Skipped - record already exists');
  /// }
  ///
  /// // Force write without duplicate check
  /// await stepCounter.writeStepsToAggregated(
  ///   stepCount: 100,
  ///   fromTime: startTime,
  ///   toTime: endTime,
  ///   skipIfDuplicate: false, // Force write even if duplicate
  /// );
  /// ```
  Future<bool> writeStepsToAggregated({
    required int stepCount,
    required DateTime fromTime,
    DateTime? toTime,
    StepRecordSource? source,
    bool skipIfDuplicate = true,
  }) async {
    final next = _externalWriteChain.then(
      (_) => _writeStepsToAggregatedLocked(
        stepCount: stepCount,
        fromTime: fromTime,
        toTime: toTime,
        source: source,
        skipIfDuplicate: skipIfDuplicate,
      ),
    );
    _externalWriteChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<bool> _writeStepsToAggregatedLocked({
    required int stepCount,
    required DateTime fromTime,
    DateTime? toTime,
    StepRecordSource? source,
    required bool skipIfDuplicate,
  }) async {
    _ensureLoggingInitialized();
    await _ensureCurrentDay();

    if (!_aggregatedModeEnabled) {
      throw StateError(
        'Aggregated mode not enabled. Call startLogging() with '
        'StepRecordConfig.aggregated() or set enableAggregatedMode: true',
      );
    }

    if (stepCount <= 0) {
      throw ArgumentError('Step count must be positive');
    }

    final endTime = toTime ?? _now().toUtc();

    if (endTime.isBefore(fromTime)) {
      throw ArgumentError('toTime must be after fromTime');
    }

    final recordSource = source ?? StepRecordSource.external;

    try {
      // === IN-MEMORY DUPLICATE CHECK ===
      // Fast check against last write to catch rapid duplicate calls
      // This is faster than database check and catches most race conditions
      if (skipIfDuplicate && recordSource == StepRecordSource.external) {
        final now = _now().toUtc();
        if (_lastExternalWriteTime != null &&
            _lastExternalWriteSteps == stepCount &&
            _lastExternalWriteFromTime != null) {
          // Check if this looks like a duplicate write (same steps, same fromTime, within 30 seconds)
          final timeSinceLastWrite = now.difference(_lastExternalWriteTime!);
          final fromTimeDiff = fromTime
              .difference(_lastExternalWriteFromTime!)
              .abs();

          if (timeSinceLastWrite.inSeconds < 30 &&
              fromTimeDiff.inSeconds < 60) {
            _log(
              'Skipped near-duplicate write (in-memory check): $stepCount steps, '
              'last write was ${timeSinceLastWrite.inSeconds}s ago',
            );
            return false;
          }
        }
      }

      // === DATABASE DUPLICATE CHECK ===
      // Check for duplicate record in database if requested
      if (skipIfDuplicate) {
        final isDuplicate = await _stepRecordStore!.hasDuplicateRecord(
          fromTime: fromTime,
          toTime: endTime,
          stepCount: stepCount,
          source: recordSource,
        );

        if (isDuplicate) {
          _log(
            'Skipped duplicate write (database check): $stepCount steps from $fromTime to $endTime',
          );
          return false; // Record already exists
        }
      }

      await _flushWriteBuffer();
      // Write to database (with distribution if needed)
      await _logDistributedSteps(stepCount, fromTime, endTime, recordSource);
      _log('Wrote $stepCount steps to aggregated database');

      // Track this write for in-memory duplicate detection
      if (recordSource == StepRecordSource.external) {
        _lastExternalWriteTime = _now();
        _lastExternalWriteSteps = stepCount;
        _lastExternalWriteFromTime = fromTime;
      }

      // Update stored steps to include the new manually added steps
      final now = _now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      // Recalculate today's total from database
      final todayTotal = await _stepRecordStore!.readTotalSteps(
        from: startOfToday,
        to: now,
      );

      // Update stored steps count
      _aggregatedStoredSteps = todayTotal - _currentSessionSteps;

      // Emit updated aggregated count immediately (no throttling for external writes
      // since they're infrequent and user expects immediate UI update)
      final newAggregatedCount = _aggregatedStoredSteps + _currentSessionSteps;
      if (!_aggregatedStepController.isClosed) {
        _aggregatedStepController.add(newAggregatedCount);
        _lastStreamEmitTime = _now();
      }

      return true; // Successfully written
    } catch (_) {
      rethrow;
    }
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
    await _flushPendingWritesIfNeeded();
    return await _stepRecordStore!.getStats(from: from, to: to);
  }

  /// Clear all step logs
  ///
  /// Use with caution - this permanently deletes all logged data.
  Future<void> clearStepLogs() async {
    _ensureLoggingInitialized();
    await _flushPendingWritesIfNeeded();
    await _stepRecordStore!.deleteAllRecords();

    _aggregatedStoredSteps = 0;
    _currentSessionSteps = 0;
    _sessionBaseStepCount = currentStepCount;
    _lastRecordedStepCount = _sessionBaseStepCount;
    _lastExternalWriteTime = null;
    _lastExternalWriteSteps = null;
    _lastExternalWriteFromTime = null;
    _processedTerminatedGapKeys.clear();
    _log('All step logs cleared');
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
    await _flushPendingWritesIfNeeded();
    await _stepRecordStore!.deleteRecordsBefore(date);
    _log('Deleted logs before $date');
  }

  /// Ensure logging is initialized, throw if not
  void _ensureLoggingInitialized() {
    if (!_storeInitialized) {
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
        await _platform.saveStepCount(osCount, _now());
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
    if (_terminatedSyncInFlight != null) {
      return _terminatedSyncInFlight!;
    }

    final future = _performTerminatedSync();
    _terminatedSyncInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_terminatedSyncInFlight, future)) {
        _terminatedSyncInFlight = null;
      }
    }
  }

  Future<Map<String, dynamic>?> _performTerminatedSync() async {
    final sw = Stopwatch()..start();
    final previousState = _runtimeState;
    _setRuntimeState(
      StepRuntimeState.recoveringAfterTermination,
      reason: 'terminatedSyncStart',
    );
    try {
      dev.log(
        'AccurateStepCounter: Checking for steps from terminated state...',
      );

      final result = await _platform.syncStepsFromTerminated();

      if (result == null) {
        _log('No steps to sync from terminated state');
        return null;
      }

      final missedSteps = result['missedSteps'] as int;
      final startTime = result['startTime'] as DateTime;
      final endTime = result['endTime'] as DateTime;
      final gap = TerminatedSyncGap(
        missedSteps: missedSteps,
        startTime: startTime,
        endTime: endTime,
      );

      dev.log(
        'AccurateStepCounter: Syncing $missedSteps steps from terminated state',
      );
      _log('Time range: $startTime to $endTime');
      _log('Gap key: ${gap.gapKey}');

      // === VALIDATION: Apply same rules as warmup validation ===
      // Prevent shake steps from being synced on app restart
      final duration = endTime.difference(startTime);
      final durationSeconds = duration.inMilliseconds / 1000.0;

      // Check minimum steps requirement
      if (missedSteps < _minStepsToValidate && durationSeconds > 0) {
        dev.log(
          'AccurateStepCounter: Terminated sync rejected - only $missedSteps steps (need $_minStepsToValidate)',
        );
        return null;
      }

      // Check step rate to detect shakes
      if (durationSeconds > 0) {
        final stepsPerSecond = missedSteps / durationSeconds;
        if (stepsPerSecond > _maxStepsPerSecond) {
          dev.log(
            'AccurateStepCounter: Terminated sync rejected - rate ${stepsPerSecond.toStringAsFixed(2)}/s exceeds max $_maxStepsPerSecond/s',
          );
          return null;
        }
      }

      dev.log(
        'AccurateStepCounter: Terminated sync validated - $missedSteps steps at ${durationSeconds > 0 ? (missedSteps / durationSeconds).toStringAsFixed(2) : "N/A"}/s',
      );

      // Session-level dedupe avoids duplicate callback/logging from repeated calls.
      if (_processedTerminatedGapKeys.contains(gap.gapKey)) {
        _log('Skipping already processed terminated gap in this session');
        return null;
      }

      // Persistent dedupe against existing records (including pre-idempotency rows).
      if (await _isTerminatedGapAlreadyLogged(gap)) {
        _processedTerminatedGapKeys.add(gap.gapKey);
        _log('Skipping terminated sync gap already present in database');
        return null;
      }

      // Notify via callback if registered
      if (onTerminatedStepsDetected != null) {
        onTerminatedStepsDetected!(missedSteps, startTime, endTime);
      }

      // Log terminated steps to database if logging is enabled.
      await _logTerminatedSteps(gap);
      _processedTerminatedGapKeys.add(gap.gapKey);

      return result;
    } catch (e) {
      _setRuntimeState(StepRuntimeState.error, reason: 'terminatedSyncFailed');
      _log('Error syncing steps after termination: $e');
      return null;
    } finally {
      if (_runtimeState != StepRuntimeState.error) {
        if (_isStarted) {
          _setRuntimeState(
            _activeRuntimeState(),
            reason: 'terminatedSyncComplete',
          );
        } else if (_storeInitialized) {
          _setRuntimeState(
            StepRuntimeState.initialized,
            reason: 'terminatedSyncComplete',
          );
        } else {
          _setRuntimeState(previousState, reason: 'terminatedSyncComplete');
        }
      }
      _logPerf(
        '_syncStepsFromTerminatedState.total took ${sw.elapsedMilliseconds}ms',
      );
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

  /// Buffer steps for batch writing
  void _bufferSteps(
    int stepCount,
    DateTime fromTime,
    DateTime toTime,
    StepRecordSource source,
    double confidence,
  ) {
    _writeBuffer.add(
      PendingStep(
        stepCount: stepCount,
        fromTime: fromTime,
        toTime: toTime,
        source: source,
        confidence: confidence,
      ),
    );
  }

  /// Flush buffered writes to DB in a single batch equivalent
  Future<void> _flushWriteBuffer() {
    return _writeFlushInFlight ??= _performWriteBufferFlush().whenComplete(() {
      _writeFlushInFlight = null;
    });
  }

  Future<void> _performWriteBufferFlush() async {
    while (_writeBuffer.isNotEmpty) {
      final step = _writeBuffer.first;
      await _logDistributedSteps(
        step.stepCount,
        step.fromTime,
        step.toTime,
        step.source,
        confidence: step.confidence,
      );
      // Keep failed writes queued. Deterministic record keys make retries safe
      // even if a multi-day write persisted some segments before failing.
      _writeBuffer.removeAt(0);
    }
  }

  DateTime? _parseRotationDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}
