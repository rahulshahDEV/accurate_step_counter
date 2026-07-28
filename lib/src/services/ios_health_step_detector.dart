import 'dart:async';

import 'package:health/health.dart';

import '../models/step_count_event.dart';
import '../policy/hc_smoothing.dart';

/// iOS step source using HealthKit through the `health` package.
///
/// Mirrors the meltdown behavior:
/// - reads HealthKit totals for today
/// - filters manual and unknown recording methods
/// - applies per-tick HC smoothing to avoid sync spikes
class IosHealthStepDetector {
  final Health _health;
  final StreamController<StepCountEvent> _controller =
      StreamController<StepCountEvent>.broadcast();

  Timer? _pollTimer;
  int _lastSmoothed = 0;
  int _lastReadAtMs = 0;

  IosHealthStepDetector({Health? health}) : _health = health ?? Health();

  Stream<StepCountEvent> get stepEventStream => _controller.stream;

  int get currentStepCount => _lastSmoothed;

  Future<void> start() async {
    await _health.configure();
    final granted = await _health.requestAuthorization(
      const [HealthDataType.STEPS],
      permissions: const [HealthDataAccess.READ],
    );
    if (!granted) {
      throw StateError('HealthKit step permission not granted');
    }

    await _pollAndEmit();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollAndEmit());
    });
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> dispose() async {
    await stop();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<bool> hasStepPermission() async {
    await _health.configure();
    final result = await _health.hasPermissions(
      const [HealthDataType.STEPS],
      permissions: const [HealthDataAccess.READ],
    );
    return result ?? false;
  }

  void reset() {
    _lastSmoothed = 0;
    _lastReadAtMs = 0;
  }

  Future<void> _pollAndEmit() async {
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final incoming = await _readFiltered(startOfToday, now);
      final smooth = smoothHcReading(
        HcSmoothingInputs(
          incomingHc: incoming,
          previousHc: _lastSmoothed,
          nowMs: now.millisecondsSinceEpoch,
          previousReadMs: _lastReadAtMs,
        ),
      );
      if (smooth.updateRecorded) {
        _lastSmoothed = incoming;
        _lastReadAtMs = now.millisecondsSinceEpoch;
      }
      final displayed = smooth.displayed;
      if (!_controller.isClosed) {
        _controller.add(
          StepCountEvent(
            stepCount: displayed,
            timestamp: now.toUtc(),
            confidence: 1.0,
          ),
        );
      }
    } catch (_) {
      // Keep polling; callers can still consume SQLite totals.
    }
  }

  Future<int> _readFiltered(DateTime start, DateTime end) async {
    try {
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
        recordingMethodsToFilter: const [
          RecordingMethod.manual,
          RecordingMethod.unknown,
        ],
      );
      var total = 0;
      for (final point in points) {
        final value = point.value;
        if (value is NumericHealthValue) {
          total += value.numericValue.toInt();
        }
      }
      return total;
    } catch (_) {
      final total = await _health.getTotalStepsInInterval(
        start,
        end,
        includeManualEntry: false,
      );
      return total ?? 0;
    }
  }
}
