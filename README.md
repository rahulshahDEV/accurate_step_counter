# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A highly accurate Flutter plugin for step counting using native Android `TYPE_STEP_DETECTOR` sensor with accelerometer fallback. Includes local Hive database logging with warmup validation. Zero external dependencies. Designed for reliability across foreground, background, and terminated app states.

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎯 **Native Detection** | Uses Android's hardware-optimized `TYPE_STEP_DETECTOR` sensor |
| 🔄 **Accelerometer Fallback** | Software algorithm for devices without step detector |
| 💾 **Hive Logging** | Local persistent storage with source tracking (foreground/background/terminated) |
| 🔥 **Warmup Validation** | Buffer steps during warmup, validate walking before logging |
| 📦 **Zero Dependencies** | Only requires Flutter SDK + Hive |
| 🔋 **Battery Efficient** | Event-driven, not polling-based |
| 📱 **All App States** | Foreground, background, and terminated state support |
| ⚙️ **Configurable** | Presets for walking/running + custom parameters |

## 📱 Platform Support

| Platform | Status |
|----------|--------|
| Android  | ✅ Full support (API 19+) |
| iOS      | ❌ Not supported |

> **Note**: This is an Android-only package. It won't crash on iOS but step detection won't work.

## 🚀 Quick Start

### 1. Install

```yaml
dependencies:
  accurate_step_counter: ^1.3.0
```

### 2. Add Permissions

In `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### 3. Request Runtime Permission

```dart
import 'package:permission_handler/permission_handler.dart';

// Request activity recognition (required)
await Permission.activityRecognition.request();

// Request notification (for Android 13+ foreground service)
await Permission.notification.request();
```

### 4. Start Counting!

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

final stepCounter = AccurateStepCounter();

// Listen to step events
stepCounter.stepEventStream.listen((event) {
  print('Steps: ${event.stepCount}');
});

// Start counting
await stepCounter.start();

// Stop when done
await stepCounter.stop();

// Clean up
await stepCounter.dispose();
```

## 📖 Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'dart:async';

class StepCounterScreen extends StatefulWidget {
  @override
  State<StepCounterScreen> createState() => _StepCounterScreenState();
}

