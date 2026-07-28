# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://opensource.org/licenses/MIT)](https://opensource.org/licenses/MIT)

Production-grade Flutter step counter for **Android + iOS**.

One call starts hardware `TYPE_STEP_COUNTER` tracking in a foreground service, SQLite logging, midnight/boot recovery, and live streams. Optional BYO Health Connect / server merge — no HC SDK baked in.

> Android uses native `TYPE_STEP_COUNTER` foreground service.  
> iOS uses HealthKit via the `health` package (manual-entry filtered).

---

## Table of contents

1. [Install](#install)
2. [Quick start](#quick-start)
3. [How it works](#how-it-works)
4. [Pick your use case](#pick-your-use-case)
5. [Reading steps](#reading-steps)
6. [Lifecycle & battery](#lifecycle--battery)
7. [Multi-source merge](#multi-source-merge-health-connect--server)
8. [Configuration](#configuration)
9. [API reference](#api-reference)
10. [Platform & device notes](#platform--device-notes)
11. [Troubleshooting](#troubleshooting)
12. [Migration from 2.x](#migration-from-2x)

---

## Install

```yaml
dependencies:
  accurate_step_counter: ^3.1.0
  permission_handler: ^11.0.0   # request runtime permissions
```

### Android permissions

The plugin merges most permissions. Declare them in the **host** app if you strip merges or want them explicit:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
```

Request at runtime **before** `startTracking()` on Android:

| Permission | When |
|------------|------|
| `ACTIVITY_RECOGNITION` | Android 10+ — required for step sensor / health FGS |
| `POST_NOTIFICATIONS` | Android 13+ — FGS shows an ongoing notification |

---

## Quick start

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

class StepsController with WidgetsBindingObserver {
  final steps = AccurateStepCounter();

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);

    await Permission.activityRecognition.request();
    await Permission.notification.request();

    await steps.startTracking(); // DB + FGS + aggregated logging

    // Optional but strongly recommended on Xiaomi / Oppo / Vivo / Samsung
    if (await steps.isBatteryOptimized()) {
      await steps.requestBatteryOptimization();
    }

    steps.watchTodaySteps().listen((n) {
      // Update UI
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Required: drains midnight rotation when user returns to the app
    steps.setAppState(state);
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await steps.dispose();
  }
}
```

On iOS, `startTracking()` requests HealthKit read permission for steps and starts polling Health app totals.

---

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter                                                    │
│  startTracking() → SQLite + watchTodaySteps / aggregated    │
│  setAppState()   → midnight drain + fg/bg source tags       │
│  SmartMergeHelper (optional) ← your HC / server ints        │
└───────────────────────────┬─────────────────────────────────┘
                            │ MethodChannel / EventChannel
┌───────────────────────────▼─────────────────────────────────┐
│  StepCounterService (foreground service)                    │
│  • TYPE_STEP_COUNTER hardware sensor                        │
│  • TYPE_STEP_DETECTOR cross-check (drop vibration)          │
│  • Rate caps: burst / per-minute / per-hour                 │
│  • Vehicle / bicycle filter via Play Services (soft-fail)   │
│  • SharedPreferences persist + reboot detect                │
│  • Exact midnight alarm + BootReceiver + time/TZ receiver   │
│  • Ongoing notification (display sync without poisoning     │
│    sensor baseline)                                         │
└─────────────────────────────────────────────────────────────┘
```

### Data flow (today total)

1. Hardware sensor reports cumulative steps since boot.
2. Native service converts that to **today** (baseline at midnight / boot).
3. Dart reconciles native today → SQLite on start (fills gaps after process death).
4. New steps are logged with source tags (`foreground` / `background` / `terminated` / `external`).
5. `getTodayStepCount()` returns `max(SQLite, native)` when the FGS is active so UI never undercounts after a kill.

### What survives what

| Event | What happens |
|-------|----------------|
| App swipe-away | FGS keeps counting; prefs persist |
| Process death | On next start: native prefs restore + SQLite reconcile |
| Device reboot | `BootReceiver` restarts FGS (if AR granted) + re-arms midnight |
| Local midnight | Alarm rotates day; Flutter drains stamp on resume / stream |
| User changes time / TZ | `TimeChangeReceiver` rotates or reschedules alarm |
| Force-stop by user | OS stops FGS until next open (Android rule) |

### Accuracy guards (native)

- Min increment + debounce (filters micro-vibrations)
- Burst / 180 steps/min / 9000 steps/hour caps (Samsung drift)
- `TYPE_STEP_DETECTOR` mismatch → drop phantom counter jumps
- In-vehicle / bicycle window (Play Services) → drop road/pedal noise
- Monotonic 16h guard against clock-spin fake midnights

---

## Pick your use case

### 1) Simple fitness / daily steps app

Show today’s steps, keep counting in background.

```dart
await steps.startTracking();
steps.watchTodaySteps().listen(setStateSteps);

// Later
final today = await steps.getTodayStepCount();
final yesterday = await steps.getYesterdayStepCount();
```

Wire `setAppState` and ask for battery exclusion once (see [Lifecycle & battery](#lifecycle--battery)).

---

### 2) Rewards / “steps for points” app

Need stable today totals, anti-cheat rate limits, and recovery after kill.

```dart
await steps.startTracking(
  useBackgroundIsolate: true, // better on low-end phones
  debugLogging: kDebugMode,
);

// Authoritative today for payouts
final today = await steps.getTodayStepCount();

// Prefer native when you need the same number as the notification
final nativeToday = await steps.getNativeServiceTodaySteps();
```

Do **not** trust raw accelerometer fallback for payouts. Require `hasNativeStepServiceSensor()` / `isUsingNativeStepService`.

```dart
if (!await steps.hasNativeStepServiceSensor()) {
  // Show “device not supported” — no hardware step counter
}
```

---

### 3) App with Health Connect / Google Fit / server baseline

This package does **not** talk to Health Connect. You read HC (or your API), then merge:

```dart
final sensor = await steps.getNativeServiceTodaySteps();
final hc = await yourHealthConnectToday();      // your code
final server = await yourApi.recoveredSteps();  // your code

final decision = SmartMergeHelper.merge(
  sensorSteps: sensor,
  healthConnectSteps: hc,
  serverSteps: server,
  currentDisplayed: currentlyShownInUi,
);

setState(() => displayed = decision.displayed);

// Keep FGS notification in sync WITHOUT poisoning the sensor baseline
await steps.setNativeNotificationDisplay(decision.displayed);
```

`MergeDecision` flags help debugging:

- `sensorOvercounting` — trust HC, sensor was high
- `hcDuplicated` — HC looks like a double-sum vs sensor
- floor / server floor bookkeeping for stable UI

**Never** call `forceUpdateNativeTodaySteps(merged)` with HC-inflated values for day-long display sync — that bakes bad HC into the sensor offset. Use `setNativeNotificationDisplay` instead.

---

### 4) Import historical / external steps into SQLite

```dart
await steps.startTracking(); // enables aggregated mode

await steps.writeStepsToAggregated(
  stepCount: 4200,
  fromTime: DateTime(2026, 7, 25, 8),
  toTime: DateTime(2026, 7, 25, 12),
  source: StepRecordSource.external,
  skipIfDuplicate: true, // default — safe for retries
);
```

---

### 5) Low-end device / avoid UI jank

```dart
await steps.startTracking(
  useBackgroundIsolate: true,
  loggingConfig: StepRecordConfig.lowEndDevice(),
);
```

Stream UI updates are throttled (~10 Hz) automatically.

---

### 6) Logout / account switch

```dart
await steps.clearStepLogs();
await steps.resetNativeStepState();
await steps.stop();
// Next login: startTracking() again
```

---

### 7) Custom detection (advanced)

Prefer `startTracking()`. Only split the pipeline if you need odd control:

```dart
await steps.initializeLogging(useBackgroundIsolate: true);
await steps.start(config: StepDetectorConfig.walking());
await steps.startLogging(config: StepRecordConfig.aggregated());
```

---

## Reading steps

| Goal | API |
|------|-----|
| Live today (SQLite-backed) | `watchTodaySteps()` |
| One-shot today | `getTodayStepCount()` / `getTodaySteps()` |
| Yesterday | `getYesterdayStepCount()` |
| Live stored + session (aggregated) | `watchAggregatedStepCounter()` |
| Sync getter for aggregated | `aggregatedStepCount` |
| Hardware service today | `getNativeServiceTodaySteps()` |
| Hardware yesterday | `getNativeServiceYesterdaySteps()` |
| Custom range | `getStepsInRange(start, end)` / `getStepCount(start:, end:)` |
| By source | `getStepsBySource(StepRecordSource.background)` |
| Raw log rows | `getStepLogs()` / `watchStepLogs()` |
| Stats map | `getStepStats()` |

### Which “today” should I show?

| Source | Best for |
|--------|----------|
| `watchTodaySteps` / `getTodayStepCount` | Default UI — SQLite + native max |
| `watchAggregatedStepCounter` | Same day live+stored session model |
| `getNativeServiceTodaySteps` | Match notification / merge input |

---

## Lifecycle & battery

### App lifecycle (required)

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  steps.setAppState(state);
}
```

Without this, midnight rotation stamps may not drain into UI until much later, and fg/bg log sources stay wrong.

### Battery optimization (strongly recommended)

Aggressive OEMs (Xiaomi, Oppo, Vivo, some Samsung) kill background work even with an FGS.

```dart
if (await steps.isBatteryOptimized()) {
  await steps.requestBatteryOptimization();
}
```

Also guide users to OEM “autostart” / “unrestricted battery” screens when you care about overnight counting.

### Service health check

```dart
if (steps.isUsingNativeStepService &&
    !await steps.isNativeStepServiceRunning()) {
  await steps.start(); // or startTracking again after stop
}
```

---

## Multi-source merge (Health Connect / server)

```dart
final decision = SmartMergeHelper.merge(
  sensorSteps: sensor,
  healthConnectSteps: hc,
  serverSteps: server,
  currentDisplayed: displayed,
);

decision.displayed;           // int to show
decision.sensorOvercounting;  // bool
decision.hcDuplicated;        // bool
```

Helpers:

```dart
SmartMergeHelper.mergeStepCounts(...);     // int only
SmartMergeHelper.mergeSensorAndHealth(...);
SmartMergeHelper.mergeYesterday(...);
```

Policy details live in `StepLogic` / `MergePolicy` / `smoothHcReading` / `RotationGuard` if you need custom orchestration.

---

## Configuration

### `startTracking` knobs

```dart
await steps.startTracking(
  useBackgroundIsolate: true,
  debugLogging: kDebugMode,
  performanceTracing: false,
  detectorConfig: StepDetectorConfig.walking(),
  loggingConfig: StepRecordConfig.aggregated(
    useBackgroundIsolate: true,
  ),
);
```

### Logging presets (`StepRecordConfig`)

| Preset | Intent |
|--------|--------|
| `aggregated()` | **Default via `startTracking`** — continuous Health Connect–like day total |
| `walking()` | Warmup + ~3 steps/s cap |
| `running()` | Faster interval, ~5 steps/s |
| `sensitive()` | Minimal filtering |
| `conservative()` | Strict warmup |
| `noValidation()` | Raw logging |
| `lowEndDevice()` | Isolate + lighter write pattern |

### Detector presets (`StepDetectorConfig`)

Mostly affect the **legacy accel / sensors_plus fallback**. The primary `TYPE_STEP_COUNTER` FGS uses native hardening instead.

| Preset | Notes |
|--------|--------|
| `walking()` / `running()` / `sensitive()` / `conservative()` | Accel path tuning |
| `useForegroundServiceOnOldDevices: true` | Enable only if device has **no** step-counter hardware |

---

## API reference

### Essentials

| Method | Description |
|--------|-------------|
| `startTracking()` | DB + FGS + aggregated logging (recommended entry) |
| `stop()` | Stop detection / FGS |
| `dispose()` | Release everything |
| `setAppState(state)` | Lifecycle hook |
| `isBatteryOptimized()` | OS restricting the app? |
| `requestBatteryOptimization()` | Prompt unrestricted battery |

### Queries & streams

| Method | Description |
|--------|-------------|
| `watchTodaySteps()` | Stream\<int\> today |
| `getTodayStepCount()` | Future\<int\> today |
| `getYesterdayStepCount()` | Future\<int\> yesterday |
| `watchAggregatedStepCounter()` | Stream\<int\> stored + session |
| `getNativeServiceTodaySteps()` | Native FGS today |
| `setNativeNotificationDisplay(n)` | Notification text only |
| `writeStepsToAggregated(...)` | Import external steps |
| `clearStepLogs()` | Wipe SQLite |
| `resetNativeStepState()` | Wipe native prefs (logout) |

### Status

| Getter / method | Description |
|-----------------|-------------|
| `isStarted` | Detection running |
| `isUsingNativeStepService` | Dart chose FGS path |
| `isNativeStepServiceRunning()` | OS still has FGS alive |
| `hasNativeStepServiceSensor()` | Hardware present |
| `runtimeState` | `StepRuntimeState` enum |
| `hasActivityRecognitionPermission()` | AR granted? |

---

## Platform & device notes

| Platform / device | Status |
|-------------------|--------|
| Android 24+ with `TYPE_STEP_COUNTER` | **Supported** (primary) |
| No step hardware | Soft-fallback only — enable legacy FGS explicitly if needed |
| Huawei / no Google Play Services | Counts; vehicle filter soft-disabled |
| Xiaomi / Oppo / Vivo / aggressive Samsung | Works if battery unrestricted + autostart |
| Force-stopped by user | Stops until next app open |
| Emulator without sensors | Will not count |
| iOS 14+ HealthKit | **Supported** (Health app step source) |

`minSdk` is **24**. Step hardware is declared with `android:required="false"` so installs still succeed on devices without it.

### iOS setup

Add HealthKit usage text in your app `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app reads your step count to show daily activity.</string>
```

Enable the HealthKit capability in Xcode for your app target.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Always 0 steps | Request `ACTIVITY_RECOGNITION`; confirm `hasNativeStepServiceSensor()` |
| Stops overnight | `requestBatteryOptimization()` + OEM autostart; verify `isNativeStepServiceRunning()` in morning |
| Notification ≠ UI | `setNativeNotificationDisplay(merged)` after merge |
| Undercount after kill | Use `getTodayStepCount()` / `startTracking` reconcile — not a stale in-memory int |
| Midnight UI stuck on yesterday | Call `setAppState` on resume |
| Play Console permission pushback | Do not add `USE_EXACT_ALARM`; package already avoids it |
| Double counting with HC | Use `SmartMergeHelper.merge`, not `max(sensor, hc)` |
| ANR on cheap phones | `useBackgroundIsolate: true` |

Enable diagnostics:

```dart
await steps.startTracking(
  debugLogging: true,
  performanceTracing: true,
);
```

---

## Migration from 2.x

1. Bump to `^3.0.0`.
2. Prefer `await steps.startTracking()` over `initializeLogging` + `start` + `startLogging`.
3. Replace naive `max()` merges with `SmartMergeHelper.merge(...)`.
4. Sync notification with `setNativeNotificationDisplay`, not `forceUpdateNativeTodaySteps`.
5. Keep supplying HC/server yourself (BYO).

See [CHANGELOG.md](CHANGELOG.md) for the full 3.0 breaking list.

---

## Example app

```bash
cd example && flutter run
```

Includes verification + warmup pages for device QA.

---

## License

MIT
