/// Inputs to a single HC smoothing decision.
class HcSmoothingInputs {
  final int incomingHc;
  final int previousHc;
  final int nowMs;
  final int previousReadMs;
  /// Max realistic HC growth per second between two reads. Default 6 covers
  /// even sprinting; Google Fit syncs that dump 10000+ steps in 15s easily
  /// exceed it and get deferred.
  final int maxStepsPerSecond;
  /// Slack added on top of `elapsedSec * maxStepsPerSecond` to absorb
  /// poll-interval jitter.
  final int jitterCushion;

  const HcSmoothingInputs({
    required this.incomingHc,
    required this.previousHc,
    required this.nowMs,
    required this.previousReadMs,
    this.maxStepsPerSecond = 6,
    this.jitterCushion = 100,
  });
}

/// Decision returned by [smoothHcReading].
///
/// `displayed` is the value the engine should treat as the current HC reading;
/// `updateRecorded` says whether the smoother accepted the value (caller
/// must overwrite previousHc/previousReadMs) or deferred it (caller must
/// leave the recorded values untouched so the next call can re-evaluate).
class HcSmoothingDecision {
  final int displayed;
  final bool updateRecorded;
  final bool deferred;
  const HcSmoothingDecision({
    required this.displayed,
    required this.updateRecorded,
    required this.deferred,
  });
}

/// Pure HC sync-event smoother.
///
/// HC can "catch up" with backlogged sensor + Google-Fit data and dump
/// thousands of steps into a single read. The smoother detects readings
/// that imply a growth rate above the realistic ceiling and holds the
/// previous value for one tick. If the new value persists across the next
/// read it'll be accepted (delta from the recorded previous is small).
HcSmoothingDecision smoothHcReading(HcSmoothingInputs i) {
  final elapsedMs = i.nowMs - i.previousReadMs;
  if (i.previousReadMs == 0 || elapsedMs <= 0) {
    // First read or clock anomaly — accept.
    return HcSmoothingDecision(
      displayed: i.incomingHc,
      updateRecorded: true,
      deferred: false,
    );
  }
  final delta = i.incomingHc - i.previousHc;
  final elapsedSec = (elapsedMs / 1000).ceil();
  final maxAllowedDelta = elapsedSec * i.maxStepsPerSecond + i.jitterCushion;
  if (delta > maxAllowedDelta) {
    return HcSmoothingDecision(
      displayed: i.previousHc,
      updateRecorded: false,
      deferred: true,
    );
  }
  return HcSmoothingDecision(
    displayed: i.incomingHc,
    updateRecorded: true,
    deferred: false,
  );
}
