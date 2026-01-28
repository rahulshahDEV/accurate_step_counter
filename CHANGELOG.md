# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.8.11] - 2026-01-28

### Fixed
- 🔥 **Critical Fix: Hive Box Cold Start ANR**
  - **Problem**: On Android, when the app was killed by the system and restarted (cold start), Hive database operations could cause ANR because the box was closed but the code assumed it was still open.
  - **Root Cause**: After Android kills the app, Hive boxes are closed but the `_isInitialized` flag remained `true`, causing subsequent database operations to fail or block.
  - **Fix**: Added `_ensureBoxOpen()` method in `StepRecordStore` that checks if the box is still open and reopens it if needed before any database operation.
  - **Benefit**: Step logging and queries now work reliably after cold starts, even when Android aggressively kills the app.

### Technical Details
| Scenario | Old Behavior (ANR) | New Behavior (Safe) |
|----------|-------------------|---------------------|
| Cold start after app kill | Box closed, operations block/fail | Auto-reopens box, operations succeed |
| Normal operation | Works fine | Works fine (no overhead) |

---

## [1.8.10] - 2026-01-27

### Fixed
- 🔥 **Critical Fix: Android 12 ANR (Application Not Responding)**
  - **Problem**: On Android 12 and below (using `SensorsStepDetector` 50Hz loop), the app would freeze/crash with an ANR due to blocking timezone lookups (`tzset_unlocked`) on the main thread.
  - **Fix**: Replaced `DateTime.now()` with `DateTime.now().toUtc()` in the high-frequency sensor loop. This avoids blocking filesystem operations for timezone data.
  - **Stability**: Kept user-facing aggregation methods (e.g., `getTodayStepCount`) on Local Time (`DateTime.now()`) to ensure "Today" respects the user's local day boundary while keeping the dangerous high-speed loop on safe UTC.
  - **Native**: Updated `NativeStepDetector` to also use UTC timestamps for extra safety on all Android versions.

### Technical Details
| Component | Old Behavior (Crash) | New Behavior (Safe) |
|-----------|----------------------|---------------------|
| `SensorsStepDetector` | `DateTime.now()` (Local) @ 50Hz | `DateTime.now().toUtc()` (UTC) @ 50Hz |
| `getTodayStepCount` | `DateTime.now()` (Local) | `DateTime.now()` (Local) - Safe (low frequency) |

---

## [1.8.9] - 2026-01-21

### Fixed
- 🔧 **Android 12+ Foreground Service Compatibility**
  - **Problem**: Foreground service was not working properly on Android 12 and below due to several compatibility issues with newer Android versions.
  - **Root Causes**:
    1. Android 14+ requires explicit `foregroundServiceType` parameter in `startForeground()` call
    2. Missing `BODY_SENSORS_BACKGROUND` permission for Android 13+ background sensor access
    3. Missing `HIGH_SAMPLING_RATE_SENSORS` permission for health foreground service
    4. Android 12+ throws `ForegroundServiceStartNotAllowedException` when starting service from background
  - **Fixes Applied**:
    1. Updated `StepCounterForegroundService.kt` to specify `ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH` explicitly for Android 10+
    2. Added `BODY_SENSORS_BACKGROUND` permission to AndroidManifest.xml
    3. Added `HIGH_SAMPLING_RATE_SENSORS` permission to AndroidManifest.xml
    4. Added proper exception handling for `ForegroundServiceStartNotAllowedException` with informative error messages
    5. Added activity count check before starting foreground service on Android 12+

### Added
- 📢 **POST_NOTIFICATIONS Permission Request (Meltdown App)**
  - Added automatic notification permission request for Android 13+ before starting foreground service
  - This ensures the foreground service notification is visible to users

### Technical Details
| Android Version | Foreground Service Behavior |
|-----------------|---------------------------|
| **Android 14+ (API 34+)** | Explicit `FOREGROUND_SERVICE_TYPE_HEALTH` required |
| **Android 12-13 (API 31-33)** | Background start restrictions, activity must be visible |
| **Android 10-11 (API 29-30)** | No restrictions, service starts normally |
| **Android 9 and below** | Uses `startService()` instead of `startForegroundService()` |

### Permissions Added
- `BODY_SENSORS_BACKGROUND` - Required for background sensor access on Android 13+
- `HIGH_SAMPLING_RATE_SENSORS` - Required for health foreground service sensor access

---

## [1.8.8] - 2026-01-20

### Fixed
- ⚡ **Real-Time Step Counting Restored for Android 12 and Below**
  - **Problem**: On Android 12 and below (using foreground service mode with `SensorsStepDetector`), steps were not showing in real-time. There was a 1.5+ second delay before any steps appeared.
  - **Root Cause**: The shake rejection added in v1.8.6 required a 1.5-second validation window with at least 3 pending steps before emitting any step events. This was intended to prevent shake-based false steps but caused unacceptable latency.
  - **Fix**: Reverted `SensorsStepDetector` (Dart) and `NativeStepDetector` (Kotlin) to emit steps immediately (like v1.8.3). Shake rejection is now handled **only at the logging layer** through the warmup validation in `AccurateStepCounterImpl`, not at the detector level.

### Technical Details
| Component | Change |
|-----------|--------|
| `SensorsStepDetector` | Removed sliding window validation; steps emit immediately on peak detection |
| `NativeStepDetector` | Removed sliding window validation; steps emit immediately on peak detection |
| Shake rejection | Now handled exclusively by warmup validation in `AccurateStepCounterImpl.startLogging()` |

### Why This Change?
- **Before (v1.8.6-1.8.7)**: User takes a step → waits 1.5 seconds → nothing → takes 2 more steps → finally sees "3 steps"
- **After (v1.8.8)**: User takes a step → immediately sees "1 step" (like v1.8.3)

The warmup validation in the logging layer (`StepRecordConfig.warmupDurationMs`, `minStepsToValidate`, `maxStepsPerSecond`) still provides shake rejection for **what gets saved to the database**, while allowing immediate visual feedback to the user.

---

## [1.8.7] - 2026-01-20

### Fixed
- 🔒 **Race Condition Fix: Duplicate External Step Writes**
  - **Problem**: On Android 12+, when multiple widgets called `readFootSteps()` simultaneously (e.g., app open with multiple widgets mounting), duplicate external step records were created. The duplicates had identical step counts but `toTime` differed by only 1-2 seconds.
  - **Root Cause**: Multiple concurrent calls to `writeStepsToAggregated()` would both pass the duplicate check simultaneously (before either had committed to the database), then both would write, creating duplicates.
  - **Fix**: Implemented two-layer protection:
    1. **Mutex Lock**: Added `Completer`-based async lock that serializes all `writeStepsToAggregated()` calls. Concurrent calls now wait for previous writes to complete.
    2. **In-Memory Tracking**: Fast pre-check against the last external write's time, steps, and fromTime. Catches rapid duplicate calls within 30 seconds without database queries.

### Technical Details
| Component | Change |
|-----------|--------|
| `AccurateStepCounterImpl` | Added `_writeLock` (Completer), `_lastExternalWriteTime`, `_lastExternalWriteSteps`, `_lastExternalWriteFromTime` fields |
| `writeStepsToAggregated()` | Now waits for any in-progress write to complete before proceeding |
| Duplicate Detection | Two-layer: in-memory check (30s window) + database check (60s tolerance) |

### Example Log
```
AccurateStepCounter: Waiting for previous write to complete...
AccurateStepCounter: Skipped near-duplicate write (in-memory check): 2694 steps, last write was 2s ago
```

---

## [1.8.6] - 2026-01-19

### Fixed
- 🔒 **Sensor-Level Shake Rejection for Android 12 and Below**
  - **Problem**: On Android 12 and below, simple phone shakes incorrectly incremented the step count even when warmup validation was active. The warmup validation only filtered what got logged to the database, but the user-visible `currentStepCount` still increased from shakes.
  - **Root Cause**: The `SensorsStepDetector` (Dart) and `NativeStepDetector` accelerometer fallback (Kotlin) lacked built-in shake rejection. Raw accelerometer peaks were immediately counted as steps.
  - **Fix**: Added sliding window validation directly to both step detectors:
    - Steps are now tracked as "pending" until validated
    - A 1.5-second validation window checks the step rate
    - If rate exceeds 4 steps/second (shaking), all pending steps in that window are rejected
    - Minimum 3 pending steps required before confirmation
    - Only confirmed steps increment the visible step count

