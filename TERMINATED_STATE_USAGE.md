# Using Terminated State Step Sync

This guide explains how to use the accurate_step_counter package to automatically sync steps that were counted while your app was terminated.

## Overview

The package now automatically syncs steps from OS-level sensors when returning from terminated state. This ensures zero data loss even when the app is killed.

## How It Works

1. **When app is running**: Steps are saved to native SharedPreferences periodically
2. **When app is terminated**: Android OS continues counting steps via `TYPE_STEP_COUNTER` sensor
3. **When app reopens**: The package automatically:
   - Compares current OS step count with last saved count
   - Validates the difference (checks for sensor resets, unreasonable values, etc.)
   - Returns missed steps via callback

## Setup

### 1. Basic Usage (Automatic Sync)

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

final stepCounter = AccurateStepCounter();

// Enable OS-level sync (enabled by default)
await stepCounter.start(
  config: StepDetectorConfig(
    enableOsLevelSync: true, // This is the default
  ),
);
```

The sync happens automatically during `start()`. If there were missed steps while the app was terminated, they will be reported via the callback.

### 2. Handling Terminated State Steps

To receive missed steps, register a callback before calling `start()`:

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

final stepCounter = AccurateStepCounter();

// Register callback for terminated state steps
stepCounter.onTerminatedStepsDetected = (missedSteps, startTime, endTime) {
  print('Found $missedSteps steps from terminated state');
  print('Time range: $startTime to $endTime');

  // Write these steps to your health/fitness storage
  // For example, to Health Connect:
  // await writeStepsToHealthConnect(missedSteps, startTime, endTime);
};

// Start the counter (this will trigger sync automatically)
await stepCounter.start();
```

### 3. Manual Sync

You can also manually trigger a sync if needed:

```dart
final result = await stepCounter.syncTerminatedSteps();

if (result != null) {
  final missedSteps = result['missedSteps'] as int;
  final startTime = result['startTime'] as DateTime;
  final endTime = result['endTime'] as DateTime;

  print('Synced $missedSteps steps manually');
}
```

### 4. Full Example with Data Storage

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

class StepTracker {
  final stepCounter = AccurateStepCounter();
  int totalStepCount = 0;

  Future<void> initialize() async {
    // Set up callback for terminated state steps
    stepCounter.onTerminatedStepsDetected = (missedSteps, startTime, endTime) async {
      print('Syncing $missedSteps steps from terminated state');
      print('Time range: $startTime to $endTime');

      // Add missed steps to your total count
      totalStepCount += missedSteps;

      // Save to your preferred storage (database, cloud, health platform, etc.)
      await saveStepsToStorage(missedSteps, startTime, endTime);

      print('Successfully saved missed steps');
    };

    // Start counter with OS-level sync enabled
    await stepCounter.start(
      config: StepDetectorConfig(
        enableOsLevelSync: true,
        threshold: 1.0,
      ),
    );

    // Listen to real-time step events
    stepCounter.stepEventStream.listen((event) {
      print('Current steps: ${event.stepCount}');
      totalStepCount = event.stepCount;
    });
  }

  Future<void> saveStepsToStorage(int steps, DateTime startTime, DateTime endTime) async {
    // Implement your storage logic here
    // Examples:
    // - Save to local database (SQLite, Hive, etc.)
    // - Upload to cloud backend
    // - Write to health platform (Health Connect, HealthKit, etc.)
    // - Update user profile/statistics
  }

  Future<void> dispose() async {
    await stepCounter.dispose();
  }
}
```

## Validation

The sync process includes multiple validations to ensure data quality:

1. **Positive steps check**: Only syncs if missed steps > 0
2. **Time validation**: Ensures timestamp hasn't gone backwards
3. **Reasonable limit check**: Rejects counts > 50,000 steps (likely sensor reset)
4. **Rate validation**: Ensures step rate ≤ 3 steps/second

If any validation fails, `null` is returned and no steps are synced.

## Android Permissions

Make sure your `AndroidManifest.xml` includes:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
```

## Troubleshooting

### Steps not syncing after termination

1. **Check OS-level sync is enabled**: Verify `enableOsLevelSync: true` in config
2. **Register callback before start()**: The callback must be set before calling `start()`
3. **Check logs**: Enable debug logging to see detailed sync information:
   ```dart
   // The package logs to 'AccurateStepCounter' and 'StepCounter' tags
   // Filter with: adb logcat -s AccurateStepCounter StepCounter
   ```

### Sensor not available

Some devices may not have the `TYPE_STEP_COUNTER` sensor. Check availability:

```dart
final osSteps = await stepCounter.getOsStepCount();
if (osSteps == null) {
  print('OS-level step counter not available on this device');
  // Fall back to accelerometer-only mode
  await stepCounter.start(
    config: StepDetectorConfig(enableOsLevelSync: false),
  );
}
```

## Health Platform Integration (Optional)

If you want to write steps to health platforms like Health Connect or HealthKit, you can use the [health](https://pub.dev/packages/health) package:

```dart
// Add to your app's pubspec.yaml (NOT the package itself):
// dependencies:
//   health: ^13.1.4

import 'package:health/health.dart';

stepCounter.onTerminatedStepsDetected = (steps, start, end) async {
  final health = Health();

  // Request permissions first
  final types = [HealthDataType.STEPS];
  final permissions = [HealthDataAccess.WRITE];
  final granted = await health.requestAuthorization(types, permissions: permissions);

  if (granted) {
    await health.writeHealthData(
      value: steps.toDouble(),
      type: HealthDataType.STEPS,
      startTime: start,
      endTime: end,
    );
  }
};
```

**Note**: The `accurate_step_counter` package does NOT include health platform dependencies. Add them to your app only if needed.

## Device Reboot Handling

When the device reboots, the OS step counter resets to 0. The package handles this automatically:
- Detects when OS count is less than previously saved count
- Validates against reasonable step limits
- Continues tracking from new OS baseline

No action needed from your app!

## Best Practices

1. **Always register callback before start()**: Otherwise you might miss the terminated state event
2. **Save state periodically**: Call `stepCounter.saveState()` periodically during long tracking sessions
3. **Handle errors**: Wrap health data writes in try-catch blocks
4. **Test thoroughly**: Test by:
   - Force-killing the app
   - Walking around
   - Reopening the app
   - Verifying missed steps are reported

## Example Test Scenario

```
1. Open app → stepCounter.start()
2. Walk 100 steps
3. Force kill app (swipe away from recents)
4. Walk 50 more steps
5. Reopen app → stepCounter.start()
6. Callback receives: missedSteps = 50
```

## Notes

- The terminated state sync only works on Android (iOS uses different mechanisms)
- Steps are synced once per app launch (during the first `start()` call)
- The OS sensor continues counting even when device is locked or app is killed
- SharedPreferences are used for persistent storage (survives app termination)
