/// Pure logic functions for step counter merge / day rollover decisions.
/// Extracted for unit testing — no Flutter / platform dependencies.
class StepLogic {
  /// Threshold above which sensor is considered to be overcounting versus HC.
  /// 1.10 means sensor exceeds HC by 10% or more — tightened from 1.20 after
  /// Apr 27 Samsung A07 reported 122% over G-Fit (today=9356 vs G-Fit=4211).
  /// At 1.20 the trigger was too loose: a 19% inflation bypassed the cap and
  /// compounded across the day. 1.10 is comfortably above HC/sensor sampling
  /// jitter (typically <5%) while catching Samsung-class drift early.
  static const double overcountingThreshold = 1.10;

  /// Minimum monotonic milliseconds before allowing a backward day change.
  /// Below this, the change is considered suspicious time manipulation.
  static const int minBackwardDayChangeMs = 20 * 3600 * 1000;

  /// Server step value sanity ceiling — any value above this is rejected.
  static const int maxReasonableSteps = 80000;

  /// Lower bound of the HC/sensor ratio band that flags HC as duplicated.
  /// Below this HC is naturally higher than sensor (HC delay, lost sensor
  /// events, sensor in pocket missing some steps) — accept HC normally.
  /// At/above triggers duplication suspicion (May 19 Samsung A07: sensor
  /// 2600, G-Fit truth 2766, HC sum after G-Fit open 5412 = sensor * 2.08).
  static const double hcDuplicationRatio = 1.5;

  /// Upper bound of the duplication band. Past this, HC genuinely has more
  /// data than sensor (typical early-day case: user walked before granting
  /// ACTIVITY_RECOGNITION so sensor missed those steps but HC tracked them
  /// via Samsung Health / a fitness band). Returning to HC keeps us
  /// truthful in that scenario rather than blanking out morning walks.
  static const double hcDuplicationUpperRatio = 2.5;

  /// Minimum sensor count before we trust it as ground truth for HC dedup.
  /// Early in the day a tiny sensor reading could legitimately be dwarfed by
  /// HC (e.g. user walked before granting ACTIVITY_RECOGNITION). Below this
  /// threshold we skip the dedup branch and let HC win.
  static const int hcDuplicationMinSensor = 100;

  /// Compute merged step value from HC and native sensor.
  ///
  /// Priority of signals:
  ///   1. **HC duplication** — when HC sum is wildly inflated vs the hardware
  ///      sensor (>= [hcDuplicationRatio] above sensor while sensor itself is
  ///      already past [hcDuplicationMinSensor]), HC is summing duplicates from
  ///      multiple data sources. Trust sensor. (May 19 Samsung A07 case.)
  ///   2. **Sensor overcount** — sensor reads above HC by >= overcounting
  ///      threshold; trust HC and reset the inflated floor.
  ///   3. **HC live, normal range** — accept HC's value (even downward) as
  ///      authoritative; sensor can still raise but the floor is *not* used
  ///      to pin against HC corrections (May 19 obs 8 — rapid-shaking
  ///      transient HC spike correcting downward).
  ///   4. **HC missing, sensor live** — sensor with floor protection against
  ///      jitter/HC delay.
  ///   5. **Both 0** — hold floor.
  ///
  /// Server-recovered floor is always honored as a hard lower bound.
  static StepMergeResult mergeSteps({
    required int hcSteps,
    required int sensorSteps,
    required int currentFloor,
    required int serverRecovered,
  }) {
    bool overcounting = false;
    bool hcDuplicated = false;
    int merged;
    int newFloor = currentFloor;
    int newServerRecovered = serverRecovered;

    final hcLooksDuplicated = sensorSteps >= hcDuplicationMinSensor &&
        hcSteps > sensorSteps * hcDuplicationRatio &&
        hcSteps < sensorSteps * hcDuplicationUpperRatio;
    final sensorLooksOvercounted = hcSteps > 0 &&
        sensorSteps > hcSteps * overcountingThreshold &&
        !hcLooksDuplicated;

    if (hcLooksDuplicated) {
      // HC is summing duplicates from multiple sources — trust the local
      // hardware sensor. Don't reset the floor here: future legitimate HC
      // recoveries should still pin against the existing baseline.
      hcDuplicated = true;
      merged = sensorSteps;
    } else if (sensorLooksOvercounted) {
      // Sensor overcounting — trust HC and reset inflated floors
      overcounting = true;
      merged = hcSteps;
      if (currentFloor > hcSteps * overcountingThreshold) {
        newFloor = hcSteps;
        newServerRecovered = 0;
      }
    } else if (hcSteps > 0) {
      // HC has live data — let it correct downward without floor interference
      // (May 19 obs 8 — G-Fit spike during shaking then self-corrects, the
      // displayed floor was pinning us to the inflated value). Sensor can still
      // raise above HC if it tracks slightly ahead.
      merged = hcSteps > sensorSteps ? hcSteps : sensorSteps;
    } else if (sensorSteps > 0) {
      // No HC — sensor with monotonic floor protection so a transient zero or
      // HC delay can't make the displayed count jitter downward.
      merged = sensorSteps > newFloor ? sensorSteps : newFloor;
    } else {
      // Both sources are silent — hold whatever the floor remembers.
      merged = newFloor;
    }

    // Server-recovered floor is the hard lower bound regardless of branch
    // (after overcount reset that value is 0, after duplication it's the
    // current value — both safe).
    if (merged < newServerRecovered) merged = newServerRecovered;

    return StepMergeResult(
      todaySteps: merged,
      newFloor: merged > newFloor ? merged : newFloor,
      newServerRecovered: newServerRecovered,
      overcountingDetected: overcounting,
      hcDuplicationDetected: hcDuplicated,
    );
  }