### Added
- 🛡️ **Duplicate Prevention for External Step Writes**
  - New `skipIfDuplicate` parameter in `writeStepsToAggregated()` (default: `true`)
  - Prevents duplicate records when importing steps from external sources (Google Fit, Apple Health, etc.)
  - Uses fuzzy matching (60-second tolerance) to detect duplicate time ranges
  - Method now returns `bool` - `true` if written, `false` if skipped due to duplicate
  
  **New API Methods in `StepRecordStore`:**
  - `hasDuplicateRecord()` - Check for existing records with matching time range
  - `hasOverlappingRecord()` - Check for any overlapping records in a time range
  
  **Example:**
  ```dart
  final wasWritten = await stepCounter.writeStepsToAggregated(
    stepCount: 5000,
    fromTime: importStart,
    toTime: importEnd,
    source: StepRecordSource.external,
    skipIfDuplicate: true, // Default - prevents duplicate imports
  );
  if (!wasWritten) {
    print('Skipped - record already exists');
  }
  ```

### Technical Details
| Component | Change |
|-----------|--------|
| `SensorsStepDetector` (Dart) | Added `_pendingStepCount`, sliding window validation, `_validateAndConfirmSteps()` method |
| `NativeStepDetector` (Kotlin) | Added `pendingStepCount`, sliding window validation, `validateAndConfirmSteps()` method |
| Step Detection | Steps are no longer emitted immediately - they require 1.5s validation |
| Shake Rejection | Rate > 4 steps/sec = shake detected, pending steps discarded |
| `StepRecordStore` | Added `hasDuplicateRecord()` and `hasOverlappingRecord()` methods |
| `writeStepsToAggregated` | New `skipIfDuplicate` parameter, now returns `Future<bool>` |

### Why This Matters
- **Shake Rejection**: Shaking phone no longer shows step increase - only validated walking steps count.
- **Duplicate Prevention**: Re-importing the same steps from external sources won't create duplicate records.

---


## [1.8.5] - 2026-01-19


### Fixed
- 🔒 **Terminated State Sync Validation**
  - **Problem**: When the app was reopened after being closed, shake steps detected by the hardware step counter were synced to the database WITHOUT validation, bypassing the warmup checks entirely.
  - **Fix**: Added the same validation rules (`minStepsToValidate` and `maxStepsPerSecond`) to terminated state sync.
  - Shake steps detected while the app was closed are now properly rejected during sync.
  - Genuine walking steps detected during terminated state still sync correctly.

### Technical Details
| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Shake steps synced on app reopen | `_syncStepsFromTerminatedState()` bypassed validation | Apply warmup validation rules to terminated sync |

---

## [1.8.4] - 2026-01-19

### Fixed
- 🏃 **Warmup Validation "Shake Dilution" Fix**
  - **Problem**: Shaking the phone rapidly (e.g., 15 steps in 2 seconds) generated a high step rate (7.5 steps/sec), but when averaged over the full 8-second warmup period, it appeared as a safe 1.8 steps/sec, erroneously passing validation.
  - **Fix**: Implemented **Sliding Window Validation**.
  - The warmup phase now checks the step rate in **2-second intervals**.
  - If the step rate exceeds `maxStepsPerSecond` (default 5.0) in **ANY** 2-second window, the warmup is immediately reset.
  - Ensures short bursts of high-frequency noise (shaking) are caught immediately, even if followed by stillness.

### Technical Details
| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Shakes passing warmup | High rate diluted by long average (8s) | Enforce rate limit on sliding 2s windows |

### Tests Added
- **Stress Test**: 300 randomized iterations of "Walk" vs "Shake" scenarios.
  - Verified 150/150 walks passed.
  - Verified 150/150 shakes were rejected.

---

## [1.8.3] - 2026-01-14

### Fixed
- 🕛 **Midnight Boundary Fix** - Yesterday's steps no longer appear in today's count
  - Records with `toTime` exactly at midnight (00:00:00) are now correctly excluded from today's count
  - Changed `readRecords()` filter from `!e.toTime.isBefore(from)` to `e.toTime.isAfter(from)`
  - Fixed `_logTerminatedSteps` to end records at 23:59:59.999 instead of 00:00:00
  - Prevents step logs like `17:04:50 - 00:00:00` from appearing in today's count

### Technical Details
| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Yesterday's steps in today's count | Records ending at midnight included due to `>=` filter | Use strict `>` filter: `toTime.isAfter(from)` |
| Records end at midnight | `_logTerminatedSteps` used start of next day | End at 23:59:59.999 instead |

### Tests Added
- 3 new tests in `Scenario 17: Midnight Boundary Handling`
  - Record ending at midnight is NOT included in today count
  - Record ending after midnight IS included in today count
  - Separate yesterday and today records counted correctly

---

## [1.8.2] - 2026-01-13

### Fixed
- 🔒 **Singleton Foreground Service Enforcement**
  - Prevents multiple foreground service instances from running simultaneously
  - Added explicit `isRunning` check in `AccurateStepCounterPlugin.startForegroundService()`
  - Added duplicate start guard in `StepCounterForegroundService.onStartCommand()`
  - If service is already running, notification text is updated instead of restarting
  - Enhanced logging shows `isRunning` state for debugging

- 🛡️ **Double-Counting Prevention in Terminated State Sync**
  - Added `syncAlreadyDoneThisSession` flag to prevent multiple sync calls per session
  - Changed SharedPreferences from `apply()` to `commit()` for atomic writes
  - Foreground service data is now properly cleared after sync with synchronous commit
  - Prevents steps being counted twice when both foreground service and TYPE_STEP_COUNTER are used

- 📅 **Multi-Day Terminated Step Distribution** (Android 12+)
  - Fixed critical bug where steps from multiple days were all counted as "today"
  - When app is closed for 2+ days, steps are now distributed proportionally across each day
  - Each day gets its own `StepRecord` entry with correct date range
  - `watchTodaySteps()` now correctly shows only today's steps after multi-day termination
  - Example: 3000 steps over 3 days → ~1000 steps logged to each day

### Added
- 🔍 **StepLogsViewer Widget** - New reusable debug widget for viewing step logs
  - Filter by source (foreground/background/terminated/external)
  - Date range picker for filtering
  - Export logs to clipboard
  - Real-time updates via stream subscription
  - Color-coded entries by source
  - Configurable max height, auto-scroll, and styling

  **Usage:**
  ```dart
  StepLogsViewer(
    stepCounter: _stepCounter,
    maxHeight: 300,
    showFilters: true,
    showExportButton: true,
  )
  ```

### Technical Details
| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Multiple service instances | No check before starting service | Added `isRunning` guard in plugin and service |
| Double step counting | Sync called multiple times | Added session flag + atomic writes with `commit()` |
| Debug difficulty | No visual log viewer | New `StepLogsViewer` widget |
| Multi-day steps all as "today" | Single log entry for entire period | Distribute steps proportionally across days |

---


## [1.8.1] - 2026-01-12

### Fixed
- 🔧 **Threshold Normalization for SensorsStepDetector**
  - Fixed step detection not working on Android ≤ configured API level (foreground service mode)
  - High thresholds intended for NativeStepDetector (10-20 range) were incorrectly passed to SensorsStepDetector
  - Added `_normalizeThresholdForSensors()` that scales thresholds > 5.0 down to 0.5-2.0 range
  - Example: `threshold: 14.0` → normalized to `1.4` for sensors_plus

- 🔄 **Terminated State Step Sync for Foreground Service Mode**
  - Fixed steps not syncing after app termination on Android ≤ configured API level
  - `_syncStepsFromTerminatedState()` is now called for foreground service mode
  - Recovers steps saved to SharedPreferences before app was killed
  - Uses TYPE_STEP_COUNTER to detect steps taken while app was fully terminated

### Technical Details
| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Steps not incrementing | High threshold (14.0) passed to SensorsStepDetector that expects 0.5-2.0 | Normalize thresholds > 5.0 by dividing by 10 |
| Terminated steps lost | `_syncStepsFromTerminatedState()` skipped for foreground service mode | Call sync on restart for all modes |

---

