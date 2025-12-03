# Accurate Step Counter

[![pub package](https://img.shields.io/pub/v/accurate_step_counter.svg)](https://pub.dev/packages/accurate_step_counter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A highly accurate Flutter plugin for step counting using advanced accelerometer-based detection with low-pass filtering and peak detection algorithms. Designed for reliability across foreground, background, and terminated app states on Android.

## Features

✨ **Highly Accurate Detection**

- Advanced accelerometer-based step detection
- Low-pass filtering to reduce noise
- Peak detection algorithm for reliable step counting
- Configurable sensitivity parameters

📱 **Comprehensive State Support**

- **Foreground**: Real-time step counting while app is active
- **Background**: Continues tracking when app is in background
- **Terminated**: Syncs steps taken while app was completely closed
- Zero data loss across all app states

🔧 **Flexible Configuration**

- Preset configurations for walking and running
- Fine-tune threshold, filtering, and timing parameters
- Enable/disable OS-level step counter synchronization

🛡️ **Production Ready**

- Robust error handling
- Validated step data (prevents unrealistic counts)
- Battery efficient
- Well-tested and documented

## Platform Support

| Platform | Supported | Notes                             |
| -------- | --------- | --------------------------------- |
| Android  | ✅        | Full support with OS-level sensor |
| iOS      | 🚧        | Planned for future release        |

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  accurate_step_counter: ^1.1.1
```

Then run:

```bash
flutter pub get
```

### Android Setup

Add the following permissions to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
```

For Android 10+ (API level 29+), you'll need to request the permission at runtime:

```dart
import 'package:permission_handler/permission_handler.dart';

// Request permission
if (await Permission.activityRecognition.request().isGranted) {
  // Permission granted, start step counting
}
```

## Quick Start

### Basic Usage

```dart
import 'package:accurate_step_counter/accurate_step_counter.dart';

class MyStepCounter {
  final _stepCounter = AccurateStepCounter();

  Future<void> startCounting() async {
    // Listen to step events
    _stepCounter.stepEventStream.listen((event) {
      print('Steps: ${event.stepCount}');
      print('Timestamp: ${event.timestamp}');
    });

    // Start counting
    await _stepCounter.start();
  }

  Future<void> stopCounting() async {
    await _stepCounter.stop();
  }

  void dispose() {
    _stepCounter.dispose();
  }
}
```

### With Custom Configuration

```dart
// Walking mode (default)
await stepCounter.start(
  config: StepDetectorConfig.walking(),
);

// Running mode (more sensitive)
await stepCounter.start(
  config: StepDetectorConfig.running(),
);

// Custom configuration
await stepCounter.start(
  config: StepDetectorConfig(
    threshold: 1.2,              // Movement threshold (higher = less sensitive)
    filterAlpha: 0.85,           // Low-pass filter smoothing (0.0 - 1.0)
    minTimeBetweenStepsMs: 250,  // Minimum time between steps in milliseconds
    enableOsLevelSync: true,     // Sync with OS step counter (Android only)
  ),
);
```

### Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'dart:async';

class StepCounterPage extends StatefulWidget {
  @override
  _StepCounterPageState createState() => _StepCounterPageState();
}

class _StepCounterPageState extends State<StepCounterPage> {
  final _stepCounter = AccurateStepCounter();
  StreamSubscription<StepCountEvent>? _subscription;
  int _stepCount = 0;
  bool _isTracking = false;

  @override
  void initState() {
    super.initState();
    _initStepCounter();
  }

  void _initStepCounter() {
    _subscription = _stepCounter.stepEventStream.listen((event) {
      setState(() {
        _stepCount = event.stepCount;
      });
    });
  }

  Future<void> _startTracking() async {
    try {
      await _stepCounter.start(config: StepDetectorConfig.walking());
      setState(() => _isTracking = true);
    } catch (e) {
      print('Error starting: $e');
    }
  }

  Future<void> _stopTracking() async {
    await _stepCounter.stop();
    setState(() => _isTracking = false);
  }

  void _resetCounter() {
    _stepCounter.reset();
    setState(() => _stepCount = 0);
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
      appBar: AppBar(title: Text('Step Counter')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Steps', style: TextStyle(fontSize: 24)),
            Text('$_stepCount', style: TextStyle(fontSize: 72, fontWeight: FontWeight.bold)),
            SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isTracking ? null : _startTracking,
                  child: Text('Start'),
                ),
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isTracking ? _stopTracking : null,
                  child: Text('Stop'),
                ),
              ],
            ),
            ElevatedButton(
              onPressed: _resetCounter,
              child: Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## API Reference

### AccurateStepCounter

Main class for step counting functionality.

#### Properties

- `stepEventStream` - Stream of `StepCountEvent` objects
- `currentStepCount` - Current step count since `start()`
- `isStarted` - Whether the step counter is currently active
- `currentConfig` - Current configuration being used

#### Methods

##### `start({StepDetectorConfig? config})`

Starts step detection.

**Parameters:**

- `config` - Optional configuration (defaults to walking mode)

**Throws:**

- `StateError` if already started

**Example:**

```dart
await stepCounter.start(config: StepDetectorConfig.walking());
```

##### `stop()`

Stops step detection while preserving the current step count.

**Example:**

```dart
await stepCounter.stop();
```

##### `reset()`

Resets the step counter to zero. Does not stop detection if running.

**Example:**

```dart
stepCounter.reset();
```

##### `dispose()`

Disposes of all resources. Call when completely done with the step counter.

**Example:**

```dart
await stepCounter.dispose();
```

##### `getOsStepCount()`

Gets the OS-level step count (Android only). Returns `null` if unavailable or OS-level sync is disabled.

**Example:**

```dart
final osSteps = await stepCounter.getOsStepCount();
if (osSteps != null) {
  print('OS reports: $osSteps steps');
}
```

##### `saveState()`

Manually saves the current state for recovery after app termination (Android only).

**Example:**

```dart
await stepCounter.saveState();
```

### StepDetectorConfig

Configuration for step detection sensitivity and behavior.

#### Constructors

##### `StepDetectorConfig()`

Creates a default configuration for general walking.

**Parameters:**

- `threshold` (default: 1.0) - Movement threshold for step detection
- `filterAlpha` (default: 0.8) - Low-pass filter coefficient (0.0 - 1.0)
- `minTimeBetweenStepsMs` (default: 300) - Minimum milliseconds between steps
- `enableOsLevelSync` (default: true) - Enable OS-level step counter sync

##### `StepDetectorConfig.walking()`

Preset configuration optimized for normal walking pace.

##### `StepDetectorConfig.running()`

Preset configuration optimized for running/jogging.

### StepCountEvent

Event emitted when steps are detected.

#### Properties

- `stepCount` - Total steps since `start()`
- `timestamp` - DateTime when the step was detected

## How It Works

### Step Detection Algorithm

1. **Accelerometer Data Collection**: Continuously monitors device accelerometer
2. **Low-Pass Filtering**: Applies smoothing to reduce noise and false positives
3. **Magnitude Calculation**: Computes movement magnitude from X, Y, Z axes
4. **Peak Detection**: Identifies peaks that exceed the configured threshold
5. **Step Validation**: Ensures minimum time between steps to prevent double-counting

### State Management

#### Foreground/Background

- Uses accelerometer-based detection via `sensors_plus` package
- Continues tracking even when app is in background
- Periodically syncs to OS-level step counter (if enabled)

#### Terminated State (Android)

- Saves current OS step count to SharedPreferences before termination
- On app restart, compares saved count with current OS count
- Validates and syncs any missed steps
- Includes safety checks for device reboots and unrealistic step counts

## Performance & Battery

- **CPU Usage**: Minimal - uses native sensor APIs
- **Battery Impact**: Low - sensor sampling optimized for efficiency
- **Memory**: ~2-5 MB depending on configuration
- **Background**: Works seamlessly with Android's Doze mode

## Troubleshooting

### Steps not being detected

1. Ensure `ACTIVITY_RECOGNITION` permission is granted
2. Verify device has accelerometer sensor
3. Try adjusting threshold (lower = more sensitive)
4. Check that app has not been force-stopped by system

### Inaccurate step counts

1. Calibrate by comparing with known step counts
2. Adjust `threshold` parameter based on device/user
3. Try different preset configurations (walking vs running)
4. Ensure device is held in typical position during calibration

### App crashes or errors

1. Check Android version (requires API 19+)
2. Verify sensor availability: `sensorManager.getDefaultSensor(TYPE_ACCELEROMETER)`
3. Review logs for specific error messages
4. Ensure proper lifecycle management (call `dispose()`)

## Debugging & Logging

The package includes comprehensive logging to help debug issues. View logs using:

### Android Logcat

```bash
# View all plugin logs
adb logcat -s AccurateStepCounter StepCounter StepSync

# View only step sync logs (terminated state)
adb logcat -s StepSync

# View only sensor events
adb logcat -s StepCounter
```

### Log Tags

The package uses the following log tags:

- **AccurateStepCounter**: Main plugin lifecycle and method calls
- **StepCounter**: Sensor events and step counting
- **StepSync**: Terminated state synchronization

### Dart Logs

Dart-side logs are available in Flutter DevTools or console:

```bash
# Run with verbose logging
flutter run --verbose
```

### Example Log Output

```
D/AccurateStepCounter: Plugin attached to Flutter engine
D/AccurateStepCounter: Initializing sensor manager
D/AccurateStepCounter: Step counter sensor found: Step Counter Sensor
D/AccurateStepCounter: Sensor vendor: Google, version: 1
D/AccurateStepCounter: Sensor listener registered
D/StepCounter: onSensorChanged: Sensor reported 1234 steps
D/StepSync: === Starting syncStepsFromTerminatedState ===
D/StepSync: Current OS step count: 1284
D/StepSync: Last saved step count: 1234 at timestamp: 1234567890
D/StepSync: Calculated: 50 missed steps over 10 minutes
D/StepSync: Step rate: 0.083 steps/second
D/StepSync: ✓ All validations passed!
D/StepSync: Syncing 50 steps from terminated state
```

## Examples

See the [example](example) directory for a complete working app demonstrating:

- Basic step counting
- Start/stop/reset functionality
- Custom configurations
- Stream subscription management
- Proper lifecycle handling

## Testing

Run the tests:

```bash
cd accurate_step_counter
flutter test
```

Run integration tests:

```bash
cd example
flutter test integration_test
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Integration with Health Platforms

This package focuses on accurate step counting and does not include built-in health platform integrations. If you need to sync steps to health platforms:

- **Android Health Connect**: Use the [health](https://pub.dev/packages/health) package
- **iOS HealthKit**: Use the [health](https://pub.dev/packages/health) package
- **Custom backends**: Implement your own storage solution

Example with health package (add it separately):

```dart
// Add health: ^13.1.4 to your app's pubspec.yaml
import 'package:health/health.dart';

stepCounter.onTerminatedStepsDetected = (steps, start, end) async {
  final health = Health();
  await health.writeHealthData(
    value: steps.toDouble(),
    type: HealthDataType.STEPS,
    startTime: start,
    endTime: end,
  );
};
```

## Acknowledgments

- Uses [sensors_plus](https://pub.dev/packages/sensors_plus) for accelerometer access
- Inspired by research in mobile step detection algorithms
- Thanks to all contributors and testers

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Support

- 📖 [Documentation](https://pub.dev/documentation/accurate_step_counter)
- 🐛 [Issue Tracker](https://github.com/rahulshahDEV/accurate_step_counter/issues)
- 💬 [Discussions](https://github.com/rahulshahDEV/accurate_step_counter/discussions)

---

Made with ❤️ for the Flutter community
