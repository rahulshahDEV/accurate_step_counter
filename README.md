# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://img.shields.io/badge/tests-671%20passing-brightgreen.svg)](https://github.com/rahulshahDEV/accurate_step_counter)
[![Production Ready](https://img.shields.io/badge/status-production%20ready-brightgreen.svg)](https://github.com/rahulshahDEV/accurate_step_counter)

A simple, accurate step counter for Flutter. Works in **foreground**, **background**, and **terminated** states. Health Connect-like API with persistent storage.

## ✨ Features

- 🎯 **Accurate** - Uses sensors_plus accelerometer with peak detection algorithm
- 💾 **Persistent** - Steps saved to local DB (Hive)
- 📱 **All States** - Foreground, background, AND terminated
- 🚀 **Simple API** - One-line setup, no complexity
- 🔋 **Battery Efficient** - Event-driven, not polling
- ⏱️ **Inactivity Timeout** - Auto-reset sessions after idle periods
- 🌍 **External Import** - Import steps from Google Fit, Apple Health, etc.
- 🧪 **Well Tested** - 671 automated tests covering all scenarios

## 🛡️ Why it's Reliable (The ANR Fix)

Previous step counters (and earlier versions of this one) could freeze phones by asking **"What time is it locally?"** too often (50 times a second!). This forces the phone to read timezone files constantly, causing "Application Not Responding" (ANR) crashes on Android 12.

**This package (v1.8.10+) uses UTC time for all high-speed processing. v1.8.11+ also handles cold start scenarios where Android kills the app.**
It only converts to "Local Time" when showing steps to the user. This means:
1.  **Zero lag**: The 50Hz sensor loop never blocks the main thread.
2.  **Zero crashes**: No timezone file lockups.
3.  **100% Accuracy**: "Today" is still safely calculated based on the user's local midnight.

## 🏗️ Code Structure (Simple View)

*   **`SensorsStepDetector` (The Eyes)**: Watches the accelerometer ~50 times a second to find generic movement.
*   **`AccurateStepCounter` (The Brain)**: Filters that movement. It ignores shakes and only counts real walking.
*   **`StepRecordStore` (The Memory)**: Saves every valid step to a local database (Hive) so data is never lost.
*   **`StepCounterForegroundService` (The Night Watchman)**: Keeps "The Eyes" open even when the app is closed (on older Androids).

## 📱 Platform Support

| Platform | Status | Note |
|----------|--------|------|
| Android  | ✅ Full support (API 19+) | Includes critical ANR fix for Android 12 (v1.8.10+) |
| iOS      | ❌ Not supported |

## 🚀 Quick Start

### 1. Install

```yaml
dependencies:
  accurate_step_counter: ^1.8.12
```

### 2. Add Permissions

In `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### 3. Use It!

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

final stepCounter = AccurateStepCounter();

// 🚀 One-line setup!
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

## 📖 Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:permission_handler/permission_handler.dart';

class StepCounterPage extends StatefulWidget {
  @override
  State<StepCounterPage> createState() => _StepCounterPageState();
}

class _StepCounterPageState extends State<StepCounterPage> 
    with WidgetsBindingObserver {
  final _stepCounter = AccurateStepCounter();
  int _steps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // Request permissions
    await Permission.activityRecognition.request();
    
    // Initialize step counter
    await _stepCounter.initSteps();
    
    // Watch today's steps (emits immediately with stored value!)
    _stepCounter.watchTodaySteps().listen((steps) {
      setState(() => _steps = steps);
    });
    
    // Handle terminated state sync
    _stepCounter.onTerminatedStepsDetected = (steps, from, to) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $steps missed steps!')),
      );
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _stepCounter.setAppState(state); // Important for source tracking!
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('$_steps steps', style: TextStyle(fontSize: 48)),
      ),
    );
  }
}
```

## 🔧 API Reference

### Core Methods

| Method | Description |
|--------|-------------|
| `initSteps()` | One-line setup (DB + detector + logging) |
| `getTodayStepCount()` | Get today's total steps |
| `getYesterdayStepCount()` | Get yesterday's total steps |
| `getStepCount(start, end)` | Get steps for date range |
| `watchTodaySteps()` | Real-time stream of today's steps |
| `setAppState(state)` | Track foreground/background (call in `didChangeAppLifecycleState`) |
| `dispose()` | Clean up resources |

### Reading Logs

```dart
// Get all step logs with details
final logs = await stepCounter.getStepLogs();

for (final log in logs) {
  print('${log.stepCount} steps');
  print('From: ${log.fromTime} To: ${log.toTime}');
  print('Source: ${log.source}'); // foreground, background, terminated, external
}

// Filter by date or source
final todayLogs = await stepCounter.getStepLogs(from: startOfToday);
final bgLogs = await stepCounter.getStepLogs(source: StepRecordSource.background);
final externalLogs = await stepCounter.getStepLogs(source: StepRecordSource.external);

// Get stats
final stats = await stepCounter.getStepStats();
// {totalSteps, foregroundSteps, backgroundSteps, terminatedSteps, ...}
```

### Importing External Steps (NEW in v1.6.0)

```dart
// Import steps from Google Fit, Apple Health, wearables, etc.
await stepCounter.writeStepsToAggregated(
  stepCount: 500,
  fromTime: DateTime.now().subtract(Duration(hours: 2)),
  toTime: DateTime.now(),
  source: StepRecordSource.external, // Mark as external import
);
// All listeners automatically notified!

// Query external steps
final externalSteps = await stepCounter.getStepsBySource(
  StepRecordSource.external,
);
```

### Data Management

```dart
// Clear all logs
await stepCounter.clearStepLogs();

// Delete old logs
await stepCounter.deleteStepLogsBefore(
  DateTime.now().subtract(Duration(days: 30)),
);
```

### Debug Logs Viewer (NEW in v1.8.2)

Display step logs visually with filtering and export:

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

// Add to your widget tree
StepLogsViewer(
  stepCounter: _stepCounter,
  maxHeight: 300,
  showFilters: true,      // Filter by source (FG/BG/Term/Ext)
  showExportButton: true,  // Copy logs to clipboard
  showDatePicker: true,    // Date range filtering
)
```

Features:
- 🔍 Filter by source (foreground/background/terminated/external)
- 📅 Date range picker
- 📋 Export to clipboard
- ⚡ Real-time updates
- 🎨 Color-coded entries by source

## 📱 How It Works (Hybrid Architecture v1.8.x)

| App State | Android ≤10 (API ≤29) | Android 11+ (API 30+) |
|-----------|----------------------|----------------------|
| 🟢 **Foreground** | sensors_plus accelerometer (realtime) | Native detector (realtime) |
| 🟡 **Background** | sensors_plus accelerometer (realtime) | Native detector (realtime) |
| 🔴 **Terminated** | Foreground service with sensors_plus | TYPE_STEP_COUNTER sync on restart |

**Key Benefits (v1.8.0):**
- ✅ **More Reliable**: sensors_plus provides consistent accelerometer access across devices
- ✅ **Better UX**: No persistent notification when app is running (Android 11+)
- ✅ **Better battery**: Foreground service only runs when needed (terminated state on Android ≤10)
- ✅ **Realtime updates**: Instant step feedback in all running states
- ✅ **No duplicates**: Smart duplicate prevention prevents double-counting on rapid restarts
- ✅ **OEM Compatible**: Works reliably on MIUI, Samsung, and other aggressive battery optimization systems

**sensors_plus Step Detection Algorithm:**
- Low-pass filter for noise reduction
- Peak detection with configurable threshold
- Minimum time between steps enforcement
- **Sliding Window Validation** (v1.8.4+):
  - Checks step rate in 2-second windows during warmup
  - Prevents "shake dilution" where short bursts of shaking pass validation
  - Ensures only sustained, realistic walking is counted
- Configurable via `StepDetectorConfig`

## ⚙️ Advanced Configuration

For more control, use the advanced setup:

```dart
// Initialize database
await stepCounter.initializeLogging(debugLogging: true);

// Start with custom config
await stepCounter.start(
  config: StepDetectorConfig(
    enableOsLevelSync: true,
    useForegroundServiceOnOldDevices: true,
    foregroundServiceMaxApiLevel: 29, // Use service on Android ≤10
  ),
);

// Start logging with preset
await stepCounter.startLogging(config: StepRecordConfig.walking());
// Presets: walking(), running(), sensitive(), conservative(), aggregated()

// Custom config with inactivity timeout (NEW in v1.6.0)
await stepCounter.startLogging(
  config: StepRecordConfig.walking().copyWith(
    inactivityTimeoutMs: 10000, // Reset after 10s of no steps
  ),
);
```

## 🧪 Testing

The package includes **671 automated tests** covering all scenarios:

```bash
# Run all tests
flutter test

# Expected output: 00:02 +671: All tests passed!
```

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

## ✅ Production Readiness

This package is **production ready** with:

- ✅ 671 automated tests
- ✅ Works on all Android versions (API 19+)
- ✅ OEM compatible (MIUI, Samsung, etc.)
- ✅ Battery efficient
- ✅ No duplicate step counting
- ✅ Handles all app states
- ✅ Well documented API

## 📄 License

MIT License - see [LICENSE](LICENSE)