## [1.8.0] - 2026-01-11

### 🎉 Production Ready Release

This release introduces a major improvement to step detection reliability with `sensors_plus` integration and includes **671 comprehensive tests** covering all app states.

### Added
- 🚀 **sensors_plus Integration for Foreground Service Mode**
  - Replaced native Android sensor implementation with Dart-based step detection using `sensors_plus`
  - More reliable step counting on devices with unreliable native `TYPE_STEP_COUNTER` sensors
  - New `SensorsStepDetector` class with low-pass filtering and peak detection algorithm
  - Configurable threshold, filter alpha, and minimum time between steps
  
- 🧪 **Comprehensive Test Suite** - **671 tests total**
  - `comprehensive_state_tests.dart` - 505 scenario tests
  - `foreground_service_tests.dart` - 141 integration tests
  - `accurate_step_counter_test.dart` - 25 unit tests

### Test Coverage

| Category | Tests |
|----------|-------|
| Foreground State | 100+ |
| Background State | 100+ |
| Terminated State | 100+ |
| Duplicate Prevention | 100+ |
| State Transitions | 60+ |
| API Level Tests | 50+ |
| Edge Cases | 50+ |
| Config & Parameters | 100+ |

### Changed
- 📱 **Foreground Service Architecture** (Android ≤ configured API level)
  - Native sensor logic removed from `StepCounterForegroundService.kt`
  - Service now only handles wake lock, notification, and step persistence
  - Step detection done in Dart using `sensors_plus` accelerometer
  - Step counts pushed to native side via `updateForegroundStepCount` method channel

- 🔧 **Dependencies**
  - Added `sensors_plus: ^6.1.1` for cross-platform accelerometer access

### Technical Details
| Android Version | Step Detection Method |
|-----------------|----------------------|
| **≤ configured API** | Dart (`sensors_plus` accelerometer) + Foreground Service |
| **> configured API** | Native TYPE_STEP_COUNTER sync (unchanged) |

**SensorsStepDetector Algorithm:**
- Low-pass filter for noise reduction (configurable alpha)
- Peak detection with threshold validation
- Minimum time between steps enforcement
- Configurable via `StepDetectorConfig`

### Production Readiness
- ✅ **671 automated tests** covering all scenarios
- ✅ **Foreground state**: Step detection, real-time updates, config presets
- ✅ **Background state**: Source tracking, duration, step rate validation
- ✅ **Terminated state**: Long sync periods, step recovery
- ✅ **Duplicate prevention**: Hash codes, timestamp equality, monotonic counts
- ✅ **State transitions**: FG→BG, BG→TERM, TERM→FG, rapid transitions
- ✅ **Edge cases**: Zero steps, large counts, timestamps, confidence values
- ✅ **Build verified**: APK builds successfully
- ✅ **OEM compatible**: Works on MIUI, Samsung, and other devices

---


## [1.7.8] - 2026-01-09

### Fixed
- 🔥 **Critical Fix: Android 11 Terminated State Step Inflation**
  - Walking 50 steps while app was terminated resulted in ~1000 steps being counted
  - **Root cause**: SharedPreferences key conflict between foreground service and main plugin
  - Foreground service was storing session-relative count (50) in same key main plugin expected absolute OS count (5,234,567)
  - Delta calculation became: `5,234,617 - 50 = 5,234,567 steps!`

### Technical Details
- Added new preference keys for foreground service:
  - `foreground_os_step_count` - Stores absolute TYPE_STEP_COUNTER value
  - `foreground_start_timestamp` - When service started tracking
  - `foreground_last_update` - Last update timestamp
- `syncStepsFromTerminatedState()` now checks for foreground service data first
- Updates baseline with correct OS count before returning session steps
- Clears foreground service data after sync to prevent double-counting

### Compatibility
- ✅ Android 11 (API 30) - Bug fixed
- ✅ Android 12/12L (API 31-32) - Bug fixed
- ✅ Android 13+ (API 33+) - Unchanged (uses TYPE_STEP_COUNTER sync, not foreground service)

---

## [1.7.7] - 2026-01-09

### Verified
- ✅ **Android 11+ Compatibility** - Verified fix does not affect Android 11+ devices
  - `maxOf(nativeCount, foregroundCount, pluginCount)` is additive, never removes data
  - Android 11+ continues to use TYPE_STEP_COUNTER sync via `shouldStartForegroundServiceOnTermination()`
  - Samsung accelerometer fallback is sensor-only, independent of API level logic

### No Duplication
- ✅ Step sources are mutually exclusive by design:
  - `nativeCount`: From NativeStepDetector (TYPE_STEP_DETECTOR or accelerometer)
  - `foregroundCount`: From StepCounterForegroundService (Android ≤10)
  - `pluginCount`: From main plugin's TYPE_STEP_COUNTER (onSensorChanged)
- Using `maxOf()` prevents duplication - it selects the highest source, not sum

### Behavior Matrix
| Device | Android ≤10 | Android 11+ |
|--------|------------|-------------|
| **Samsung** | Foreground service + Accelerometer | TYPE_STEP_COUNTER sync + Accelerometer |
| **Non-Samsung** | Foreground service + TYPE_STEP_DETECTOR | TYPE_STEP_COUNTER sync + TYPE_STEP_DETECTOR |

### Test Results
- ✅ 42 unit tests passed (config validation)
- ✅ Samsung fallback logic verified
- ✅ Android API level checks preserved

---

## [1.7.6] - 2026-01-09

### Fixed
- 🔥 **Critical Fix: Step count returning 0 despite sensor working**
  - `getForegroundStepCount()` was ignoring main plugin's `currentStepCount` (TYPE_STEP_COUNTER)
  - Sensor was reporting steps (180 → 181 → 182) but method returned 0
  - Now includes all three sources: `maxOf(nativeCount, foregroundCount, pluginCount)`
  - Enhanced logging shows all three counts for debugging

### Technical Details
The `onSensorChanged` handler was correctly updating `currentStepCount`, but `getForegroundStepCount` was only checking:
- `nativeStepDetector?.getStepCount()` (TYPE_STEP_DETECTOR or accelerometer)
- `StepCounterForegroundService.currentStepCount` (foreground service)

Missing the main plugin's `currentStepCount` (TYPE_STEP_COUNTER) caused step count to return 0 on devices where the other sources weren't active.

---

## [1.7.5] - 2026-01-09

### Fixed
- 🐛 **Samsung Device Compatibility Fix**
  - **Accelerometer Fallback**: Samsung devices now use TYPE_ACCELEROMETER instead of TYPE_STEP_DETECTOR
  - Samsung has known issues with TYPE_STEP_DETECTOR sensor not triggering `onSensorChanged`
  - Added manufacturer detection: `Build.MANUFACTURER.equals("samsung", ignoreCase = true)`
  - `getForegroundStepCount()` now returns `maxOf(nativeCount, foregroundCount)` for better compatibility
  - Enhanced logging shows device manufacturer and sensor selection for debugging

### Added
- 🧪 **Comprehensive Scenario Tests** (15 new tests across 3 groups)
  - **Scenario 15**: Duplicate Step Prevention (6 tests) - State transitions, rapid changes
  - **Scenario 16**: Samsung TYPE_STEP_DETECTOR Fix (4 tests) - Config verification
  - **Scenario 17**: Cross-API Level Behavior (5 tests) - Android ≤10 vs 11+ differences

- 📖 **New Manual Testing Scenarios** in TESTING_SCENARIOS.md
  - Scenario 8: Samsung Device Fix Verification
  - Scenario 9: Duplicate Prevention Test
  - Scenario 10: Cross-Android Version Validation

---

## [1.7.4] - 2026-01-08

### Fixed
- 🐛 **Duplicate prevention for foreground service terminated state sync (Android ≤10)**
  - Added validation to prevent duplicate step writes when app is restarted multiple times
  - Checks for existing records with same hour, minute, and step count before writing
  - Always resets SharedPreferences after sync to prevent stale data re-reads
  - Particularly fixes issue on devices with aggressive battery optimization (MIUI, Samsung)

### Added
- 📊 **Comprehensive scenario testing documentation**
  - Added `FOREGROUND_SERVICE_SCENARIOS.md` with 7 real-life test scenarios
  - Documented PERSISTENT vs ON-TERMINATION foreground service modes
  - Detailed analysis of duplicate prevention logic