  /// Merge yesterday's step value from HC and native sensor.
  ///
  /// Yesterday is historical data — once it's set, the user expects it to
  /// stay put. The today path uses MAX-with-overcount-correction, which is
  /// fine for live counts where overshoots can be corrected. For yesterday
  /// that policy was wrong: a sensor that overcounted through yesterday's
  /// evening kept inflating the value the user already saw last night
  /// (Apr 27 Bug 3 — yesterday changed from 6142 to 11099 retroactively).
  ///
  /// Policy:
  ///   - If HC has a value (>0) for yesterday, trust HC and ignore sensor.
  ///     HC is the cross-source-of-truth and won't drift the way Samsung
  ///     TYPE_STEP_COUNTER does.
  ///   - If HC is missing, fall back to sensor only when it's plausible
  ///     (`<= maxReasonableSteps`), otherwise return 0 rather than display
  ///     a clearly broken number.
  ///   - If both sources are zero, keep `currentYesterday` so a freshly cold-
  ///     started cubit doesn't blank out the value the previous session had
  ///     already restored from prefs / server.
  /// Maximum drift ratio yesterday's value is allowed to take in a single
  /// merge cycle. Yesterday is historical; once the user saw a value last
  /// night, it shouldn't suddenly jump by 30%+ today. Anything outside the
  /// [1/yesterdayStabilityRatio, yesterdayStabilityRatio] band is rejected
  /// in favour of the existing value (May 26 obs 2 — QA saw yesterday
  /// move from 10619 to 16308 because today's inflated value rolled over
  /// into the yesterday slot during midnight rotation).
  static const double yesterdayStabilityRatio = 1.30;

  static int mergeYesterday({
    required int hcYesterday,
    required int sensorYesterday,
    required int currentYesterday,
  }) {
    // Same HC-duplication guard as today's merge: if HC's yesterday value is
    // wildly above what our hardware sensor saw, HC is summing duplicates
    // (May 19 obs 3 — yesterday changed from 8689 to 9133 after new install
    // because HC was being preferred and HC had extra source records).
    final hcLooksDuplicated = sensorYesterday >= hcDuplicationMinSensor &&
        hcYesterday > sensorYesterday * hcDuplicationRatio &&
        hcYesterday < sensorYesterday * hcDuplicationUpperRatio;
    if (hcLooksDuplicated) {
      return sensorYesterday;
    }

    // Stability lock — *asymmetric*: only reject upward drift beyond
    // [yesterdayStabilityRatio]. Honour HC's downward corrections (audit
    // finding May 28: a symmetric lock would cement an overcount once
    // currentYesterday was set to a wrong-high value). The May 26
    // obs 2 scenario is purely upward (10619 stable, HC tries to bump to
    // 16308 after rotation promoted inflated today), so the asymmetric
    // rule still catches it.
    if (currentYesterday > 0 &&
        hcYesterday > currentYesterday * yesterdayStabilityRatio) {
      return currentYesterday;
    }

    if (hcYesterday > 0) return hcYesterday;
    if (sensorYesterday > 0 && sensorYesterday <= maxReasonableSteps) {
      return sensorYesterday;
    }
    return currentYesterday;
  }

  /// Returns true if [toDate] is chronologically before [fromDate].
  /// Both dates must be ISO 8601 format strings (yyyy-MM-dd) for
  /// lexicographic comparison to match chronological order.
  static bool isBackwardDayChange(String fromDate, String toDate) {
    return toDate.compareTo(fromDate) < 0;
  }

