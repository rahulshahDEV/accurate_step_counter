# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Production Ready](https://img.shields.io/badge/status-production%20ready-brightgreen.svg)](https://github.com/rahulshahDEV/accurate_step_counter)

A production-grade, accurate step counter for Flutter on Android. Uses the native **TYPE_STEP_COUNTER** sensor via a foreground service for reliable tracking across **foreground**, **background**, and **terminated** app states.

## ✨ Features

- 🎯 **Hardware Accurate** — Uses Android's `TYPE_STEP_COUNTER` sensor (cumulative, boot-relative)
- 💾 **Persistent Storage** — SQLite database with reactive streams and background isolate support
- 📱 **All App States** — Foreground, background, AND terminated state recovery
- 🔀 **Smart Merge** — `SmartMergeHelper.mergeStepCounts()` for combining sensor + Health Connect + server sources
- 🔋 **Battery Efficient** — Event-driven architecture with notification throttling
- ⏱️ **Warmup Validation** — Filters out shakes and false positives with sliding window validation
- 🧵 **Low-End Device Support** — Optional background isolate for smooth UI on budget devices
- 🌍 **External Import** — Import steps from Google Fit, Apple Health, etc.
- 🕛 **Midnight Day Reset** — Automatic day boundary handling with alarm-based midnight reset

## 📱 Platform Support

| Platform | Status | Note |
|----------|--------|------|
| Android  | ✅ Full support (API 24+) | Native TYPE_STEP_COUNTER + foreground service |
| iOS      | ❌ Not supported |

## 🚀 Quick Start

### 1. Install

```yaml
dependencies:
  accurate_step_counter: ^2.0.0
```

### 2. Add Permissions

In `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### 3. Use It

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

final stepCounter = AccurateStepCounter();

// Initialize database + start detection + start logging
await stepCounter.initializeLogging(useBackgroundIsolate: true);
await stepCounter.start(config: StepDetectorConfig.walking());
await stepCounter.startLogging(config: StepRecordConfig.aggregated());

// Watch today's steps (emits immediately with stored value)
stepCounter.watchAggregatedStepCounter().listen((steps) {
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
    await Permission.activityRecognition.request();

    await _stepCounter.initializeLogging(useBackgroundIsolate: true);
    await _stepCounter.start(config: StepDetectorConfig.walking());
    await _stepCounter.startLogging(config: StepRecordConfig.aggregated());

    _stepCounter.watchAggregatedStepCounter().listen((steps) {
      setState(() => _steps = steps);
    });

    _stepCounter.onTerminatedStepsDetected = (steps, from, to) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $steps missed steps!')),
      );
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _stepCounter.setAppState(state);
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

## 🔀 Smart Merge (NEW in v2.0.0)

Combine multiple step sources for maximum reliability — the pattern used by production apps:

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

final merged = SmartMergeHelper.mergeStepCounts(
  sensorSteps: await stepCounter.currentStepCount,
  healthConnectSteps: hcSteps ?? 0,
  serverSteps: serverRecoveredSteps,
  currentDisplayed: displayedCount,
);
// Always returns the highest reliable value — never goes backwards
```

## 🏗️ Architecture

```
Android TYPE_STEP_COUNTER sensor
    ↓
StepCounterService.kt (Foreground service with notification)
    ↓ LocalBroadcastManager
AccurateStepCounterPlugin.kt (MethodChannel + EventChannel bridge)
    ↓ EventChannel stream
step_counter_platform.dart (Dart platform interface)
    ↓
AccurateStepCounterImpl (Detection + SQLite logging + aggregation)
    ↓
Your App (watchAggregatedStepCounter / SmartMergeHelper)
```

| App State | Behavior |
|-----------|----------|
| 🟢 **Foreground** | Real-time step events via EventChannel |
| 🟡 **Background** | Foreground service keeps counting |
| 🔴 **Terminated** | TYPE_STEP_COUNTER sync on restart + midnight alarm reset |

## 🔧 API Reference

### Core Methods

| Method | Description |
|--------|-------------|
| `start()` | Start step detection |
| `stop()` | Stop step detection |
| `isNativeStepServiceRunning()` | Check if native service is alive |
| `isUsingNativeStepService` | Whether native service mode is active |
| `currentStepCount` | Current steps since start() |

### Aggregated Mode

| Method | Description |
|--------|-------------|
| `initializeLogging()` | Initialize SQLite database |
| `startLogging()` | Start recording steps to database |
| `watchAggregatedStepCounter()` | Real-time stream (stored + live) |
| `aggregatedStepCount` | Sync getter for current total |
| `getTodaySteps()` | Today's total from database |
| `getYesterdaySteps()` | Yesterday's total from database |
| `getStepsInRange()` | Steps for custom date range |
| `writeStepsToAggregated()` | Import external steps |

### Smart Merge

| Method | Description |
|--------|-------------|
| `SmartMergeHelper.mergeStepCounts()` | Merge sensor + HC + server (max of all) |
| `SmartMergeHelper.mergeSensorAndHealth()` | Simplified merge (sensor + HC only) |

### Debug

| Method | Description |
|--------|-------------|
| `StepLogsViewer` | Widget for viewing step logs with filters |
| `getStepLogs()` | Get all step log entries |
| `getStepStats()` | Get statistics (totals by source, averages) |

## ⚙️ Configuration

```dart
// Presets
await stepCounter.start(config: StepDetectorConfig.walking());
await stepCounter.start(config: StepDetectorConfig.running());
await stepCounter.start(config: StepDetectorConfig.sensitive());
await stepCounter.start(config: StepDetectorConfig.conservative());

// Custom
await stepCounter.start(config: StepDetectorConfig(
  threshold: 1.2,
  filterAlpha: 0.85,
  minTimeBetweenStepsMs: 250,
  enableOsLevelSync: true,
  useForegroundServiceOnOldDevices: true,
  foregroundServiceMaxApiLevel: 29,
));

// Logging presets
await stepCounter.startLogging(config: StepRecordConfig.aggregated());
await stepCounter.startLogging(config: StepRecordConfig.lowEndDevice());
```

## 🔒 Reliability Features

- **Idempotency keys** — Deterministic keys prevent duplicate records
- **Single-writer queue** — Serialized database writes prevent race conditions
- **Mutex locks** — Concurrent `writeStepsToAggregated()` calls are serialized
- **Warmup validation** — Sliding window filters shakes and non-walking motion
- **Terminated sync** — Deterministic gap identity prevents double-counting
- **Midnight reset** — AlarmManager-based day boundary handling
- **Cold start recovery** — Database auto-reopens after Android kills the app

## 📱 Low-End Device Support

```dart
// Background isolate moves all DB work off the main thread
await stepCounter.initializeLogging(useBackgroundIsolate: true);
await stepCounter.startLogging(config: StepRecordConfig.lowEndDevice());
```

## 📄 License

MIT License — see [LICENSE](LICENSE)