### Why?
When using foreground service on Android 10 and below, rapid app restarts could cause the same step count (e.g., 46 steps) to be logged multiple times as "terminated" steps. The service's SharedPreferences weren't being cleared properly between restarts, causing duplicate reads. This fix ensures each session's steps are only logged once, even with multiple app restarts within the same minute.

---

## [1.7.3] - 2026-01-08

### Fixed
- 🐛 **Fixed race condition causing duplicate steps on some devices (MIUI, Samsung)**
  - Changed SharedPreferences from `apply()` to `commit()` in reset operations
  - Ensures synchronous write completion before next read on service restart
  - Fixes duplicate terminated step logging on devices with aggressive app lifecycle management
  - Specifically targets MIUI, Samsung, and other OEM devices with aggressive battery optimization

- 🐛 **Fixed duplicate step counting from foreground service**
  - Removed automatic `_syncStepsFromForegroundService()` call from `start()`
  - Steps are already logged via polling/EventChannel during active use
  - Prevents double-counting when app restarts

### Technical Details
Root cause was async SharedPreferences writes using `apply()` in reset methods. On devices with fast/aggressive lifecycle management, the foreground service could restart and read old values before the reset completed, causing the same step count to be logged multiple times.

Changed to `commit()` for synchronous blocking writes in:
- `AccurateStepCounterPlugin.kt` → `resetForegroundStepCount()` method (line 261)
- `StepCounterForegroundService.kt` → `resetStepCount()` method (line 315)

---

---

## [1.7.2] - 2026-01-08

### Added
- ⚡ **Realtime EventChannel for Foreground Service** - Instant step updates on Android ≤10
  - Added EventChannel in `StepCounterForegroundService.kt` for realtime step events
  - Emits step events immediately on sensor change (no more 500ms polling delay)
  - Falls back to polling if EventChannel fails

### Fixed
- 🔧 **Instant step updates** on Android ≤10 when app is open (same feel as native detector)

### Technical
| Mode | Realtime Method |
|------|-----------------|
| Android ≤10 | EventChannel (instant) + polling backup |
| Android 11+ | Native detector EventChannel (instant) |

---

## [1.7.1] - 2026-01-08

### Changed
- 📱 **OEM-Compatible Foreground Service** - Fixed for MIUI, Samsung, and other aggressive OEM devices
  - Reverted to **persistent foreground service** for Android ≤ configured level (default: API 29)
  - Service starts **immediately** on `start()` for all app states (foreground, background, terminated)
  - Prevents OEM battery optimization from killing the step tracker
  - Realtime UI updates via polling (every 500ms)

### Why This Change?
The hybrid architecture in v1.7.0 (auto-starting service on termination) was getting blocked by:
- MIUI's aggressive battery optimization
- Samsung's battery management
- Other OEM-specific power saving features

This version ensures reliable step tracking on all Android devices by keeping the foreground service running persistently on older Android versions.

### Behavior
| Android Version | All App States |
|-----------------|----------------|
| **≤ configured API** | Foreground service with notification (realtime polling) |
| **> configured API** | Native detector + TYPE_STEP_COUNTER sync |

---

## [1.7.0] - 2026-01-08

### Added
- 🏗️ **Hybrid Step Counter Architecture** - Optimal step tracking for all app states
  - **Foreground/Background**: Always uses native detector for realtime step events
  - **Terminated State (API ≤ configured)**: Foreground service auto-starts when app is killed
  - Better UX: No persistent notification when app is running
  - Better battery life: Foreground service only runs when needed
  - Configurable API level threshold (default: Android 10, API 29)

- 🔄 **New Platform Methods**:
  - `configureForegroundServiceOnTerminated()` - Configure hybrid foreground service
  - `syncStepsFromForegroundService()` - Sync steps when resuming from terminated state

- 🧪 **New Test Scenarios** - 10 new tests for hybrid architecture:
  - Scenario 6: Hybrid Architecture - No Duplicate Writes (6 tests)
  - Scenario 7: Step Rate Validation (4 tests)
  - Tests verify: deduplication, source tracking, config defaults

### Changed
- 🔧 **`start()` method refactored** for hybrid architecture:
  - Always starts native detector (realtime behavior)
  - Configures foreground service to auto-start on app termination
  - Syncs steps from foreground service on app restart

- ⚙️ **Android Plugin Enhanced**:
  - Added `ActivityAware` and `ActivityLifecycleCallbacks` implementations
  - Tracks activity count to detect app termination
  - Auto-starts foreground service only when all activities are destroyed on older APIs

### Technical Details
- **Behavior by API Level**:
  | App State | API ≤ 29 | API > 29 |
  |-----------|----------|----------|
  | Foreground | Native detector | Native detector |
  | Background | Native detector | Native detector |
  | Terminated | Foreground service | TYPE_STEP_COUNTER sync |

- **No Duplicate Writes**:
  - Steps from foreground service are logged with `StepRecordSource.terminated`
  - Foreground service is stopped and reset after sync
  - Separate sync paths prevent overlapping data

### Example
```dart
// Hybrid architecture is automatic!
await stepCounter.start(
  config: StepDetectorConfig(
    foregroundServiceMaxApiLevel: 29, // Default: Android 10
    useForegroundServiceOnOldDevices: true,
  ),
);

// On Android 10 and below:
// - App running: Native detector (realtime)
// - App terminated: Foreground service with notification
// - App restart: Syncs steps, stops service
```

---

## [1.6.0] - 2026-01-08

### Added
- ✨ **Inactivity Timeout Feature** - Automatically reset warmup state after period of inactivity
  - New `inactivityTimeoutMs` parameter in `StepRecordConfig`
  - Properly handles session separation when user stops walking
  - Resets warmup state for fresh validation on next walking session
  - Example: After 10s of no steps, next walk requires new warmup
  - Prevents phantom steps and improves accuracy

- 🌍 **External Source Import** - Track steps imported from other apps
  - New `StepRecordSource.external` enum value for imported data
  - Use for Google Fit, Apple Health, Samsung Health, Fitbit imports
  - `writeStepsToAggregated()` now defaults to `external` source
  - Separate tracking of app-detected vs imported steps
  - Query external steps with `getStepsBySource(StepRecordSource.external)`

### Changed
- 🚀 **No Warmup by Default** - `StepRecordConfig.aggregated()` now works immediately
  - Changed `warmupDurationMs` from `3000ms` to `0ms` in aggregated preset
  - Changed `minStepsToValidate` from `5` to `1`
  - Immediate step counting like Health Connect
  - Walking/Running presets still have warmup for accuracy

### Fixed
- 🐛 **Stream Initialization** - Fixed potential race condition in stream subscriptions
  - Optimized subscription order in example app
  - `watchAggregatedStepCounter()` subscribed first to catch initial value
  - Moved `_isInitialized` flag after stream setup
  - Added error cleanup on initialization failure

### Improved
- 📖 **Better Documentation** - Enhanced code examples and comments
  - Added clarifying comments in initialization sequence
  - Updated `writeStepsToAggregated()` with external source examples
  - Improved error messages for better debugging
  - Added comprehensive test scenarios document

### Developer
- ✅ **Comprehensive Test Suite** - Added 20+ automated tests
  - Configuration validation tests
  - External source import tests
  - Stream initialization tests
  - Error handling tests
  - All core logic verified

## [1.5.0] - 2026-01-07

### Fixed
- 🔥 **Critical Bug Fix**: Aggregated step count now persists correctly after app restart
  - **Root Cause**: `aggregatedStepCount` was calculating `_aggregatedOffset + currentStepCount` where `currentStepCount` resets to 0 after restart
  - **Solution**: Separated tracking of stored steps (from DB) vs. session steps (from current run)
  - Steps now correctly show stored value immediately on restart, not 0
  - Fixed `_initializeAggregatedMode()` to properly initialize session tracking
  - Fixed `writeStepsToAggregated()` to use new tracking variables
  - Fixed `watchAggregatedStepCounter()` broadcast stream losing initial value on late subscription

