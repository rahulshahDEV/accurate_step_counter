# accurate_step_counter_example

Production-style demo app for `accurate_step_counter`.

## What this example shows

- Permission request flow (`ACTIVITY_RECOGNITION` + notifications)
- Explicit startup sequence:
  - `initializeLogging(...)`
  - `start(...)`
  - `startLogging(...)`
- Aggregated stream updates for today
- Source-wise stats (foreground/background/terminated)
- Manual terminated-state sync trigger
- Lifecycle bridging via `setAppState(...)`

## Run

```bash
flutter run
```
