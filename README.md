# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Production-grade Flutter **Android** step counter. One call to start. Hardware `TYPE_STEP_COUNTER` FGS on all API 24+.

## Install

```yaml
dependencies:
  accurate_step_counter: ^3.0.0
  permission_handler: ^11.0.0
```

Host `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
```

## 5-line usage

```dart
final steps = AccurateStepCounter();
await Permission.activityRecognition.request();
await Permission.notification.request();
await steps.startTracking();                 // DB + FGS + logging
steps.watchTodaySteps().listen(print);       // live today total
```

Lifecycle (required for midnight / resume):

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  steps.setAppState(state);
}
```

Optional once:

```dart
if (await steps.isBatteryOptimized()) {
  await steps.requestBatteryOptimization();
}
```

## What `startTracking()` does

1. Opens SQLite  
2. Starts production-hardened `TYPE_STEP_COUNTER` foreground service  
3. Reconciles native today → SQLite (fixes undercount after process death)  
4. Enables aggregated logging  

You do **not** need to call `initializeLogging` / `start` / `startLogging` yourself.

## Multi-source merge (optional)

Bring your own Health Connect / server ints — no HC SDK in this package:

```dart
final decision = SmartMergeHelper.merge(
  sensorSteps: await steps.getNativeServiceTodaySteps(),
  healthConnectSteps: hcToday,
  serverSteps: serverRecovered,
  currentDisplayed: displayed,
);
await steps.setNativeNotificationDisplay(decision.displayed);
```

## API cheat sheet

| Need | Call |
|------|------|
| Start everything | `startTracking()` |
| Today (live) | `watchTodaySteps()` / `getTodayStepCount()` |
| Aggregated stream | `watchAggregatedStepCounter()` |
| Native today | `getNativeServiceTodaySteps()` |
| Stop | `stop()` + `dispose()` |

Advanced knobs (`StepDetectorConfig`, `StepRecordConfig`, policy classes) stay available for power users.

## Platform

| Platform | Status |
|----------|--------|
| Android 24+ | Supported |
| iOS | Not supported |

## License

MIT