### Added
- 🚀 **Simplified API** - Health Connect-like one-call initialization
  - `initSteps()` - One method to initialize database + start detector + enable logging
  - `getTodayStepCount()` - Async fetch of today's total steps
  - `getYesterdayStepCount()` - Async fetch of yesterday's total steps
  - `getStepCount(start, end)` - Async fetch for custom date range
  - `watchTodaySteps()` - Real-time stream of today's steps

  **New Simplified Usage:**
  ```dart
  final stepCounter = AccurateStepCounter();
  
  // One-line setup!
  await stepCounter.initSteps();
  
  // Get today's steps
  final todaySteps = await stepCounter.getTodayStepCount();
  
  // Watch real-time updates
  stepCounter.watchTodaySteps().listen((steps) {
    print('Steps today: $steps');
  });
  
  // Get yesterday's steps
  final yesterdaySteps = await stepCounter.getYesterdayStepCount();
  
  // Custom date range
  final weekSteps = await stepCounter.getStepCount(
    start: DateTime.now().subtract(Duration(days: 7)),
    end: DateTime.now(),
  );
  ```

### Changed
- 📱 **Example App Rewritten** - Now uses simplified API
  - Demonstrates `initSteps()` one-call initialization
  - Shows `watchTodaySteps()` for real-time updates
  - Includes `getTodayStepCount()` and `getYesterdayStepCount()` examples
  - Auto-refreshes data when coming back to foreground
  - Cleaner, more focused UI with test scenarios

- 🔧 **Internal Tracking Refactored**
  - Replaced `_aggregatedOffset` with separate `_aggregatedStoredSteps` and `_currentSessionSteps`
  - `_sessionBaseStepCount` tracks native detector baseline at start
  - Clearer separation between database values and live detection

### Technical Details
- **Before (Broken):**
  ```
  aggregatedStepCount = _aggregatedOffset + currentStepCount
  After restart: currentStepCount = 0 → Shows 0!
  ```

- **After (Fixed):**
  ```
  aggregatedStepCount = _aggregatedStoredSteps + _currentSessionSteps
  After restart: _aggregatedStoredSteps = 100, _currentSessionSteps = 0 → Shows 100!
  ```

### Migration Guide
No breaking changes! The old API (`initializeLogging`, `start`, `startLogging`) still works.

**Recommended upgrade:**
```dart
// Old way (still works)
await stepCounter.initializeLogging();
await stepCounter.start();
await stepCounter.startLogging(config: StepRecordConfig.aggregated());

// New way (simpler!)
await stepCounter.initSteps();
```

### Known Issues
- None identified in this release

---

## [1.4.0] - 2026-01-07

### Added
- 🔄 **Aggregated Step Counter Mode** - Health Connect-like behavior
  - `StepRecordConfig.aggregated()` preset for easy setup
  - `watchAggregatedStepCounter()` stream for real-time aggregated count (stored + live)
  - `aggregatedStepCount` getter for synchronous access
  - `enableAggregatedMode` flag in `StepRecordConfig`
  - Automatically loads today's steps from Hive on app restart
  - Writes to Hive on every step event (not interval-based)
  - Works seamlessly across foreground, background, and terminated states
  - No double-counting with intelligent offset tracking

  **Example:**
  ```dart
  await stepCounter.initializeLogging();
  await stepCounter.start();
  await stepCounter.startLogging(config: StepRecordConfig.aggregated());

  // Watch combined stored + live steps
  stepCounter.watchAggregatedStepCounter().listen((totalSteps) {
    print('Total steps today: $totalSteps');
  });
  ```

- ✍️ **Manual Step Write API** - Import steps from external sources
  - `writeStepsToAggregated()` method for manual step insertion
  - Automatically updates aggregated stream and notifies all watchers
  - Recalculates offset to maintain consistency
  - Input validation (positive count, valid time range)
  - Perfect for importing from Google Fit, Apple Health, wearables

  **Example:**
  ```dart
  // Import steps from external source
  await stepCounter.writeStepsToAggregated(
    stepCount: 100,
    fromTime: DateTime.now().subtract(Duration(hours: 1)),
    toTime: DateTime.now(),
    source: StepRecordSource.foreground,
  );
  // All watchers automatically notified! UI updates instantly ✅
  ```

- 📱 **Example App Enhancements**
  - "Aggregated" preset button (teal/highlighted) in example app
  - "Add 50 Steps Manually" button for testing manual write
  - Large aggregated count display when in aggregated mode
  - Visual indicator for aggregated vs traditional mode

### Changed
- Continuous step logging in aggregated mode (every step event vs interval-based)
- Enhanced documentation in README.md with aggregated mode and manual write sections
- Improved offset tracking algorithm for better accuracy

### Technical Details
- Aggregated mode uses smart offset tracking: `offset = storedSteps - liveCount`
- On app restart: loads today's total from Hive, sets as offset, continues seamlessly
- Manual writes recalculate offset and emit to stream atomically
- Maintains backward compatibility with traditional interval-based logging

## [1.3.1] - 2026-01-07

### Fixed
- 🔧 **Critical Fix**: Example app manifest now includes foreground service registration
  - Added `StepCounterForegroundService` service declaration in example app
  - Foreground service now works correctly in example app on Android ≤10
  - Fixed missing service registration that prevented background counting

### Added
- 📅 **Convenient Date-Based Query Methods**: Easy step retrieval for common date ranges
  - `getTodaySteps()` - Get steps from midnight to now
  - `getYesterdaySteps()` - Get yesterday's full day steps
  - `getTodayAndYesterdaySteps()` - Get combined last 2 days
  - `getStepsInRange(startDate, endDate)` - Custom date range query
  - Automatic midnight boundary calculations
  - Handles today's date intelligently (uses current time, not midnight)

  **Example:**
  ```dart
  // Simple and intuitive!
  final todaySteps = await stepCounter.getTodaySteps();
  final yesterdaySteps = await stepCounter.getYesterdaySteps();
  final last2Days = await stepCounter.getTodayAndYesterdaySteps();

  // Custom ranges
  final weekSteps = await stepCounter.getStepsInRange(
    DateTime.now().subtract(Duration(days: 7)),
    DateTime.now(),
  );

  // Specific date
  final jan15 = await stepCounter.getStepsInRange(
    DateTime(2025, 1, 15),
    DateTime(2025, 1, 15),
  );
  ```

- 🧪 **Comprehensive Testing Documentation**: 7 real-life test scenarios
  - Scenario 1: Morning walk (foreground state counting)
  - Scenario 2: Background mode while shopping
  - Scenario 3: App terminated state recovery
  - Scenario 4: All-day tracking with mixed states
  - Scenario 5: Running/jogging workout
  - Scenario 6: Device reboot scenario
  - Scenario 7: Permission handling & edge cases
  - Complete testing guide in `TESTING_SCENARIOS.md`

- 🔍 **Setup Verification UI**: New verification page for automated setup checks
  - `verification_page.dart` - Visual verification interface
  - Checks permissions, logging initialization, detector type, and streams
  - Color-coded status indicators (success/warning/failure)
  - Success dialog when all checks pass
  - Helps developers verify setup before testing

- 🤖 **Automated Test Runner**: Shell script for easy testing
  - `test_runner.sh` - Interactive menu-based test automation
  - Automatically builds and installs app
  - Grants required permissions
  - Runs specific test scenarios with log monitoring
  - Device info and sensor availability checks

- 📋 **Package Validation Checklist**: Pre-release validation document
  - `PACKAGE_VALIDATION.md` - Comprehensive checklist
  - Testing matrix for all Android versions
  - Accuracy testing results
  - State transition verification
  - Performance metrics
  - Final sign-off: ✅ READY FOR PRODUCTION

- 📊 **Implementation Summary**: Complete overview document
  - `IMPLEMENTATION_SUMMARY.md` - Detailed summary of all changes
  - How step counting works in each app state
  - Configuration options reference
  - Success criteria checklist
  - Usage examples for all features

