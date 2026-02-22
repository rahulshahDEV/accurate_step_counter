# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://img.shields.io/badge/tests-800%2B%20passing-brightgreen.svg)](https://github.com/rahulshahDEV/accurate_step_counter)
[![Production Ready](https://img.shields.io/badge/status-production%20ready-brightgreen.svg)](https://github.com/rahulshahDEV/accurate_step_counter)

A production-focused, accurate step counter for Flutter on Android. Works in **foreground**, **background**, and **terminated** recovery states with persistent SQLite storage.

## ✨ Features

- 🎯 **Accurate** - Uses sensors_plus accelerometer with peak detection algorithm
- 💾 **Persistent** - Steps saved to local SQLite database
- 📱 **All States** - Foreground, background, AND terminated
- 🚀 **Simple API** - One-line setup, no complexity
- 🔋 **Battery Efficient** - Event-driven, not polling
- ⏱️ **Inactivity Timeout** - Auto-reset sessions after idle periods
- 🌍 **External Import** - Import steps from Google Fit, Apple Health, etc.
- 🧪 **Well Tested** - 800+ automated tests covering lifecycle, dedupe, retention, and stress paths
- 🧵 **Low-End Device Support** - Optional background isolate for smooth UI on budget devices

## ✅ Production Readiness Scope

This package is considered production-ready for the scope below:

- Android plugin support only (no iOS implementation in this package yet)
- Min Android SDK 24+
- Duplicate-safe persistence via idempotency keys + single-writer queue
- Terminated-state reconciliation with deterministic gap dedupe
- ANR safeguards:
  - DB work can run in background isolate
  - native heavy work runs off main thread
  - stream update throttling in aggregated mode

It is not a medical device and should not be used for clinical/regulated step reporting.

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
*   **`StepRecordStore` (The Memory)**: Saves every valid step to a local SQLite database so data is never lost.
*   **`StepCounterForegroundService` (The Night Watchman)**: Keeps "The Eyes" open even when the app is closed (on older Androids).

## 📱 Platform Support

| Platform | Status | Note |
|----------|--------|------|
| Android  | ✅ Full support (API 24+) | Includes ANR-safe architecture and duplicate guards |
| iOS      | ❌ Not supported |

## 🚀 Quick Start

### 1. Install

```yaml
dependencies:
  accurate_step_counter: ^1.9.4
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

// Recommended production startup (explicit phases)
await stepCounter.initializeLogging(
  useBackgroundIsolate: true,   // smoother UI on low-end devices
  performanceTracing: false,    // enable while profiling
);
await stepCounter.start(config: StepDetectorConfig.walking());
await stepCounter.startLogging(
  config: StepRecordConfig.aggregated(useBackgroundIsolate: true),
);

final todaySteps = await stepCounter.getTodayStepCount();
stepCounter.watchTodaySteps().listen((steps) {
  print('Steps today: $steps');
});
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
    
    // Recommended production startup
    await _stepCounter.initializeLogging(useBackgroundIsolate: true);
    await _stepCounter.start(config: StepDetectorConfig.walking());
    await _stepCounter.startLogging(
      config: StepRecordConfig.aggregated(useBackgroundIsolate: true),
    );
    
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

## 🔒 Duplicate Prevention Model

- Exact-write idempotency keys are attached to records.
- Storage uses conflict-ignore + unique idempotency index.
- Writes are serialized through a single writer queue.
- Terminated sync uses deterministic gap identity and skips already-processed gaps.

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
// Presets: walking(), running(), sensitive(), conservative(), aggregated(), lowEndDevice()

// Custom config with inactivity timeout
await stepCounter.startLogging(
  config: StepRecordConfig.walking().copyWith(
    inactivityTimeoutMs: 10000, // Reset after 10s of no steps
  ),
);
```

## 📱 Low-End Device Optimization (NEW in v1.9.3)

For budget Android devices with slow storage, enable the background isolate to prevent UI jank:

```dart
// Option 1: Use the low-end device preset (recommended)
await stepCounter.startLogging(config: StepRecordConfig.lowEndDevice());

// Option 2: Enable isolate on any preset
await stepCounter.startLogging(
  config: StepRecordConfig.aggregated(useBackgroundIsolate: true),
);

// Option 3: Enable via copyWith
await stepCounter.startLogging(
  config: StepRecordConfig.walking().copyWith(useBackgroundIsolate: true),
);

// Option 4: Enable at initialization time
await stepCounter.initializeLogging(useBackgroundIsolate: true);
await stepCounter.startLogging(config: StepRecordConfig.aggregated());
```

**What it does:**
- Moves all database operations to a dedicated Dart isolate
- Prevents main thread blocking during database writes
- Adds stream throttling (10Hz max) to reduce UI rebuilds
- Fully backwards compatible - disabled by default

**When to use:**
- Budget Android devices (Android Go edition, low RAM)
- Apps with heavy UI rendering alongside step counting
- Production apps targeting broad device range

## 🧪 Testing

The package includes **800+ automated tests** covering all scenarios:

```bash
# Run all tests
flutter test

# Expected output: 00:03 +800: All tests passed!
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
| Isolate & Config | 50+ |
| Fuzz Testing | 750+ scenarios |

## ✅ Production Readiness

This package is **production ready** with:

- ✅ 800+ automated tests
- ✅ Android support scope: API 24+
- ✅ OEM compatible (MIUI, Samsung, etc.)
- ✅ Battery efficient
- ✅ No duplicate step counting
- ✅ Handles all app states
- ✅ Low-end device optimization (background isolate)
- ✅ Automatic log retention (30 days default)
- ✅ Well documented API

## 📄 License

MIT License - see [LICENSE](LICENSE)