  /// Decide whether a day rollover should be accepted given the new date,
  /// the saved session date, the last rollover timestamp, and the current
  /// timestamp. Forward changes always allowed; backward only if the previous
  /// rollover was sufficiently long ago (anti time-manipulation).
  static bool shouldAcceptDayChange({
    required String currentDate,
    required String sessionDate,
    required int lastRolloverMs,
    required int currentMs,
  }) {
    if (currentDate == sessionDate) return false; // No change
    final isBackward = isBackwardDayChange(sessionDate, currentDate);
    if (!isBackward) return true; // Forward = always allowed

    // Backward: allow only if old enough (positive elapsed needed; negative
    // elapsed indicates clock went backward — block as suspicious)
    final elapsed = currentMs - lastRolloverMs;
    if (lastRolloverMs == 0) return true; // First ever rollover
    if (elapsed < 0) return false; // Time went backward — block
    return elapsed >= minBackwardDayChangeMs;
  }

  /// Reject server-recovered values that exceed the sanity ceiling.
  /// Returns 0 for unreasonable values, otherwise the input.
  static int sanitizeServerSteps(int serverSteps) {
    if (serverSteps > maxReasonableSteps) return 0;
    if (serverSteps < 0) return 0;
    return serverSteps;
  }

  /// Compute day difference accounting for year boundaries (Dec 31 -> Jan 1).
  /// Returns 0 for same day, 1 for next day, etc. Returns 999 for multi-year gaps.
  static int dayDifference({
    required int savedYear,
    required int savedDayOfYear,
    required int currentYear,
    required int currentDayOfYear,
    required int savedYearMaxDays,
  }) {
    if (savedYear == currentYear) {
      return currentDayOfYear - savedDayOfYear;
    } else if (currentYear == savedYear + 1) {
      return (savedYearMaxDays - savedDayOfYear) + currentDayOfYear;
    } else if (currentYear < savedYear) {
      return -1; // Backward in time
    } else {
      return 999; // Multi-year gap
    }
  }
}

/// Sliding-window rate limiter — pure mirror of the Kotlin sustained-rate
/// guard in `StepCounterService.onSensorChanged`.
///
/// Exists in Dart to unit-test the algorithm. The native side enforces the
/// real cap on raw sensor events; this class documents and verifies the
/// behaviour we expect there. If you change one, change both.
///
/// Caps the number of steps accepted within any trailing `windowMs` to
/// `maxStepsPerWindow`. Used to defend against well-known TYPE_STEP_COUNTER
/// overcounting on certain Samsung devices (Apr 17 QA observation 5: A07
/// reporting 75% above ground truth from Google Fit; Apr 27/May 10 the same
/// device hit 98%-122% drift, prompting the layered hourly cap below).
///
/// For the layered minute+hour native scheme, instantiate two limiters:
/// one with the per-minute cap and one with the per-hour cap. A step is
/// accepted only if both `admit` calls return >0 (use the smaller).
class StepRateLimiter {
  final int maxStepsPerWindow;
  final int windowMs;
  final List<MapEntry<int, int>> _entries = <MapEntry<int, int>>[];
  int _total = 0;

  StepRateLimiter({
    this.maxStepsPerWindow = 180,
    this.windowMs = 60 * 1000,
  });

  /// Returns how many of [requested] steps are accepted at monotonic [nowMs].
  /// Any rejected steps are dropped (not deferred) to mirror the Kotlin path.
  int admit(int nowMs, int requested) {
    if (requested <= 0) return 0;
    _prune(nowMs);
    final accepted = (_total + requested > maxStepsPerWindow)
        ? (maxStepsPerWindow - _total).clamp(0, requested)
        : requested;
    if (accepted > 0) {
      _entries.add(MapEntry(nowMs, accepted));
      _total += accepted;
    }
    return accepted;
  }

  /// Current sum of accepted steps inside the trailing window.
  int get currentTotal {
    return _total;
  }

  void _prune(int nowMs) {
    while (_entries.isNotEmpty && nowMs - _entries.first.key > windowMs) {
      _total -= _entries.first.value;
      _entries.removeAt(0);
    }
    if (_total < 0) _total = 0;
  }

  void reset() {
    _entries.clear();
    _total = 0;
  }
}

/// Result of step merge computation.
class StepMergeResult {
  final int todaySteps;
  final int newFloor;
  final int newServerRecovered;
  final bool overcountingDetected;
  /// HC was rejected as containing duplicate records (May 19 obs 1) — the
  /// returned value comes from the hardware sensor.
  final bool hcDuplicationDetected;

  const StepMergeResult({
    required this.todaySteps,
    required this.newFloor,
    required this.newServerRecovered,
    required this.overcountingDetected,
    this.hcDuplicationDetected = false,
  });
}