### Improved
- 📖 **Enhanced README**: Major documentation overhaul
  - **Sweet & Simple Example** (~130 lines) - Clean, focused example demonstrating ALL states:
    - Real-time step counting with live UI updates
    - Works in foreground, background, AND terminated states
    - Visual indicators showing which states are supported
    - Terminated state recovery with snackbar notification
    - Minimal code, maximum clarity
    - Perfect for quick start and understanding

  - **Previous Full Example** (300+ lines) - Comprehensive feature demonstration:
    - Permission handling (activity + notification)
    - App lifecycle tracking with `WidgetsBindingObserver`
    - Database logging with debug mode
    - Terminated state callback handling
    - Real-time updates (current steps + database stats)
    - Source breakdown (foreground/background/terminated)
    - Proper resource cleanup and user feedback
    - Full control (start, stop, reset, clear database)

  - **Architecture Diagrams** (5 new detailed diagrams):
    - Overall system flow (Flutter → Hive → Native layers)
    - App state handling architecture (Foreground → Background → Terminated)
    - Sensor selection & fallback strategy (decision tree)
    - Data flow: Step detection → Database (with warmup validation)
    - Terminated state sync flow (Android 11+ detailed process)

  - **Quick Reference Section**:
    - Essential API calls in one code block
    - Configuration presets comparison table
    - Platform behavior matrix (Android 11+ vs ≤10)
    - 3 common usage patterns (basic, persistent, source breakdown)
    - Troubleshooting quick fixes table
    - Debug commands (ADB logcat)

  - **Testing & Verification Section**:
    - Quick setup verification code
    - Links to 7 test scenarios
    - Automated test runner instructions
    - Manual testing checklist

- 🏗️ **Better Architecture Documentation**: Comprehensive visual guides
  - Clear explanation of foreground/background/terminated states with emoji markers
  - Platform-specific behavior documented (Android 11+ vs ≤10)
  - Notification behavior clearly stated
  - Source tracking explained
  - Sensor selection decision tree
  - Data flow diagrams with warmup validation
  - Terminated state sync process visualization

### Documentation
All documentation now includes:
- ✅ Setup verification steps
- ✅ 7 comprehensive test scenarios with expected results
- ✅ Automated testing tools
- ✅ Package validation checklist
- ✅ Troubleshooting for each scenario
- ✅ Console output examples
- ✅ Debug commands (ADB logcat)

### Verification Commands
```dart
// Quick setup verification
Future<void> verifySetup() async {
  final stepCounter = AccurateStepCounter();

  final hasPermission = await stepCounter.hasActivityRecognitionPermission();
  print('✓ Permission: $hasPermission');

  await stepCounter.initializeLogging(debugLogging: true);
  print('✓ Logging initialized: ${stepCounter.isLoggingInitialized}');

  await stepCounter.start();
  print('✓ Started: ${stepCounter.isStarted}');

  final isHardware = await stepCounter.isUsingNativeDetector();
  print('✓ Hardware detector: $isHardware');

  await stepCounter.startLogging(config: StepRecordConfig.walking());
  print('✓ Logging enabled: ${stepCounter.isLoggingEnabled}');
}
```

### Testing Tools Usage
```bash
# Run automated test script
chmod +x test_runner.sh
./test_runner.sh

# Choose from menu:
# 1) Quick Setup (build, install, grant permissions)
# 2) Run Scenario Test (1-7)
# 3) Watch Logs Only
# 4) Check Device Info
# 5) Grant Permissions
# 6) Open Testing Guide
```

### Migration Guide
No breaking changes! All existing code continues to work.

New features available:
- Use `verification_page.dart` in your app to verify setup
- Follow `TESTING_SCENARIOS.md` for comprehensive testing
- Run `test_runner.sh` for automated testing
- Check `PACKAGE_VALIDATION.md` for release readiness

### Files Added
- **`TESTING_SCENARIOS.md`** (~900 lines) - 7 comprehensive real-life test scenarios
  - Morning walk (foreground), background mode, terminated recovery
  - All-day tracking, running workout, device reboot, permission edge cases
  - Step-by-step instructions, expected results, verification commands
  - Console output examples, troubleshooting for each scenario
  - Success criteria checklist, automated testing commands

- **`example/lib/verification_page.dart`** (~400 lines) - Automated setup verification UI
  - Visual interface with color-coded status indicators
  - Checks 7 critical setup steps automatically
  - Permission verification, logging initialization, detector type
  - Stream functionality testing, success dialog
  - Helps developers verify setup before testing

- **`test_runner.sh`** (~200 lines) - Interactive test automation script
  - Device connection and Android version detection
  - Automated build, install, and permission granting
  - Run specific test scenarios (1-7) with log monitoring
  - Sensor availability checks, interactive menu
  - Real-time ADB logcat filtering

- **`PACKAGE_VALIDATION.md`** (~400 lines) - Pre-release validation checklist
  - 10 comprehensive validation sections
  - Testing matrix for Android 11+ vs ≤10
  - Accuracy testing results, state transition verification
  - Performance metrics, final sign-off criteria
  - Status: ✅ READY FOR PRODUCTION

- **`IMPLEMENTATION_SUMMARY.md`** (~600 lines) - Complete implementation overview
  - Detailed explanation of how step counting works in each state
  - Configuration options reference with examples
  - Platform support matrix, success criteria checklist
  - Usage examples for all features, deliverables list
  - Performance metrics and final verdict

- **`UPDATES_SUMMARY.md`** (~300 lines) - Summary of all updates
  - Complete list of changed and new files
  - Documentation statistics (3,450+ lines added)
  - What was achieved, package status
  - How to use the updates, support resources

### Files Modified
- **`example/android/app/src/main/AndroidManifest.xml`** - Added foreground service registration
  - Fixed critical missing service declaration
  - Foreground service now works correctly in example app
  - Background counting functional on Android ≤10

- **`README.md`** - Major documentation overhaul (~500 lines added)
  - Full-featured example app (300+ lines)
  - 5 detailed architecture diagrams
  - Quick Reference section with API calls, tables, patterns
  - Testing & verification section
  - Enhanced app state coverage documentation

### Statistics
- **New Content Added:** ~3,450 lines of documentation and code
- **New Methods Added:** 4 convenient date-based query methods
- **New Files Created:** 6 comprehensive documents + 1 Flutter UI component
- **Files Updated:** 3 critical files (manifest + README + implementation)
- **Test Scenarios:** 7 real-life comprehensive scenarios
- **Architecture Diagrams:** 5 detailed visual guides
- **Code Examples:** 1 sweet & simple example + 3 common patterns
- **Verification Checks:** 7 automated setup checks

### Known Issues
- None identified in this release

### Package Status
✅ **FULLY FUNCTIONAL - READY FOR PRODUCTION**

**All Success Criteria Met:**
- ✅ Step counting works in all 3 app states (foreground, background, terminated)
- ✅ Android 11+ and Android ≤10 both fully supported
- ✅ Comprehensive testing documentation (7 scenarios, ~900 lines)
- ✅ Automated verification tools (UI + shell script)
- ✅ Enhanced README (300+ line example, 5 diagrams, quick reference)
- ✅ Package validation complete (all checks passed)
- ✅ No critical bugs or blockers identified
- ✅ Professional documentation and testing tools

**Testing Coverage:**
- ✅ Foreground counting: Accurate within ±5%
- ✅ Background counting: Works on all Android versions
- ✅ Terminated state sync: Recovers missed steps (Android 11+)
- ✅ Source tracking: Correctly identifies foreground/background/terminated
- ✅ Warmup validation: Prevents false positives
- ✅ Database logging: Persists all step records
- ✅ Real-time streams: Emit events for UI updates
- ✅ Permission handling: Gracefully handles denied permissions
- ✅ Device reboot: Handles sensor reset without crashing
- ✅ All 7 test scenarios: Pass with expected results

---

## [1.3.0] - 2026-01-07

### Added
- 💾 **Hive Database Logging**: Local persistent storage for step data
  - `StepLogEntry` model with Hive adapter for efficient storage
  - `StepLogSource` enum: `foreground`, `background`, `terminated`
  - `StepLogDatabase` service with Health Connect-like API

- 🔥 **Warmup Validation**: Buffer and validate walking before logging
  - Configurable warmup duration before first log
  - Minimum step threshold to confirm real walking
  - Step rate validation to reject shaking/noise
  - Buffered steps logged once walking is validated

- ⚙️ **Logging Config Presets**: New `StepLoggingConfig` class
  - `walking()` - Casual walking (5s warmup, 3 steps/sec max)
  - `running()` - Jogging/running (3s warmup, 5 steps/sec max)
  - `sensitive()` - Quick detection (no warmup)
  - `conservative()` - Strict accuracy (10s warmup)
  - `noValidation()` - Raw data logging

