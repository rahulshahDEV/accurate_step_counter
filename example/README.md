# accurate_step_counter_example

Production-style demo app for `accurate_step_counter` v2.0.0.

## What this example shows

- Permission request flow (`ACTIVITY_RECOGNITION` + notifications)
- Explicit startup sequence:
  - `initializeLogging(...)`
  - `start(...)`
  - `startLogging(...)`
- Aggregated stream updates for today
- Source-wise stats (foreground/background/terminated)
- **Native service status** — Live green/red indicator for `isNativeStepServiceRunning()`
- **SmartMergeHelper demo** — Button to test `mergeStepCounts()` with current values
- Manual terminated-state sync trigger
- Lifecycle bridging via `setAppState(...)`

## Run

```bash
flutter run
```
