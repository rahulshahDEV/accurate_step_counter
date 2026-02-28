# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-28

### 🎉 Major: Native Step Service + Smart Merge

This release promotes the native `TYPE_STEP_COUNTER` foreground service as the primary detection strategy and adds the **SmartMergeHelper** utility for combining multiple step sources.

### Added
- 🔀 **SmartMergeHelper** — New utility class for combining multiple step count sources
  - `SmartMergeHelper.mergeStepCounts()` — Returns `max(sensor, healthConnect, server, currentDisplayed)` with monotonic guarantee
  - `SmartMergeHelper.mergeSensorAndHealth()` — Simplified merge for apps without server recovery
  - Based on proven production pattern from the Meltdown app

- 📡 **Native Step Service Status API**
  - `isNativeStepServiceRunning()` — Queries actual Android service state (not just Dart flag)
  - `isUsingNativeStepService` — Getter to check if native service mode is active
  - `StepCounterService.isServiceRunning()` — Static Kotlin accessor for service state

### Changed
- 📦 **VERSION BUMP to 2.0.0** — Reflects architectural shift to native step service as primary
- 📘 **README completely rewritten** — Reflects TYPE_STEP_COUNTER architecture, SmartMergeHelper, and production API
- 📋 **CHANGELOG trimmed** — Condensed historical entries for readability
- 🧹 **pubspec.yaml cleaned** — Removed boilerplate comments, improved description

### Fixed
- 🔧 **StepCounterService.kt** — Added missing `isRunning` flag to track service lifecycle state

### Removed
- 🗑️ **Stale Hive artifacts** — Removed `accurate_step_counter/step_records.hive` (leftover from pre-v1.9.0 Hive migration)
- 🗑️ **`.DS_Store`** — Removed committed macOS metadata file

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

## [1.8.12] - 2026-01-28

### Fixed
- Crash-proof `deleteRecordsBefore()` with null/open checks after cold start recovery

## [1.8.11] - 2026-01-28

### Fixed
- Hive box cold start ANR — Added `_ensureBoxOpen()` for automatic box recovery

## [1.8.10] - 2026-01-27

### Fixed
- **Critical**: Android 12 ANR — Replaced `DateTime.now()` with UTC in 50Hz sensor loop

## [1.8.9] - 2026-01-21

### Fixed
- Android 14+ foreground service type requirement
- Android 12+ background start restrictions
- Added `BODY_SENSORS_BACKGROUND` and `HIGH_SAMPLING_RATE_SENSORS` permissions

## [1.8.8] - 2026-01-20

### Fixed
- Real-time step counting restored — Removed sensor-level sliding window (moved to logging layer only)

## [1.8.7] - 2026-01-20

### Fixed
- Duplicate external step writes — Added mutex lock + in-memory tracking

## [1.8.6] - 2026-01-19

### Added
- Sensor-level shake rejection (sliding window validation)
- `skipIfDuplicate` parameter for `writeStepsToAggregated()`
- `hasDuplicateRecord()` and `hasOverlappingRecord()` in StepRecordStore

## [1.8.5] - 2026-01-19

### Fixed
- Terminated state sync now applies warmup validation rules

## [1.8.4] - 2026-01-19

### Fixed
- Warmup "shake dilution" — Added 2-second sliding window rate checks

## [1.8.3] - 2026-01-14

### Fixed
- Midnight boundary — Yesterday's steps no longer appear in today's count

## [1.8.2] - 2026-01-13

### Added
- `StepLogsViewer` debug widget
- Singleton foreground service enforcement
- Multi-day terminated step distribution

## [1.8.1] - 2026-01-12

### Fixed
- Threshold normalization for SensorsStepDetector
- Terminated state sync for foreground service mode

## [1.8.0] - 2026-01-11

### Added
- sensors_plus integration for foreground service mode
- 671 comprehensive tests

## [1.7.x] - 2026-01-08 to 2026-01-09

### Key changes across 1.7.0–1.7.8
- Samsung TYPE_STEP_DETECTOR compatibility fix with accelerometer fallback
- OEM-compatible foreground service (MIUI, Samsung)
- Real-time EventChannel for foreground service
- Critical Android 11 terminated state step inflation fix
- Duplicate prevention for foreground service sync
- Race condition fixes for SharedPreferences

## [1.6.0] - 2025-12-20

### Added
- External step import via `writeStepsToAggregated()`
- `StepRecordSource.external` source type

## [1.5.0] - 2025-12-15

### Added
- Aggregated mode (`watchAggregatedStepCounter()`)
- `StepRecordConfig` presets

## [1.0.0] - 2025-11-01

### Initial Release
- Accelerometer-based step detection
- SQLite persistent logging
- Foreground service for background tracking
- Terminated state recovery via TYPE_STEP_COUNTER
