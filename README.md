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

### Full-Featured Step Tracker App

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step Counter',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const StepCounterPage(),
    );
  }
}

class StepCounterPage extends StatefulWidget {
  const StepCounterPage({super.key});

  @override
  State<StepCounterPage> createState() => _StepCounterPageState();
}

class _StepCounterPageState extends State<StepCounterPage> with WidgetsBindingObserver {
  // Step counter instance
  final _stepCounter = AccurateStepCounter();

  // State variables
  StreamSubscription<StepCountEvent>? _realtimeSubscription;
  int _currentSteps = 0;
  int _totalSteps = 0;
  int _foregroundSteps = 0;
  int _backgroundSteps = 0;
  int _terminatedSteps = 0;
  bool _isRunning = false;
  bool _isHardwareDetector = false;
  String _statusMessage = 'Ready to start';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeStepCounter();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // CRITICAL: Track app state for proper source detection
    _stepCounter.setAppState(state);

    setState(() {
      switch (state) {
        case AppLifecycleState.resumed:
          _statusMessage = 'App in foreground';
          break;
        case AppLifecycleState.paused:
          _statusMessage = 'App in background';
          break;
        case AppLifecycleState.inactive:
          _statusMessage = 'App inactive';
          break;
        case AppLifecycleState.detached:
          _statusMessage = 'App detached';
          break;
        case AppLifecycleState.hidden:
          _statusMessage = 'App hidden';
          break;
      }
    });
  }

  Future<void> _initializeStepCounter() async {
    try {
      // 1. Request permissions
      final permissionStatus = await Permission.activityRecognition.request();
      if (!permissionStatus.isGranted) {
        setState(() => _statusMessage = 'Permission denied');
        return;
      }

      // Android 13+ notification permission for foreground service
      await Permission.notification.request();

      // 2. Initialize logging database (with debug logging in debug builds)
      await _stepCounter.initializeLogging(debugLogging: kDebugMode);
      setState(() => _statusMessage = 'Logging initialized');

      // 3. Check detector type
      _isHardwareDetector = await _stepCounter.isUsingNativeDetector();

      // 4. Start step counter with OS-level sync for terminated state
      await _stepCounter.start(
        config: StepDetectorConfig(
          enableOsLevelSync: true,  // Enable terminated state sync
          useForegroundServiceOnOldDevices: true,
          foregroundNotificationTitle: 'Step Tracker',
          foregroundNotificationText: 'Tracking your steps...',
        ),
      );

      // 5. Start logging with walking preset
      await _stepCounter.startLogging(
        config: StepRecordConfig.walking(),
      );

      // 6. Handle terminated state steps
      _stepCounter.onTerminatedStepsDetected = (steps, startTime, endTime) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Synced $steps steps from terminated state';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Recovered $steps steps taken while app was closed'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      };

      // 7. Subscribe to real-time step events
      _realtimeSubscription = _stepCounter.stepEventStream.listen((event) {
        if (mounted) {
          setState(() => _currentSteps = event.stepCount);
        }
      });

      // 8. Watch total steps from database in real-time
      _stepCounter.watchTotalSteps().listen((total) {
        if (mounted) {
          setState(() => _totalSteps = total);
        }
      });

      setState(() {
        _isRunning = true;
        _statusMessage = _isHardwareDetector
            ? 'Running (Hardware Detector)'
            : 'Running (Accelerometer Fallback)';
      });

      // 9. Load initial stats
      _refreshStats();
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    }
  }

  Future<void> _refreshStats() async {
    try {
      final stats = await _stepCounter.getStepStats();
      final fg = await _stepCounter.getStepsBySource(StepRecordSource.foreground);
      final bg = await _stepCounter.getStepsBySource(StepRecordSource.background);
      final term = await _stepCounter.getStepsBySource(StepRecordSource.terminated);

      if (mounted) {
        setState(() {
          _foregroundSteps = fg;
          _backgroundSteps = bg;
          _terminatedSteps = term;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing stats: $e');
    }
  }

  Future<void> _toggleTracking() async {
    if (_isRunning) {
      await _stepCounter.stop();
      await _stepCounter.stopLogging();
      setState(() {
        _isRunning = false;
        _statusMessage = 'Stopped';
      });
    } else {
      await _stepCounter.start();
      await _stepCounter.startLogging(config: StepRecordConfig.walking());
      setState(() {
        _isRunning = true;
        _statusMessage = 'Running';
      });
    }
  }

  Future<void> _resetCounter() async {
    _stepCounter.reset();
    setState(() => _currentSteps = 0);
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Logs?'),
        content: const Text('This will permanently delete all step records from the database.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _stepCounter.clearStepLogs();
      _refreshStats();
      setState(() {
        _totalSteps = 0;
        _foregroundSteps = 0;
        _backgroundSteps = 0;
        _terminatedSteps = 0;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSubscription?.cancel();
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accurate Step Counter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshStats,
            tooltip: 'Refresh Stats',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isRunning ? Icons.play_circle : Icons.stop_circle,
                          color: _isRunning ? Colors.green : Colors.red,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _statusMessage,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _isHardwareDetector
                                    ? 'Hardware Detector'
                                    : 'Software Detector',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Current Steps Display
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Current Session',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_currentSteps',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const Text(
                      'steps',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Database Statistics
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Database Statistics',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    _buildStatRow('Total Steps', _totalSteps, Icons.trending_up, Colors.blue),
                    _buildStatRow('Foreground', _foregroundSteps, Icons.phone_android, Colors.green),
                    _buildStatRow('Background', _backgroundSteps, Icons.layers, Colors.orange),
                    _buildStatRow('Terminated', _terminatedSteps, Icons.power_off, Colors.red),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Control Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleTracking,
                    icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                    label: Text(_isRunning ? 'Stop' : 'Start'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _isRunning ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _resetCounter,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _clearLogs,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Clear Database', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
```

### Key Features Demonstrated

This example shows:
- ✅ **Permission handling** - Requests both activity and notification permissions
- ✅ **App lifecycle tracking** - Implements `WidgetsBindingObserver` for state detection
- ✅ **Database logging** - Initializes and uses Hive database with debug logging
- ✅ **Terminated state sync** - Handles missed steps with callback
- ✅ **Real-time updates** - Shows current steps and database stats
- ✅ **Source tracking** - Displays foreground/background/terminated breakdown
- ✅ **Proper cleanup** - Disposes resources correctly
- ✅ **User feedback** - Shows status messages and snackbars
- ✅ **Full control** - Start, stop, reset, and clear functionality

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

### Overall System Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Flutter App Layer                             │
├─────────────────────────────────────────────────────────────────────────┤
│  AccurateStepCounter (Main API)                                         │
│    ├── stepEventStream            → Real-time step events               │
│    ├── currentStepCount            → Current session steps              │
│    ├── onTerminatedStepsDetected  → Missed steps callback              │
│    ├── setAppState()               → Track foreground/background        │
│    └── Database Logging API                                             │
│         ├── initializeLogging()    → Setup Hive database                │
│         ├── startLogging()         → Auto-log with warmup validation    │
│         ├── getTotalSteps()        → Query aggregate                    │
│         ├── getStepsBySource()     → Query by source type               │
│         └── watchTotalSteps()      → Real-time database stream          │
├─────────────────────────────────────────────────────────────────────────┤
│  Hive Database (Local Storage)                                          │
│    ├── StepRecord (Model)         → {stepCount, fromTime, toTime}       │
│    ├── StepRecordSource           → foreground | background | terminated│
│    └── StepRecordStore (Service)  → CRUD operations + streams           │
├─────────────────────────────────────────────────────────────────────────┤
│  NativeStepDetector (Dart Side)                                         │
│    ├── MethodChannel              → Commands (start, stop, reset)       │
│    └── EventChannel               → Step events from native             │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │
                   Platform Channel (MethodChannel + EventChannel)
                          │
┌─────────────────────────▼───────────────────────────────────────────────┐
│                      Android Native Layer (Kotlin)                       │
├─────────────────────────────────────────────────────────────────────────┤
│  AccurateStepCounterPlugin                                              │
│    ├── NativeStepDetector.kt      → Sensor management + event streaming │
│    ├── StepCounterForegroundService.kt → Background service (API ≤29)   │
│    └── SharedPreferences          → State persistence (OS-level sync)   │
├─────────────────────────────────────────────────────────────────────────┤
│  Android Sensor Framework                                               │
│    ├── TYPE_STEP_DETECTOR         → Hardware step sensor (preferred)    │
│    ├── TYPE_STEP_COUNTER          → OS-level counter (for sync)         │
│    └── TYPE_ACCELEROMETER         → Fallback (software algorithm)       │
└─────────────────────────────────────────────────────────────────────────┘
```

### App State Handling Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                         App Lifecycle States                            │
└────────────────────────────────────────────────────────────────────────┘

🟢 FOREGROUND (AppLifecycleState.resumed)
┌─────────────────────────────────────────────┐
│  App Active & Visible                       │
│  ├── NativeStepDetector active             │
│  ├── Real-time UI updates                  │
│  ├── Steps logged as: foreground           │
│  └── Best accuracy & responsiveness        │
└─────────────────────────────────────────────┘
                    ↓ Press Home / Switch App

🟡 BACKGROUND (AppLifecycleState.paused)
┌─────────────────────────────────────────────┐
│  App Minimized but Running                  │
│                                             │
│  Android 11+ (API 30+)                     │
│  ├── Native sensor continues automatically │
│  ├── No notification needed                 │
│  └── Steps logged as: background           │
│                                             │
│  Android ≤10 (API ≤29)                     │
│  ├── Foreground Service activated          │
│  ├── Persistent notification shown          │
│  ├── WakeLock keeps CPU active             │
│  └── Steps logged as: background           │
└─────────────────────────────────────────────┘
                    ↓ Force Stop / OS Kills App

🔴 TERMINATED (App Killed)
┌─────────────────────────────────────────────┐
│  App Completely Stopped                     │
│                                             │
│  Android 11+ (API 30+)                     │
│  ├── OS continues via TYPE_STEP_COUNTER    │
│  ├── Steps tracked by Android system       │
│  ├── On relaunch: sync missed steps        │
│  └── Steps logged as: terminated           │
│                                             │
│  Android ≤10 (API ≤29)                     │
│  ├── Foreground Service prevents death     │
│  ├── Service survives Activity destruction │
│  └── No true terminated state               │
└─────────────────────────────────────────────┘
                    ↓ User Reopens App

🟢 FOREGROUND (Back to resumed)
┌─────────────────────────────────────────────┐
│  App Relaunched                             │
│  ├── onTerminatedStepsDetected fires       │
│  ├── Missed steps synced to database       │
│  └── Resume normal counting                 │
└─────────────────────────────────────────────┘
```

### Sensor Selection & Fallback Strategy

```
                    ┌─────────────────────┐
                    │   App Starts        │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ Check Android API   │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
     ┌────────▼────────┐              ┌────────▼────────┐
     │ API ≤ 29        │              │ API ≥ 30        │
     │ (Android ≤10)   │              │ (Android 11+)   │
     └────────┬────────┘              └────────┬────────┘
              │                                 │
   ┌──────────▼──────────┐          ┌─────────▼──────────┐
   │ Foreground Service  │          │ Native Detection   │
   │ - Persistent notify │          │ + OS-level sync    │
   │ - WakeLock active   │          │ - No notification  │
   │ - Keeps app alive   │          │ - Better battery   │
   └──────────┬──────────┘          └─────────┬──────────┘
              │                                 │
              └────────────────┬────────────────┘
                               │
                    ┌──────────▼──────────────┐
                    │ Check TYPE_STEP_DETECTOR│
                    │    (Hardware Sensor)    │
                    └──────────┬──────────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
     ┌────────▼────────┐              ┌────────▼────────┐
     │  ✅ Available   │              │  ❌ Not Found   │
     └────────┬────────┘              └────────┬────────┘
              │                                 │
   ┌──────────▼──────────┐          ┌─────────▼──────────┐
   │ Hardware Detection  │          │ Accelerometer      │
   │ ├─ Event-driven     │          │ + Software Algo    │
   │ ├─ Best accuracy    │          │ ├─ Low-pass filter │
   │ ├─ Battery efficient│          │ ├─ Peak detection  │
   │ └─ Android optimized│          │ └─ Configurable    │
   └─────────────────────┘          └────────────────────┘
```

### Data Flow: Step Detection → Database

```
┌──────────────────┐
│  User Walks      │  👣
└────────┬─────────┘
         │
┌────────▼───────────────────────────────────────────────────┐
│  Android Sensor (TYPE_STEP_DETECTOR or ACCELEROMETER)      │
└────────┬───────────────────────────────────────────────────┘
         │
┌────────▼─────────┐
│  NativeDetector  │  (Kotlin)
│  - Filters noise │
│  - Emits events  │
└────────┬─────────┘
         │ EventChannel
┌────────▼─────────┐
│  AccurateStep    │  (Dart)
│  Counter         │
│  - stepCount++   │
└────────┬─────────┘
         │
    ┌────▼────┐
    │ Warmup? │
    └────┬────┘
         │
    ┌────▼────────────────────────────┐
    │ YES: Buffer steps                │
    │  ├─ Wait for warmup duration    │
    │  ├─ Validate step count          │
    │  ├─ Validate step rate           │
    │  └─ Log if validated             │
    └────┬────────────────────────────┘
         │
    ┌────▼────────────────────────────┐
    │ NO: Normal logging               │
    │  ├─ Check interval elapsed       │
    │  ├─ Validate step rate           │
    │  └─ Log to database              │
    └────┬────────────────────────────┘
         │
┌────────▼─────────┐
│  Determine       │
│  Source Type     │
│  ├─ Foreground   │
│  ├─ Background   │
│  └─ Terminated   │
└────────┬─────────┘
         │
┌────────▼─────────┐
│  Hive Database   │  💾
│  StepRecord      │
│  - stepCount     │
│  - fromTime      │
│  - toTime        │
│  - source        │
│  - confidence    │
└──────────────────┘
```

### Terminated State Sync Flow (Android 11+)

```
┌─────────────────┐
│  App Running    │
│  Walk 100 steps │
└────────┬────────┘
         │
         │  Save state to SharedPreferences:
         │  - lastStepCount: 1000 (OS counter)
         │  - timestamp: 10:00 AM
         │
┌────────▼────────┐
│  App Killed     │  ❌ (Force stop or OS kills it)
└────────┬────────┘
         │
┌────────▼────────┐
│  User Walks     │  👣 Walk 50 more steps
│  (OS counting)  │  OS step counter: 1000 → 1050
└────────┬────────┘
         │
┌────────▼────────┐
│  App Relaunched │  🔄
└────────┬────────┘
         │
┌────────▼─────────────────────────────────┐
│  Sync Process (automatic)                │
│  1. Read current OS count: 1050          │
│  2. Read saved count: 1000               │
│  3. Calculate missed: 1050 - 1000 = 50   │
│  4. Validate:                            │
│     ✓ Positive number                    │
│     ✓ < 50,000 (max reasonable)          │
│     ✓ Step rate < 3 steps/sec            │
│     ✓ Time not negative                  │
│  5. onTerminatedStepsDetected(50, ...)   │
│  6. Log to database as: terminated       │
│  7. Save new baseline: 1050              │
└──────────────────────────────────────────┘
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

## 🧪 Testing & Verification

### Quick Setup Verification

Run this code to verify everything is configured correctly:

```dart
Future<void> verifySetup() async {
  final stepCounter = AccurateStepCounter();

  // 1. Check permission
  final hasPermission = await stepCounter.hasActivityRecognitionPermission();
  print('✓ Permission: $hasPermission');

  // 2. Initialize logging
  await stepCounter.initializeLogging(debugLogging: true);
  print('✓ Logging initialized: ${stepCounter.isLoggingInitialized}');

  // 3. Start counter
  await stepCounter.start();
  print('✓ Started: ${stepCounter.isStarted}');

  // 4. Check detector
  final isHardware = await stepCounter.isUsingNativeDetector();
  print('✓ Hardware detector: $isHardware');

  // 5. Enable logging
  await stepCounter.startLogging(config: StepRecordConfig.walking());
  print('✓ Logging enabled: ${stepCounter.isLoggingEnabled}');
}
```

### Real-Life Test Scenarios

The package includes **7 comprehensive test scenarios** covering all app states:

1. **Morning Walk** - Foreground state counting
2. **Background Mode** - Shopping while app is backgrounded
3. **Terminated State Recovery** - App killed and relaunched
4. **All-Day Tracking** - Mixed states throughout the day
5. **Running Workout** - High-intensity activity
6. **Device Reboot** - Handling sensor resets
7. **Permission Handling** - Edge cases and failures

See **[TESTING_SCENARIOS.md](TESTING_SCENARIOS.md)** for detailed testing instructions.

### Automated Test Runner

Use the included test script for easy testing:

```bash
chmod +x test_runner.sh
./test_runner.sh
```

The script will:
- ✅ Check device connection
- ✅ Build and install the example app
- ✅ Grant required permissions
- ✅ Run scenario tests
- ✅ Monitor logs in real-time

### Manual Testing Checklist

```
[ ] Foreground counting (100 steps, ±5% accuracy)
[ ] Background counting (proper source tracking)
[ ] Terminated state sync (missed steps recovered)
[ ] Warmup validation (prevents false positives)
[ ] Real-time stream updates
[ ] Database logging persists
[ ] Notification shows on Android ≤10
[ ] No crashes or errors
```

## 📋 Quick Reference

### Essential API Calls

```dart
// Basic Setup
final stepCounter = AccurateStepCounter();
await stepCounter.initializeLogging(debugLogging: kDebugMode);
await stepCounter.start(config: StepDetectorConfig(enableOsLevelSync: true));
await stepCounter.startLogging(config: StepRecordConfig.walking());

// App Lifecycle (CRITICAL for proper source tracking)
void didChangeAppLifecycleState(AppLifecycleState state) {
  stepCounter.setAppState(state);
}

// Real-time Step Count
stepCounter.stepEventStream.listen((event) {
  print('Steps: ${event.stepCount}');
});

// Terminated State Callback
stepCounter.onTerminatedStepsDetected = (steps, start, end) {
  print('Recovered $steps steps from $start to $end');
};

// Query Database
final total = await stepCounter.getTotalSteps();
final fgSteps = await stepCounter.getStepsBySource(StepRecordSource.foreground);
final bgSteps = await stepCounter.getStepsBySource(StepRecordSource.background);
final termSteps = await stepCounter.getStepsBySource(StepRecordSource.terminated);

// Real-time Database Stream
stepCounter.watchTotalSteps().listen((total) {
  print('Total: $total');
});

// Cleanup
await stepCounter.stop();
await stepCounter.dispose();
```

### Configuration Presets Quick Pick

| Activity | Detector Config | Logging Config |
|----------|----------------|----------------|
| **Casual Walking** | `StepDetectorConfig.walking()` | `StepRecordConfig.walking()` |
| **Running/Jogging** | `StepDetectorConfig.running()` | `StepRecordConfig.running()` |
| **High Sensitivity** | `StepDetectorConfig.sensitive()` | `StepRecordConfig.sensitive()` |
| **Strict Accuracy** | `StepDetectorConfig.conservative()` | `StepRecordConfig.conservative()` |
| **Raw Data** | Default | `StepRecordConfig.noValidation()` |

### Platform Behavior Matrix

| Feature | Android 11+ | Android ≤10 |
|---------|-------------|-------------|
| **Foreground Counting** | ✅ Native detector | ✅ Native detector |
| **Background Counting** | ✅ Automatic | ✅ Foreground service |
| **Notification** | ❌ None | ✅ Required |
| **Terminated Recovery** | ✅ OS-level sync | ⚠️ Service prevents termination |
| **Battery Impact** | 🟢 Low | 🟡 Medium |
| **Setup Required** | Minimal | Notification permission |

### Common Patterns

#### Pattern 1: Basic Real-Time Counter
```dart
final counter = AccurateStepCounter();
await counter.start();
counter.stepEventStream.listen((e) => print(e.stepCount));
```

#### Pattern 2: Persistent All-Day Tracking
```dart
final counter = AccurateStepCounter();
await counter.initializeLogging(debugLogging: kDebugMode);
await counter.start(config: StepDetectorConfig(enableOsLevelSync: true));
await counter.startLogging(config: StepRecordConfig.walking());

// Track app state in didChangeAppLifecycleState
counter.setAppState(state);

// Query anytime
final total = await counter.getTotalSteps();
```

#### Pattern 3: Activity Tracking with Source Breakdown
```dart
final counter = AccurateStepCounter();
await counter.initializeLogging(debugLogging: true);
await counter.start(config: StepDetectorConfig(enableOsLevelSync: true));
await counter.startLogging(config: StepRecordConfig.walking());

// Get breakdown
final stats = await counter.getStepStats();
print('Foreground: ${stats['foregroundSteps']}');
print('Background: ${stats['backgroundSteps']}');
print('Terminated: ${stats['terminatedSteps']}');
```

### Troubleshooting Quick Fixes

| Problem | Solution |
|---------|----------|
| No steps counted | Check `ACTIVITY_RECOGNITION` permission granted |
| Stops in background (Android ≤10) | Notification permission granted? Check battery optimization |
| No terminated sync | Set `enableOsLevelSync: true` in config |
| Database empty | Called `initializeLogging()` and `startLogging()`? |
| No real-time updates | Subscribed to `stepEventStream`? |
| Wrong source tracking | Implemented `didChangeAppLifecycleState` with `setAppState()`? |

### Debug Commands

```bash
# View all logs
adb logcat -s AccurateStepCounter NativeStepDetector StepSync

# Clear logs and watch
adb logcat -c && adb logcat -s AccurateStepCounter

# Check sensor availability
adb shell dumpsys sensorservice | grep -i step
```

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 🔗 Links

- [📦 pub.dev](https://pub.dev/packages/accurate_step_counter)
- [🐙 GitHub](https://github.com/rahulshahDEV/accurate_step_counter)
- [📋 Changelog](CHANGELOG.md)
- [🐛 Issues](https://github.com/rahulshahDEV/accurate_step_counter/issues)
- [🧪 Testing Guide](TESTING_SCENARIOS.md)

---

Made with ❤️ for the Flutter community