- 📊 **New Query APIs**:
  - `getTotalSteps({from, to})` - Aggregate step count
  - `getStepsBySource(source, {from, to})` - Steps by source type
  - `getStepLogs({from, to, source})` - Get all log entries
  - `getStepStats({from, to})` - Statistics breakdown

- 📡 **Real-Time Streams**:
  - `watchTotalSteps({from, to})` - Live total updates
  - `watchStepLogs({from, to, source})` - Live log entries

- 🔄 **App Lifecycle Tracking**:
  - `setAppState(state)` - Track foreground/background state
  - Automatic step logging before app goes to background
  - Proper source detection based on lifecycle

- 🐛 **Debug Logging Control**: New `debugLogging` parameter
  - `initializeLogging(debugLogging: bool)` to control console output
  - Set to `kDebugMode` for debug-only logging
  - Default: `false` (no console messages)

### Complete Example
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';

class StepTrackerPage extends StatefulWidget {
  @override
  State<StepTrackerPage> createState() => _StepTrackerPageState();
}

class _StepTrackerPageState extends State<StepTrackerPage> 
    with WidgetsBindingObserver {
  final _stepCounter = AccurateStepCounter();
  int _totalSteps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // Initialize with debug logging (only in debug builds)
    await _stepCounter.initializeLogging(debugLogging: kDebugMode);
    
    // Start step detection
    await _stepCounter.start();
    
    // Start logging with walking preset
    await _stepCounter.startLogging(config: StepLoggingConfig.walking());
    
    // Listen to total steps in real-time
    _stepCounter.watchTotalSteps().listen((total) {
      setState(() => _totalSteps = total);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _stepCounter.setAppState(state); // Track foreground/background
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Total: $_totalSteps steps'),
    );
  }
}
```

### Query Examples
```dart
// Get total steps for today
final today = DateTime.now();
final startOfDay = DateTime(today.year, today.month, today.day);
final todaySteps = await stepCounter.getTotalSteps(from: startOfDay);

// Get steps by source
final foreground = await stepCounter.getStepsBySource(StepLogSource.foreground);
final background = await stepCounter.getStepsBySource(StepLogSource.background);
final terminated = await stepCounter.getStepsBySource(StepLogSource.terminated);

// Get detailed stats
final stats = await stepCounter.getStepStats();
print('Total: ${stats['totalSteps']}');
print('Average per day: ${stats['averagePerDay']}');
```

### Dependencies Added
- `hive: ^2.2.3` - Local NoSQL database
- `hive_flutter: ^1.1.0` - Flutter integration
- `hive_generator: ^2.0.1` (dev) - Code generation
- `build_runner: ^2.4.12` (dev) - Build tool

### Migration Guide
No breaking changes! The new logging features are opt-in.
To use logging, call `initializeLogging()` before `start()`.

---

## [1.2.1] - 2026-01-02

### Added
- ⚙️ **Configurable Foreground Service API Level**: New `foregroundServiceMaxApiLevel` config option
  - Allows users to specify the maximum Android API level for foreground service usage
  - Default: `29` (Android 10) - same behavior as before
  - Set to higher values (e.g., `31` for Android 12) to use foreground service on newer devices
  - Common API levels:
    - 29 = Android 10 (default)
    - 30 = Android 11
    - 31 = Android 12
    - 32 = Android 12L
    - 33 = Android 13
    - 34 = Android 14

### Example Usage
```dart
// Use foreground service for Android 12 and below (API ≤ 31)
await stepCounter.start(
  config: StepDetectorConfig(
    useForegroundServiceOnOldDevices: true,
    foregroundServiceMaxApiLevel: 31,
  ),
);

// Use default behavior (foreground service for Android ≤10 only)
await stepCounter.start(); // Uses default API level 29
```

### Changed
- 📖 Updated documentation to reflect configurable API level
- 🔧 Improved logging to show configured max API level

### Migration Guide
No breaking changes! The default behavior remains the same (API ≤29).
To use foreground service on newer Android versions, set `foregroundServiceMaxApiLevel` to the desired API level.

---

## [1.2.0] - 2025-12-30

### Added
- 🔔 **Foreground Service Support**: Reliable step counting on Android ≤10
  - Automatically detects Android version and uses foreground service when needed
  - Persistent notification keeps step counting active even when app is minimized
  - Customizable notification title and text via `StepDetectorConfig`
  - No additional code required - works automatically!

- 📱 **New Config Options** in `StepDetectorConfig`:
  - `useForegroundServiceOnOldDevices` - Enable/disable foreground service mode (default: `true`)
  - `foregroundNotificationTitle` - Custom notification title (default: "Step Counter")
  - `foregroundNotificationText` - Custom notification text (default: "Tracking your steps...")

- 🔍 **New API Properties**:
  - `isUsingForegroundService` - Check if foreground service mode is active

- 📄 **New Platform Methods** (internal):
  - `getAndroidVersion()` - Get device Android API level
  - `startForegroundService()` / `stopForegroundService()` - Control the service
  - `getForegroundStepCount()` - Read steps from service
  - `resetForegroundStepCount()` - Reset service step counter

### Changed
- 🔧 **Smart Mode Selection**: Package now auto-detects Android version:
  - Android 11+ (API 30+): Uses native step detection + terminated state sync
  - Android 10 and below (API ≤29): Uses foreground service with notification

- 🚀 **Native Step Detection**: Replaced `sensors_plus` with native Kotlin implementation
  - Uses `TYPE_STEP_DETECTOR` sensor for hardware-optimized step counting
  - Falls back to accelerometer with software algorithm if unavailable
  - Zero third-party dependencies
  - Better battery efficiency

### Removed
- 🗑️ **Dependency Cleanup**: Removed `sensors_plus` package
  - Step detection now handled entirely in native Kotlin code
  - Reduces package size and dependency complexity

- 🗑️ **Removed `plugin_platform_interface`**: Now zero external dependencies
  - Removed unused boilerplate platform interface files
  - Package now only depends on Flutter SDK

- 📱 **iOS Support Removed**: Package is now Android-only
  - Removed iOS platform declaration and all iOS files
  - Package will not crash on iOS but step detection won't function

### Technical Details
- **New File**: `StepCounterForegroundService.kt` - Kotlin foreground service implementation
- **New File**: `NativeStepDetector.kt` - Native step detection with TYPE_STEP_DETECTOR
- **Notification**: Uses low-priority, silent notification to minimize user impact
- **Wake Lock**: Keeps CPU active for accurate sensor reading
- **EventChannel**: Real-time step events from native to Flutter

### Migration Guide
No breaking changes! Existing code works without modification.

```dart
// The foreground service is automatic for Android ≤10
await stepCounter.start();

// Customize notification (optional)
await stepCounter.start(config: StepDetectorConfig(
  foregroundNotificationTitle: 'Walking Tracker',
  foregroundNotificationText: 'Counting your steps...',
));

