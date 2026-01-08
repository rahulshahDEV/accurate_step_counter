# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A simple, accurate step counter for Flutter. Works in **foreground**, **background**, and **terminated** states. Health Connect-like API with persistent storage.

## ✨ Features

- 🎯 **Accurate** - Uses Android's hardware step detector
- 💾 **Persistent** - Steps saved to local DB (Hive)
- 📱 **All States** - Foreground, background, AND terminated
- 🚀 **Simple API** - One-line setup, no complexity
- 🔋 **Battery Efficient** - Event-driven, not polling
- ⏱️ **Inactivity Timeout** - Auto-reset sessions after idle periods
- 🌍 **External Import** - Import steps from Google Fit, Apple Health, etc.

## 📱 Platform Support

| Platform | Status |
|----------|--------|
| Android  | ✅ Full support (API 19+) |
| iOS      | ❌ Not supported |

## 🚀 Quick Start

### 1. Install

```yaml
dependencies:
  accurate_step_counter: ^1.6.0
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

## 📱 How It Works

| State | Behavior |
|-------|----------|
| 🟢 **Foreground** | Real-time updates, logged as `foreground` |
| 🟡 **Background** | Continues counting, logged as `background` |
| 🔴 **Terminated** | OS tracks steps, synced on relaunch as `terminated` |

**Terminated state sync**: When you kill the app and walk, Android's step counter keeps counting. When you reopen, the package syncs missed steps and adds them to your total. This works on Android 11+.

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

## 📄 License

MIT License - see [LICENSE](LICENSE)
