# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-07-26

### Breaking

- **Primary detection is now TYPE_STEP_COUNTER FGS on all Android API 24+** (including Samsung). Previous API≤29 / non-Samsung gate removed.
- **`SmartMergeHelper.mergeStepCounts` semantics changed** — no longer naive `max()`. Uses `StepLogic` (HC duplication band, sensor overcount at 1.10×, HC can correct downward, server floor). Prefer `SmartMergeHelper.merge()` for full `MergeDecision` flags.
- Legacy auto-start of `StepCounterForegroundService` on app termination is **off by default** to prevent dual-FGS fights.
- `StepDetectorConfig.useForegroundServiceOnOldDevices` defaults to **false** (legacy sensors_plus fallback only).

### Added

- Production-hardened `StepCounterService`: prefs persist, reboot detect, burst/minute/hour caps with baseline fold-in, vehicle/bicycle Activity Recognition filter, TYPE_STEP_DETECTOR cross-check, exact midnight alarm, BootReceiver, TimeChangeReceiver, rotation stamps
- `ActivityClassifier` + soft-fail without Play Services (`play-services-location`)
- Dart policies: `StepLogic`, `MergePolicy`, `smoothHcReading`, `RotationGuard`, `StepRateLimiter`
- Platform APIs: `setNotificationDisplay`, `forceUpdateTodaySteps`, `consumeLastRotation`, `resetNativeStepState`
- **`startTracking()`** — one-call setup (DB + FGS + aggregated logging)
- Short aliases: `isBatteryOptimized()`, `requestBatteryOptimization()`
- Safe calibration from SQLite today (sensor=0, seed ≤40k) on start
- Native↔SQLite reconcile on aggregated start (fixes undercount after process death)
- Rotation drain on start / resume / step stream
- Ported production policy unit tests under `test/policy/`
- Soft `uses-feature` for stepcounter/stepdetector (`required=false`)
- Consumer ProGuard keep rules for services/receivers

### Fixed (production DX / hardening)

- Skip legacy terminated-prefs sync when the native FGS is available (no dual recovery)
- Example + verification check TYPE_STEP_COUNTER FGS, not fallback detector
- Removed 500ms artificial delay from `initSteps` (now aliases `startTracking`)
- Collapsed duplicate `getTodaySteps` / `getYesterdaySteps` definitions
- Cold-start day-gap restore stamps `KEY_LAST_ROTATION_*` and persists rotated prefs
- Activity Recognition PendingIntent uses explicit component + unique request code; receiver in manifest
- Removed Play-risk permissions `USE_EXACT_ALARM`, `BODY_SENSORS`, `BODY_SENSORS_BACKGROUND`, `HIGH_SAMPLING_RATE_SENSORS`
- Plugin no longer permanently registers a second `TYPE_STEP_COUNTER` listener (battery)
- Kotlin unit test matches real MethodChannel API
- `NotificationChannel` creation guarded for API 24–25 (`StepCounterService`)
- `dispose()` / `stopLogging()` flush write buffer and cancel flush timer

### Migration

1. Bump to `^3.0.0` and request `ACTIVITY_RECOGNITION` + notifications before `startTracking()`.
2. Prefer `await steps.startTracking()` over the old three-call sequence.
3. If you relied on naive max merge, switch to `SmartMergeHelper.merge(...)` and handle `MergeDecision`.
4. Keep notification synced with `setNativeNotificationDisplay(merged)` — do **not** force-write merged HC into sensor baseline.
5. Supply HC/server yourself (BYO); package does not embed Health Connect SDK.

## [2.0.0] - 2026-02-28

### Major: Native Step Service + Smart Merge

This release promotes the native `TYPE_STEP_COUNTER` foreground service as the primary detection strategy and adds the **SmartMergeHelper** utility for combining multiple step sources.

### Added
- **SmartMergeHelper** — combine sensor + Health Connect + server (naive max in 2.x)
- **Native Step Service Status API** — `isNativeStepServiceRunning()`, `isUsingNativeStepService`

### Changed
- VERSION BUMP to 2.0.0
- README rewritten for TYPE_STEP_COUNTER architecture

### Fixed
- `StepCounterService.kt` — added `isRunning` flag

### Removed
- Stale Hive artifacts

---

## [1.9.5] - 2026-02-22

### Fixed
- Background isolate `sqflite` initialization error — Added `DartPluginRegistrant.ensureInitialized()` to isolate entry point

## [1.9.4] - 2026-02-22

### Added
- Terminated sync gap reconciliation with idempotent deterministic gap keys
- Single-flight terminated sync to prevent concurrent reprocessing
- Production example flow in example app

## [1.9.3] - 2026-02-03

### Added
- Automatic 30-day log retention policy
- Database write batching (3-second buffer)
- Background isolate for database operations (`StepRecordConfig.lowEndDevice()`)
- Stream emission throttling (max 10Hz)

## [1.9.2] - 2026-02-03

### Fixed
- Samsung ANR mitigation (auto-disables foreground service on Samsung Android 11+)
- Midnight step distribution across day boundaries
- Async database logging (moved to non-blocking operations)

### Removed
- `device_info_plus` dependency (replaced with native platform channel)

## [1.9.1] - 2026-01-28

### Verified
- ANR-safe architecture audit: all Kotlin I/O on `Dispatchers.IO`, async SharedPreferences, background SQLite

## [1.9.0] - 2026-01-28

### Changed
- **Database migration: Hive → sqflite** — Indexed SQL queries, smaller footprint, no code generation needed

### Removed
- Hive dependencies (`hive`, `hive_flutter`, `hive_generator`, `build_runner`)

## [1.8.12] and earlier

See git history for pre-1.9.0 notes.