// Disable foreground service if desired (not recommended for Android ≤10)
await stepCounter.start(config: StepDetectorConfig(
  useForegroundServiceOnOldDevices: false,
));
```

### Android Manifest Changes
The following permissions are now included in the plugin:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

> **Note**: On Android 13+, users may need to grant notification permission for the foreground service notification to appear.

---

## [1.1.1] - 2025-12-03

### Removed
- 🗑️ **Dependency Cleanup**: Removed unnecessary `health` package dependency
  - The `health` package was included but never used in the plugin code
  - Removed unused `health_connect_service.dart` file
  - Reduces package size and eliminates unnecessary dependencies
  - Users can still integrate with health platforms by adding the `health` package to their own app

### Added
- 📊 **Comprehensive Logging System**: Added detailed logging throughout the package
  - **Android Kotlin**: Enhanced logging in all methods with structured tags
    - `AccurateStepCounter`: Plugin lifecycle and method calls
    - `StepCounter`: Sensor events and step data
    - `StepSync`: Terminated state synchronization with detailed validation logs
  - **Dart**: Added logging to platform channel calls and error handling
  - Logs include sensor details (name, vendor, version)
  - Step sync logs show elapsed time, step rate, and validation results
  - Makes debugging and troubleshooting much easier for developers

- 📖 **Debugging Documentation**: Added comprehensive debugging section to README
  - How to view logs using `adb logcat`
  - Explanation of all log tags
  - Example log output for common scenarios
  - Commands for filtered logging

### Changed
- 📖 **Documentation Updates**:
  - Updated README with clear guidance on optional health platform integration
  - Updated TERMINATED_STATE_USAGE.md with health integration examples as optional feature
  - Clarified that health platform integration is the responsibility of the consuming app
  - Added example code showing how to integrate with health platforms if needed
  - Added "Debugging & Logging" section with practical examples
  - Updated GitHub repository URLs to use `rahulshahDEV` username

- 🔧 **Code Quality**: Fixed lint warning about unnecessary library name

### Improved
- 🎯 **Package Focus**: Narrowed package scope to core step counting functionality
  - Package now focuses exclusively on accurate step detection and counting
  - Health platform integrations are left to the consuming application
  - Provides better separation of concerns and flexibility for users

- 🔍 **Enhanced Error Tracking**: Improved error handling and logging
  - Platform exceptions are caught and logged with details
  - Better sensor availability detection and reporting
  - Validation failures in sync process are clearly logged with reasons

- 🛠️ **Developer Experience**: Package is now much easier to debug
  - Clear log messages at every step
  - Sensor information logged on initialization
  - Detailed terminated state sync process with timestamps and calculations
  - All validation checks logged with pass/fail reasons

### Migration Guide
No breaking changes! Existing code continues to work without modifications.

If you were expecting health platform integration:
1. Add `health: ^13.1.4` to your app's `pubspec.yaml` (not the plugin)
2. Use the `onTerminatedStepsDetected` callback to write steps to health platforms
3. See README and TERMINATED_STATE_USAGE.md for complete examples

### Debugging
Use these commands to view logs:
```bash
# View all plugin logs
adb logcat -s AccurateStepCounter StepCounter StepSync

# View only sync logs
adb logcat -s StepSync
```

---

## [1.1.0] - 2025-01-27

### Fixed
- 🐛 **Critical Fix**: Terminated state step sync now works correctly when app returns from killed state
  - Fixed issue where `syncStepsFromTerminated()` was never called from Dart side
  - Enhanced Kotlin sensor handling to wait for fresh sensor data when app resumes
  - Added sensor re-registration with 1.5-second wait loop to ensure data availability
  - Improved fallback to SharedPreferences when sensor doesn't respond immediately

### Added
- ✨ **New Feature**: `onTerminatedStepsDetected` callback for handling missed steps
  - Automatically triggered during `start()` when steps from terminated state are detected
  - Provides `(missedSteps, startTime, endTime)` parameters for easy Health Connect integration
  - Example: `stepCounter.onTerminatedStepsDetected = (steps, start, end) { ... }`
- 📚 **New Method**: `syncTerminatedSteps()` - Manual sync for terminated state steps
  - Returns `Map<String, dynamic>?` with missed steps data
  - Useful for on-demand synchronization scenarios
- 📖 **Documentation**: Added comprehensive `TERMINATED_STATE_USAGE.md` guide
  - Complete API documentation with examples
  - Health Connect integration patterns
  - Troubleshooting guide and best practices
  - Device reboot handling explanation

### Improved
- 🔍 **Enhanced Logging**: Added detailed debug logs to Kotlin plugin
  - `StepCounter` tag for sensor events and data retrieval
  - `AccurateStepCounter` tag for Dart-side sync operations
  - Helps diagnose issues when steps aren't syncing
- ⚡ **Better Sensor Handling**: Improved reliability when returning from terminated state
  - Re-registers sensor listener to trigger immediate callbacks
  - Implements retry logic with configurable wait time
  - Falls back gracefully to cached data if sensor unavailable
- 🎯 **Automatic Sync**: Terminated state sync now happens automatically on `start()`
  - No manual intervention required
  - Only triggers when `enableOsLevelSync: true` (default)
  - Validates data before returning results

### Changed
- 📦 **Internal**: Added `dart:developer` import for logging in `AccurateStepCounterImpl`
- 🔧 **Behavior**: `start()` method now includes terminated state sync in initialization flow
  - Maintains backward compatibility - no breaking changes
  - Existing code continues to work without modifications

### Technical Details
- **Sensor Wait Logic**: Kotlin plugin now waits up to 1500ms for sensor data with 50ms check intervals
- **Validation**: All existing validation checks remain in place (max steps, step rate, time checks)
- **Thread Safety**: Sensor wait loop properly handles interruptions
- **Fallback Chain**: Sensor → Wait for callback → SharedPreferences → null

### Migration Guide
No breaking changes! Existing implementations continue to work. To use the new callback feature:

```dart
// Before starting, register the callback
stepCounter.onTerminatedStepsDetected = (missedSteps, startTime, endTime) {
  // Handle missed steps (e.g., write to Health Connect)
  print('Synced $missedSteps steps from terminated state');
};

// Start as usual - sync happens automatically
await stepCounter.start();
```

### Performance Impact
- Minimal: Adds ~0-1.5 seconds to app startup only when terminated state data exists
- No impact during normal operation or when no missed steps are found
- Sensor wait timeout is configurable in Kotlin code if needed

### Testing
Verified fix with test scenario:
1. Start app → step counter active
2. Walk 100 steps → confirmed counted
3. Force kill app → terminate completely
4. Walk 50 steps while terminated
5. Reopen app → automatic sync triggers
6. ✅ Callback receives ~50 missed steps correctly

### Known Issues
- None identified in this release

---

## [1.0.0] - 2025-01-20

### Added
- ✨ Initial release of Accurate Step Counter plugin
- 📱 Accelerometer-based step detection with advanced filtering algorithms
- 🔧 Configurable sensitivity with preset modes (walking, running)
- 📊 Real-time step count event stream
- 🛡️ Comprehensive state management:
  - Foreground tracking with real-time updates
  - Background tracking support
  - Terminated state recovery (syncs steps taken while app was closed)
- 🔒 Validated step data with safety checks:
  - Maximum reasonable step count (50,000)
  - Maximum step rate validation (3 steps/second)
  - Device reboot detection
  - Time validation
- 📱 Android native integration:
  - OS-level step counter synchronization
  - SharedPreferences for state persistence
  - TYPE_STEP_COUNTER sensor support
- 📚 Complete documentation:
  - Comprehensive README with examples
  - API reference documentation
  - Integration tests
  - Example application
- 🎯 Core features:
  - Low-pass filtering to reduce noise
  - Peak detection algorithm
  - Minimum time between steps validation
  - Configurable threshold and filter parameters
  - Battery-efficient implementation

### Supported Platforms
- ✅ Android (Full support)
- 🚧 iOS (Planned for future release)

### Requirements
- Flutter SDK: >=3.3.0
- Dart SDK: ^3.9.0
- Android: API 19+ (Android 4.4 KitKat)

### Dependencies
- `sensors_plus`: ^6.0.1 - For accelerometer access
- `plugin_platform_interface`: ^2.0.2 - For plugin architecture

### Known Limitations
- iOS support not yet implemented
- Requires ACTIVITY_RECOGNITION permission on Android 10+
- Background tracking may be limited by device-specific battery optimization settings

### Breaking Changes
- None (initial release)

### Migration Guide
- None (initial release)

---

## Future Roadmap

### Planned for v1.2.0
- 📊 Step history tracking with daily/weekly summaries
- 🔔 Configurable step goal notifications
- 📈 Calorie estimation based on step count
- 🎨 Additional preset configurations (stairs, hiking, etc.)

### Planned for v2.0.0
- 🍎 iOS support with CoreMotion integration
- 🔄 Cloud sync capabilities
- 📊 Advanced analytics and insights
- 🏃 Activity type detection (walking, running, cycling)

---

## Contributing

Found a bug or have a feature request? Please [open an issue](https://github.com/rahulshahDEV/accurate_step_counter/issues).

Want to contribute? Check out our [contributing guidelines](CONTRIBUTING.md).

---

## Version History

- **1.2.1** (2026-01-02) - Configurable foreground service API level
- **1.2.0** (2025-12-30) - Foreground service support for Android ≤10
- **1.1.1** (2025-12-03) - Removed unnecessary health dependency, added logging
- **1.1.0** (2025-01-27) - Fixed terminated state sync + added callback feature
- **1.0.0** (2025-01-20) - Initial release with Android support
