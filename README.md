# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)

Step tracking for **Android API 24+** using the hardware step counter in a health
foreground service, with live streams and SQLite history.

Use one long-lived instance for the app. `startTracking()` opens storage, starts
tracking, reconciles saved counts, and observes app lifecycle automatically.

**Version 4 is Android only.** Tracking on iOS, desktop, or web is unsupported.
The experimental HealthKit implementation and `health` dependency were removed.

## Install and Android setup

```sh
flutter pub add accurate_step_counter permission_handler
```

Set the host app's Android `minSdk` to **24 or higher** and `compileSdk` to
**36 or higher**. Keep your app's target SDK aligned with its release requirements.
The package manifest merges the service, receivers, sensor declarations, and
permissions into the app; you normally do not need to copy service declarations.

Request activity recognition before starting. Android requires that runtime
permission from API 29 onward. Request notification permission on API 33+ so the
user can see the ongoing tracking notification. Start while an app activity is
visible; recent Android versions restrict starting services from the background.

```dart
import 'dart:async';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

class StepsController {
  final counter = AccurateStepCounter();
  StreamSubscription<int>? _subscription;

  Future<void> start(ValueChanged<int> onSteps) async {
    final activity = await Permission.activityRecognition.request();
    if (!activity.isGranted) {
      throw StateError('Activity recognition permission is required.');
    }
    await Permission.notification.request();
    await counter.startTracking();
    await _subscription?.cancel();
    _subscription = counter.watchTodaySteps().listen(onSteps);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await counter.dispose();
  }
}
```

Call `WidgetsFlutterBinding.ensureInitialized()` in `main()` before using the
package. For an Android-only app the snippet above is sufficient; guard your
platform before calling it in a cross-platform host. Denied activity permission
raises `StateError`; an unsupported tracking platform raises `UnsupportedError`.
Handle these errors in the UI and offer a retry after the user grants permission.
Notification denial does not grant or revoke sensor access.

Keep the controller above screen lifetime when tracking should continue across
navigation. `dispose()` stops the Android service as well as Dart subscriptions.

## Everyday use

```dart
final counter = AccurateStepCounter();
await counter.startTracking(); // after permissions

final subscription = counter.watchTodaySteps().listen((today) {
  // Update your UI.
});
final today = await counter.getTodayStepCount();
final yesterday = await counter.getYesterdayStepCount();
final week = await counter.getStepsInRange(
  DateTime.now().subtract(const Duration(days: 6)),
  DateTime.now(),
);

// Stop tracking and flush buffered records. Starting again is supported.
await counter.stop();
await counter.startTracking();

await subscription.cancel();
await counter.dispose();
```

Concurrent or repeated `startTracking()` calls share the current startup/session.
The first call's configuration applies until tracking is stopped. Use one
instance; multiple counter instances share the Android service and database,
so one instance stopping or disposing can affect another.

The default `watchTodaySteps()` stream emits the current value then updates when
records or sensor events change. Each call creates an independently cancellable
subscription. The hardware sensor may batch readings, so a stream update is not
promised on every footstep.

| API | Meaning |
| --- | --- |
| `watchTodaySteps()` | Today's stored/live total; follows the new date after midnight |
| `getTodayStepCount()` / `getTodaySteps()` | Today, using the greater of SQLite and the active native service |
| `getYesterdayStepCount()` | Yesterday, using SQLite plus the active native backup |
| `getStepsInRange(start, end)` | Stored history, including the end calendar day |
| `watchAggregatedStepCounter()` | Today's stored baseline plus accepted session increments |
| `aggregatedStepCount` | Synchronous aggregate; requires aggregated logging |
| `stepEventStream` | Detection-source counts; semantics depend on the detector |
| `getNativeServiceTodaySteps()` | Native service's own today total; excludes display-only merges |
| `getStepLogs()` / `watchStepLogs()` | Interval records with source information |
| `getStepStats()` | Stored totals and counts by source |

Historical queries use stored records; they cannot reconstruct walks before
tracking was installed or granted permission. Default retention is 30 days.

## Walking, running, and storage

The default walking profile uses native limits of 180 steps
per trailing minute and 9,000 per trailing hour. Those limits can clip sustained
running. Use the running preset for a higher cadence:

```dart
await counter.startTracking(
  detectorConfig: StepDetectorConfig.running(), // 240/min and 14,400/hour
  useBackgroundIsolate: true, // default; moves database work off the UI isolate
  debugLogging: false,
  performanceTracing: false,
);
```

Custom native limits are available through `nativeMaxStepsPerMinute` and
`nativeMaxStepsPerHour` in `StepDetectorConfig`. Raise them only with device
measurements: larger limits also admit more sensor noise. The short burst guard,
vehicle filtering, and available step-detector cross-check still apply.
Accelerometer threshold/filter settings tune the fallback detector rather than
the hardware counter itself.

### Shake rejection and validation time

`StepRecordConfig.walking()` uses a **5-second** logging warmup;
`StepRecordConfig.running()` uses **3 seconds**. A custom duration is available:

```dart
await counter.startTracking(
  loggingConfig: StepRecordConfig.walking().copyWith(warmupDurationMs: 3000),
);
```

Warmup buffers candidate logging increments and checks minimum steps and step
rate, including checks every two seconds. The default aggregated logging config
has no warmup. This is a Dart logging filter, not a native shake lockout: native
totals and later reconciliation remain authoritative for hardware tracking.
The native service separately applies a five-second burst guard, cadence limits,
vehicle filtering, and a step-detector cross-check when evidence is available.
Shaking that resembles valid walking can still pass a phone's hardware sensors;
these settings do not guarantee rejection of every shake.

`startTracking()` defaults to aggregated logging, writes buffered increments
about every three seconds, and flushes when queries, stop, or lifecycle changes
require it. An abrupt process kill can interrupt Dart writes; the next start
reconciles the native persisted count. A database isolate is not a separate
Android process and does not run after that process is killed.

## Background, midnight, reboot, and battery

The Android foreground service owns the sensor listener and native persistence.
It can keep tracking while the Flutter screen is backgrounded. `startTracking()`
registers the Flutter lifecycle observer; advanced callers using
`initializeLogging()` + `start()` + `startLogging()` must forward lifecycle via
`setAppState()` themselves.

At a day boundary the service rotates its counters and saves a date-stamped
snapshot. Dart drains that snapshot on startup, resume, and live events. Old
counts are stored against their actual date, including after a multi-day gap.
Calendar/time-zone changes are handled with rotation guards; this is not a
server-enforced anti-cheat system.

| Situation | Expected behavior and limit |
| --- | --- |
| App backgrounded or screen off | Native health service continues, subject to device power restrictions |
| Swipe from recents | Service normally remains; some OEMs treat this more aggressively |
| OS kills/restarts the process | Restore persisted native state and reconcile SQLite on next start |
| Device reboots | Restart previously enabled tracking after normal boot if activity permission remains granted |
| Explicit `stop()` or logout | Tracking remains disabled across reboot |
| User force-stops the app | Android prevents restart until the user opens it again |
| Exact alarm access unavailable | Inexact alarm, sensor events, and app resume provide rollover recovery; timing can drift |
| Sensor/service was inactive | Missing intervals may be unrecoverable; the package cannot invent those steps |

On devices that restrict background work, offer battery exclusion when the user
enables continuous tracking:

```dart
if (await counter.isBatteryOptimized()) {
  await counter.requestBatteryOptimization();
}
final serviceAlive = await counter.isNativeStepServiceRunning();
```

`requestBatteryOptimization()` opens Android's battery optimization settings so
the user can select the app. Its result reports whether settings opened; check
`isBatteryOptimized()` again after returning to learn whether the setting changed.

Xiaomi/Redmi/POCO, OPPO/Realme, Vivo/iQOO, Samsung, and other OEMs may also need an
app-specific unrestricted-battery or auto-start setting. Exclusion improves the
chance of continued operation; it cannot override a force-stop or every OEM rule.
The package requests `SCHEDULE_EXACT_ALARM`, with an inexact fallback, and uses a
health foreground service rather than a time-limited data-sync service.

## Device coverage

Tracking supports Android API 24+ **when the phone exposes suitable sensors**.
`TYPE_STEP_COUNTER` availability is a device capability, not guaranteed by brand
or Android version:

```dart
final hasHardwareCounter = await counter.hasNativeStepServiceSensor();
```

