# Android reliability plan

This plan covers the package's Android service, Dart lifecycle, persistence,
public API, and documentation. Automated checks establish specific behavior;
physical device results are required for accuracy and OEM background claims.

## Implementation

1. Remove the HealthKit detector and `health` dependency. Document Android as the
   supported tracking platform and fail clearly when tracking is unsupported.
2. Preserve the native implementation's rate limits, vehicle filter, and explicit
   activity-transition receiver. Fix service permission/type handling, persisted
   offsets and rotation timestamps, and date attribution after a cold start.
3. Fix Dart day rollover before merging an event; share the native event stream;
   preserve the first logging delta; avoid counting session steps twice after an
   import; retain buffered writes when storage fails.
4. Make `startTracking` single-flight and repeatable, observe lifecycle events
   automatically, and keep manual setup available for advanced callers.
5. Add behavioral regression tests, run analysis and tests, compile the Android
   example, and document real-device acceptance scenarios and remaining limits.

## Acceptance

- The public today stream and aggregate reset at a day boundary and query the new
  day's records; an old day's floor cannot raise the new day.
- Repeated startup and multiple stream consumers share one tracking session.
- First sensor deltas and repeated equal-sized recovery gaps are persisted.
- Imported records do not count already-persisted session steps twice.
- Missing permission fails before tracking; there is no data-sync service used
  as a substitute for long-running health tracking.
- A process restart does not restart the 16-hour rotation guard or lose offsets.
- Documentation distinguishes hardware support, fallback behavior, OEM battery
  restrictions, force-stop behavior, and code-tested versus device-tested cases.

## Device validation

See `ANDROID_TEST_MATRIX.md`. Physical walking, sensor batching and accuracy,
Doze, overnight rollover, OEM auto-start, and reboot behavior require real-device
results. Unit tests and a successful APK build do not establish those results.

## Implementation status — 2026-10-25

All five implementation items above are complete. Analysis, 1,005 Dart tests,
11 JVM tests, Android lint, and debug/release builds passed. Three Dart tests
requiring a real platform database are intentionally skipped on the desktop;
the real SQLite isolate integration suite passed on Android instead.

The connected Galaxy A23 passed hardware-counter startup and lifecycle tests,
logout cleanup, denied activity permission, and SQLite persistence tests.
The user also reported tracking working in foreground, background, and
terminated states on this phone; exact counts and termination method were
not recorded.
Measured walking accuracy and the remaining power-state/OEM scenarios are
tracked separately in the acceptance matrix and remain release-validation work.