class _StepCounterScreenState extends State<StepCounterScreen> {
  final _stepCounter = AccurateStepCounter();
  StreamSubscription<StepCountEvent>? _subscription;
  int _steps = 0;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _subscription = _stepCounter.stepEventStream.listen((event) {
      setState(() => _steps = event.stepCount);
    });
  }

  Future<void> _toggleTracking() async {
    if (_isRunning) {
      await _stepCounter.stop();
    } else {
      await _stepCounter.start();
    }
    setState(() => _isRunning = !_isRunning);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Step Counter')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_steps', style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold)),
            const Text('steps', style: TextStyle(fontSize: 24, color: Colors.grey)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _toggleTracking,
              icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_isRunning ? 'Stop' : 'Start'),
            ),
            TextButton(
              onPressed: () {
                _stepCounter.reset();
                setState(() => _steps = 0);
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## ⚙️ Configuration

### Presets

```dart
// For walking (default)
await stepCounter.start(config: StepDetectorConfig.walking());

// For running (more sensitive, faster detection)
await stepCounter.start(config: StepDetectorConfig.running());

// Sensitive mode (may have false positives)
await stepCounter.start(config: StepDetectorConfig.sensitive());

// Conservative mode (fewer false positives)
await stepCounter.start(config: StepDetectorConfig.conservative());
```

### Custom Configuration

```dart
await stepCounter.start(
  config: StepDetectorConfig(
    threshold: 1.2,                // Movement threshold (higher = less sensitive)
    filterAlpha: 0.85,             // Smoothing factor (0.0 - 1.0)
    minTimeBetweenStepsMs: 250,    // Minimum ms between steps
    enableOsLevelSync: true,       // Sync with OS step counter
    
    // Foreground service options
    useForegroundServiceOnOldDevices: true,
    foregroundServiceMaxApiLevel: 29, // API level threshold (default: 29 = Android 10)
    foregroundNotificationTitle: 'Step Tracker',
    foregroundNotificationText: 'Counting your steps...',
  ),
);
```

### Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `threshold` | 1.0 | Movement threshold for step detection |
| `filterAlpha` | 0.8 | Low-pass filter smoothing (0.0-1.0) |
| `minTimeBetweenStepsMs` | 200 | Minimum time between steps |
| `enableOsLevelSync` | true | Sync with OS step counter |
| `useForegroundServiceOnOldDevices` | true | Use foreground service on older Android |
| `foregroundServiceMaxApiLevel` | 29 | Max API level for foreground service (29=Android 10, 31=Android 12, etc.) |
| `foregroundNotificationTitle` | "Step Counter" | Notification title |
| `foregroundNotificationText` | "Tracking your steps..." | Notification text |

## 🔧 API Reference

### AccurateStepCounter

```dart
final stepCounter = AccurateStepCounter();

// Properties
stepCounter.stepEventStream       // Stream<StepCountEvent>
stepCounter.currentStepCount      // int
stepCounter.isStarted             // bool
stepCounter.isUsingForegroundService  // bool
stepCounter.currentConfig         // StepDetectorConfig?

// Methods
await stepCounter.start({config});    // Start detection
await stepCounter.stop();             // Stop detection
stepCounter.reset();                  // Reset count to zero
await stepCounter.dispose();          // Clean up resources

// Check sensor type
final isHardware = await stepCounter.isUsingNativeDetector();

// Terminated state sync (automatic, but can be manual)
stepCounter.onTerminatedStepsDetected = (steps, startTime, endTime) {
  print('Synced $steps missed steps');
};
```

### StepCountEvent

```dart
final event = StepCountEvent(stepCount: 100, timestamp: DateTime.now());

event.stepCount   // int - Total steps since start()
event.timestamp   // DateTime - When step was detected
```

## 💾 Hive Step Logging

### Setup

```dart
import 'package:flutter/foundation.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';

final stepCounter = AccurateStepCounter();

// Initialize logging database
// debugLogging: kDebugMode = only show console logs in debug builds
await stepCounter.initializeLogging(debugLogging: kDebugMode);

// Start counting
await stepCounter.start();

// Start logging with a preset
await stepCounter.startLogging(config: StepLoggingConfig.walking());
```

### Debug Logging Parameter

Control console output with the `debugLogging` parameter:

```dart
// No console output (default - recommended for production)
await stepCounter.initializeLogging(debugLogging: false);

// Always show console logs
await stepCounter.initializeLogging(debugLogging: true);

// Only in debug builds (recommended)
await stepCounter.initializeLogging(debugLogging: kDebugMode);
```

Console output examples when `debugLogging: true`:
```
AccurateStepCounter: Logging database initialized
AccurateStepCounter: Warmup started
AccurateStepCounter: Warmup validated - 15 steps at 1.87/s
AccurateStepCounter: Logged 15 warmup steps (source: StepLogSource.foreground)
```

### Logging Presets

| Preset | Warmup | Min Steps | Max Rate | Use Case |
|--------|--------|-----------|----------|----------|
| `walking()` | 5s | 8 | 3/s | Casual walks |
| `running()` | 3s | 10 | 5/s | Jogging/running |
| `sensitive()` | 0s | 3 | 6/s | Quick detection |
| `conservative()` | 10s | 15 | 2.5/s | Strict accuracy |
| `noValidation()` | 0s | 1 | 100/s | Raw data |

```dart
// Use a preset
await stepCounter.startLogging(config: StepLoggingConfig.walking());

// Custom configuration
await stepCounter.startLogging(
  config: StepLoggingConfig(
    logIntervalMs: 5000,       // Log every 5 seconds
    warmupDurationMs: 8000,    // 8 second warmup period
    minStepsToValidate: 10,    // Need 10+ steps to confirm walking
    maxStepsPerSecond: 4.0,    // Reject rates above 4/second
  ),
);
```

### Complete Example

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';

class StepTrackerPage extends StatefulWidget {
  @override
  State<StepTrackerPage> createState() => _StepTrackerPageState();
}

class _StepTrackerPageState extends State<StepTrackerPage> 
    with WidgetsBindingObserver {
  final _stepCounter = AccurateStepCounter();
  int _totalSteps = 0;
  int _foregroundSteps = 0;
  int _backgroundSteps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // 1. Initialize logging (with debug output in debug builds)
    await _stepCounter.initializeLogging(debugLogging: kDebugMode);
    
    // 2. Start step detection
    await _stepCounter.start();
    
    // 3. Start logging with walking preset
    await _stepCounter.startLogging(config: StepLoggingConfig.walking());
    
    // 4. Listen to total steps in real-time
    _stepCounter.watchTotalSteps().listen((total) {
      setState(() => _totalSteps = total);
    });
    
    // 5. Handle terminated state sync
    _stepCounter.onTerminatedStepsDetected = (steps, from, to) {
      print('Synced $steps steps from terminated state');
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Track app state for proper source detection
    _stepCounter.setAppState(state);
  }

  Future<void> _refreshStats() async {
    final fg = await _stepCounter.getStepsBySource(StepLogSource.foreground);
    final bg = await _stepCounter.getStepsBySource(StepLogSource.background);
    setState(() {
      _foregroundSteps = fg;
      _backgroundSteps = bg;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Total: $_totalSteps steps'),
        Text('Foreground: $_foregroundSteps'),
        Text('Background: $_backgroundSteps'),
        ElevatedButton(
          onPressed: _refreshStats,
          child: Text('Refresh Stats'),
        ),
      ],
    );
  }
}
```

### Query API

```dart
// Aggregate total
final total = await stepCounter.getTotalSteps();

// Today's steps
final today = DateTime.now();
final startOfDay = DateTime(today.year, today.month, today.day);
final todaySteps = await stepCounter.getTotalSteps(from: startOfDay);

// By source
final fgSteps = await stepCounter.getStepsBySource(StepLogSource.foreground);
final bgSteps = await stepCounter.getStepsBySource(StepLogSource.background);
final termSteps = await stepCounter.getStepsBySource(StepLogSource.terminated);

// Get all logs
final logs = await stepCounter.getStepLogs();

// Statistics
final stats = await stepCounter.getStepStats();
// Returns: {totalSteps, entryCount, averagePerEntry, averagePerDay, 
//           foregroundSteps, backgroundSteps, terminatedSteps}
```

### Real-Time Streams

```dart
// Watch total steps
stepCounter.watchTotalSteps().listen((total) {
  print('Total: $total');
});

// Watch all logs with filter
stepCounter.watchStepLogs(source: StepLogSource.foreground).listen((logs) {
  for (final log in logs) {
    print('${log.stepCount} steps at ${log.toTime}');
  }
});
```

### Data Management

```dart
// Clear all logs
await stepCounter.clearStepLogs();

// Delete logs older than 30 days
await stepCounter.deleteStepLogsBefore(
  DateTime.now().subtract(Duration(days: 30)),
);
```

## 🏗️ Architecture

### Overall Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter App                              │
├─────────────────────────────────────────────────────────────────┤
│  AccurateStepCounter                                            │
│       ├── stepEventStream (real-time steps)                     │
│       ├── currentStepCount                                      │
│       └── onTerminatedStepsDetected (missed steps callback)     │
├─────────────────────────────────────────────────────────────────┤
│  NativeStepDetector (Dart)                                      │
│       ├── MethodChannel (commands)                              │
│       └── EventChannel (step events)                            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                    Platform Channel
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                     Android Native (Kotlin)                      │
├─────────────────────────────────────────────────────────────────┤
│  AccurateStepCounterPlugin                                      │
│       ├── NativeStepDetector.kt (sensor handling)               │
│       ├── StepCounterForegroundService.kt (Android ≤10)         │
│       └── SharedPreferences (state persistence)                 │
├─────────────────────────────────────────────────────────────────┤
│  Android Sensors                                                │
│       ├── TYPE_STEP_DETECTOR (primary - hardware)               │
│       └── TYPE_ACCELEROMETER (fallback - software)              │
└─────────────────────────────────────────────────────────────────┘
```

### Step Detection Priority

```
┌─────────────────────────────────────────────────┐
│            Check: TYPE_STEP_DETECTOR            │
│              (Hardware Sensor)                  │
└──────────────────────┬──────────────────────────┘
                       │
           ┌───────────▼───────────┐
           │     Available?        │
           └───────────┬───────────┘
                       │
          ┌────────────┴────────────┐
          │                         │
    ┌─────▼─────┐            ┌──────▼──────┐
    │    YES    │            │     NO      │
    └─────┬─────┘            └──────┬──────┘
          │                         │
┌─────────▼─────────┐    ┌─────────▼─────────┐
│  Hardware Step    │    │  Accelerometer    │
│  Detection        │    │  + Algorithm      │
│                   │    │                   │
│  • Best accuracy  │    │  • Low-pass filter│
│  • Battery saving │    │  • Peak detection │
│  • Event-driven   │    │  • Configurable   │
└───────────────────┘    └───────────────────┘
```

## 📱 App State Coverage

### How Each State is Handled

| App State | Android 11+ (API 30+) | Android ≤10 (API ≤29) |
|-----------|----------------------|----------------------|
| 🟢 **Foreground** | Native `TYPE_STEP_DETECTOR` | Native `TYPE_STEP_DETECTOR` |
| 🟡 **Background** | Native detection continues | **Foreground Service** keeps counting |
| 🔴 **Terminated** | OS sync on app relaunch | **Foreground Service** prevents termination |
| 📢 **Notification** | ❌ **None** (not needed) | ✅ **Shows** (required by Android) |

> **Important**: The persistent notification **only appears on Android devices with API level ≤ `foregroundServiceMaxApiLevel`** (default: 29 = Android 10). On newer devices, no notification is shown because the native step detector works without needing a foreground service.

### Detailed State Behavior

#### 🟢 Foreground State
```
App Active → NativeStepDetector → TYPE_STEP_DETECTOR → EventChannel → Flutter UI
```
- Real-time step counting with immediate updates
- Hardware-optimized detection
- Full access to all sensors

#### 🟡 Background State

**Android 11+:**
```
App Minimized → Native detection continues → Steps buffered → UI updates when resumed
```

**Android ≤10:**
```
App Minimized → Foreground Service starts → Persistent notification shown
                    ↓
              Keeps CPU active via WakeLock
                    ↓
              Steps counted continuously
                    ↓
              Results polled every 500ms
```

#### 🔴 Terminated State

**Android 11+:**
```
App Killed → OS continues counting via TYPE_STEP_COUNTER
                    ↓
             App Relaunched
                    ↓
       Compare saved count with current OS count
                    ↓
       Calculate missed steps
                    ↓
       Trigger onTerminatedStepsDetected callback
```

**Android ≤10:**
```
Foreground Service prevents true termination
                    ↓
       Service continues counting even if Activity destroyed
                    ↓
       No steps are ever missed
```

### Terminated State Sync (Android 11+)

```dart
// Automatic sync happens on start(), but you can handle it:
stepCounter.onTerminatedStepsDetected = (missedSteps, startTime, endTime) {
  print('You walked $missedSteps steps while app was closed!');
  print('From: $startTime to $endTime');
  
  // Optionally save to database or sync to server
  saveToDatabase(missedSteps, startTime, endTime);
};
```

## 🔋 Battery & Performance

| Metric | Value |
|--------|-------|
| Detection Method | Event-driven (not polling) |
| CPU Usage | Minimal (~1-2%) |
| Battery Impact | Low (uses hardware sensor) |
| Memory | ~2-5 MB |
| Foreground Service Battery | Moderate (only Android ≤10) |

## 🐛 Debugging

### View Logs

```bash
# All plugin logs
adb logcat -s AccurateStepCounter NativeStepDetector StepSync

# Only step events
adb logcat -s NativeStepDetector
```

### Check Sensor Availability

```dart
final isHardware = await stepCounter.isUsingNativeDetector();
print('Using hardware step detector: $isHardware');
```

## ❓ Troubleshooting

| Issue | Solution |
|-------|----------|
| Steps not detected | Check `ACTIVITY_RECOGNITION` permission is granted |
| Inaccurate counts | Try adjusting `threshold` parameter |
| Stops in background | Enable foreground service or check battery optimization |
| No notification (Android ≤10) | Grant notification permission |

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 🔗 Links

- [📦 pub.dev](https://pub.dev/packages/accurate_step_counter)
- [🐙 GitHub](https://github.com/rahulshahDEV/accurate_step_counter)
- [📋 Changelog](CHANGELOG.md)
- [🐛 Issues](https://github.com/rahulshahDEV/accurate_step_counter/issues)

---

Made with ❤️ for the Flutter community