Without that counter, the package can use its legacy step detector/accelerometer
path, with weaker accuracy and background guarantees. The optional legacy
foreground service is disabled by default; it can keep a process alive but does
not make a Dart accelerometer listener reliable after process termination.
For an app requiring hardware counting, check `hasNativeStepServiceSensor()` and
show an unsupported-device state when false.

Vehicle/bicycle filtering uses Google Play Services and degrades gracefully when
it is unavailable. Native step counting itself does not require Google Play
Services. Phones with poor sensor firmware can still overcount or miss steps.

No universal accuracy percentage or all-phone certification is claimed. The
[device acceptance matrix](doc/ANDROID_TEST_MATRIX.md) lists required physical
checks and the evidence collected for this change. A simulator without a step
sensor cannot establish walking accuracy.

## Optional Health Connect or server display merge

The package does not read Health Connect or contact your backend. Your app can
supply filtered totals to the public merge policy:

```dart
final decision = SmartMergeHelper.merge(
  sensorSteps: await counter.getNativeServiceTodaySteps(),
  healthConnectSteps: filteredHealthConnectTotal,
  serverSteps: recoveredServerTotal,
  currentDisplayed: displayedToday,
);
displayedToday = decision.displayed;
await counter.setNativeNotificationDisplay(displayedToday);
```

Inspect `overcountingDetected` and `hcDuplicationDetected` for diagnostics. Filter
manual/unknown Health Connect records and apply `smoothHcReading` if necessary
before merging. The policy uses ratio heuristics to recognize duplicated sources
or drifting sensors; it is not a clinical reference or a fraud guarantee.

`setNativeNotificationDisplay()` updates notification text without changing sensor
state. `forceUpdateNativeTodaySteps()` changes the native offset and can preserve
an inflated imported reading for the rest of the day; reserve it for an explicit,
validated correction. Keep overlapping HC/server data in the display merge.

## Import distinct historical records

```dart
await counter.writeStepsToAggregated(
  stepCount: 420,
  fromTime: DateTime(2026, 7, 25, 8),
  toTime: DateTime(2026, 7, 25, 9),
  source: StepRecordSource.external,
);
```

Imports add records. Supply distinct increments/intervals, not a repeatedly polled
cumulative daily total or a second copy of sensor steps. The default fuzzy
retry check catches many duplicates; deterministic internal record keys also
prevent identical records from being inserted twice. Cross-day intervals are
split proportionally by duration, which is an estimate of when the steps occurred.
Keep imported data tagged `StepRecordSource.external` so native recovery can
distinguish it from sensor records and preserve both contributions.

## Logout and account switching

```dart
await counter.stop();
await counter.clearStepLogs();
await counter.resetNativeStepState();
// Reuse after permissions, or dispose and create a new instance.
```

`clearStepLogs()` clears SQLite; `resetNativeStepState()` clears native state.
Both are needed when the next account must not inherit activity from the previous
account. The host remains responsible for clearing its own merged/server totals.
The deprecated synchronous `reset()` only resets legacy session detectors; it
throws for persisted hardware daily totals instead of pretending to clear them.

## Migration to 4.0

- iOS tracking and the `health` dependency are removed. Use a separate
  platform-specific health integration in a cross-platform host.
- Tracking on unsupported platforms fails explicitly. Local storage APIs remain
  independently usable where their dependencies support the host.
- `startTracking()` observes lifecycle and tolerates concurrent/repeated startup.
  Manual lifecycle forwarding remains available for advanced setup.
- `stop()` now stops logging and flushes pending records. Call `startTracking()`
  to resume the complete pipeline.
- Native running limits now follow `StepDetectorConfig.running()`.
- Permission and service-start failures are surfaced rather than silently
  selecting a weaker detector when a hardware counter is available.

See [the implementation plan](doc/ANDROID_RELIABILITY_PLAN.md) and
[device acceptance matrix](doc/ANDROID_TEST_MATRIX.md) for the changes and evidence.

## Development

```sh
flutter pub get
flutter analyze
flutter test
cd example
flutter pub get
flutter build apk --debug
```

The example contains a live counter, service status, logs, verification, and
warmup screens. Start with a real Android phone for walking and overnight tests.

MIT licensed. See [LICENSE](LICENSE).
