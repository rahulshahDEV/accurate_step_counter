# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-12-30

### Added
- 🔔 **Foreground Service Support**: Reliable step counting on Android ≤10
  - Automatically detects Android version and uses foreground service when needed
  - Persistent notification keeps step counting active even when app is minimized
  - Customizable notification title and text via `StepDetectorConfig`
  - No additional code required - works automatically!

- 📱 **New Config Options** in `StepDetectorConfig`:
  - `useForegroundServiceOnOldDevices` - Enable/disable foreground service mode (default: `true`)
  - `foregroundNotificationTitle` - Custom notification title (default: "Step Counter")
  - `foregroundNotificationText` - Custom notification text (default: "Tracking your steps...")

- 🔍 **New API Properties**:
  - `isUsingForegroundService` - Check if foreground service mode is active

- 📄 **New Platform Methods** (internal):
  - `getAndroidVersion()` - Get device Android API level
  - `startForegroundService()` / `stopForegroundService()` - Control the service
  - `getForegroundStepCount()` - Read steps from service
  - `resetForegroundStepCount()` - Reset service step counter

### Changed
- 🔧 **Smart Mode Selection**: Package now auto-detects Android version:
  - Android 11+ (API 30+): Uses native step detection + terminated state sync
  - Android 10 and below (API ≤29): Uses foreground service with notification

- 🚀 **Native Step Detection**: Replaced `sensors_plus` with native Kotlin implementation
  - Uses `TYPE_STEP_DETECTOR` sensor for hardware-optimized step counting
  - Falls back to accelerometer with software algorithm if unavailable
  - Zero third-party dependencies
  - Better battery efficiency

### Removed
- 🗑️ **Dependency Cleanup**: Removed `sensors_plus` package
  - Step detection now handled entirely in native Kotlin code
  - Reduces package size and dependency complexity

### Technical Details
- **New File**: `StepCounterForegroundService.kt` - Kotlin foreground service implementation
- **New File**: `NativeStepDetector.kt` - Native step detection with TYPE_STEP_DETECTOR
- **Notification**: Uses low-priority, silent notification to minimize user impact
- **Wake Lock**: Keeps CPU active for accurate sensor reading
- **EventChannel**: Real-time step events from native to Flutter

### Migration Guide
No breaking changes! Existing code works without modification.

```dart
// The foreground service is automatic for Android ≤10
await stepCounter.start();

// Customize notification (optional)
await stepCounter.start(config: StepDetectorConfig(
  foregroundNotificationTitle: 'Walking Tracker',
  foregroundNotificationText: 'Counting your steps...',
));

// Disable foreground service if desired (not recommended for Android ≤10)
await stepCounter.start(config: StepDetectorConfig(
  useForegroundServiceOnOldDevices: false,
));
```

### Android Manifest Changes
The following permissions are now included in the plugin:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

> **Note**: On Android 13+, users may need to grant notification permission for the foreground service notification to appear.

---

## [1.1.1] - 2025-12-03

### Removed
- 🗑️ **Dependency Cleanup**: Removed unnecessary `health` package dependency
  - The `health` package was included but never used in the plugin code
  - Removed unused `health_connect_service.dart` file
  - Reduces package size and eliminates unnecessary dependencies
  - Users can still integrate with health platforms by adding the `health` package to their own app

### Added
- 📊 **Comprehensive Logging System**: Added detailed logging throughout the package
  - **Android Kotlin**: Enhanced logging in all methods with structured tags
    - `AccurateStepCounter`: Plugin lifecycle and method calls
    - `StepCounter`: Sensor events and step data
    - `StepSync`: Terminated state synchronization with detailed validation logs
  - **Dart**: Added logging to platform channel calls and error handling
  - Logs include sensor details (name, vendor, version)
  - Step sync logs show elapsed time, step rate, and validation results
  - Makes debugging and troubleshooting much easier for developers

- 📖 **Debugging Documentation**: Added comprehensive debugging section to README
  - How to view logs using `adb logcat`
  - Explanation of all log tags
  - Example log output for common scenarios
  - Commands for filtered logging

### Changed
- 📖 **Documentation Updates**:
  - Updated README with clear guidance on optional health platform integration
  - Updated TERMINATED_STATE_USAGE.md with health integration examples as optional feature
  - Clarified that health platform integration is the responsibility of the consuming app
  - Added example code showing how to integrate with health platforms if needed
  - Added "Debugging & Logging" section with practical examples
  - Updated GitHub repository URLs to use `rahulshahDEV` username

- 🔧 **Code Quality**: Fixed lint warning about unnecessary library name

### Improved
- 🎯 **Package Focus**: Narrowed package scope to core step counting functionality
  - Package now focuses exclusively on accurate step detection and counting
  - Health platform integrations are left to the consuming application
  - Provides better separation of concerns and flexibility for users

- 🔍 **Enhanced Error Tracking**: Improved error handling and logging
  - Platform exceptions are caught and logged with details
  - Better sensor availability detection and reporting
  - Validation failures in sync process are clearly logged with reasons

- 🛠️ **Developer Experience**: Package is now much easier to debug
  - Clear log messages at every step
  - Sensor information logged on initialization
  - Detailed terminated state sync process with timestamps and calculations
  - All validation checks logged with pass/fail reasons

### Migration Guide
No breaking changes! Existing code continues to work without modifications.

If you were expecting health platform integration:
1. Add `health: ^13.1.4` to your app's `pubspec.yaml` (not the plugin)
2. Use the `onTerminatedStepsDetected` callback to write steps to health platforms
3. See README and TERMINATED_STATE_USAGE.md for complete examples

### Debugging
Use these commands to view logs:
```bash
# View all plugin logs
adb logcat -s AccurateStepCounter StepCounter StepSync

# View only sync logs
adb logcat -s StepSync
```

---

## [1.1.0] - 2025-01-27

### Fixed
- 🐛 **Critical Fix**: Terminated state step sync now works correctly when app returns from killed state
  - Fixed issue where `syncStepsFromTerminated()` was never called from Dart side
  - Enhanced Kotlin sensor handling to wait for fresh sensor data when app resumes
  - Added sensor re-registration with 1.5-second wait loop to ensure data availability
  - Improved fallback to SharedPreferences when sensor doesn't respond immediately

### Added
- ✨ **New Feature**: `onTerminatedStepsDetected` callback for handling missed steps
  - Automatically triggered during `start()` when steps from terminated state are detected
  - Provides `(missedSteps, startTime, endTime)` parameters for easy Health Connect integration
  - Example: `stepCounter.onTerminatedStepsDetected = (steps, start, end) { ... }`
- 📚 **New Method**: `syncTerminatedSteps()` - Manual sync for terminated state steps
  - Returns `Map<String, dynamic>?` with missed steps data
  - Useful for on-demand synchronization scenarios
- 📖 **Documentation**: Added comprehensive `TERMINATED_STATE_USAGE.md` guide
  - Complete API documentation with examples
  - Health Connect integration patterns
  - Troubleshooting guide and best practices
  - Device reboot handling explanation

### Improved
- 🔍 **Enhanced Logging**: Added detailed debug logs to Kotlin plugin
  - `StepCounter` tag for sensor events and data retrieval
  - `AccurateStepCounter` tag for Dart-side sync operations
  - Helps diagnose issues when steps aren't syncing
- ⚡ **Better Sensor Handling**: Improved reliability when returning from terminated state
  - Re-registers sensor listener to trigger immediate callbacks
  - Implements retry logic with configurable wait time
  - Falls back gracefully to cached data if sensor unavailable
- 🎯 **Automatic Sync**: Terminated state sync now happens automatically on `start()`
  - No manual intervention required
  - Only triggers when `enableOsLevelSync: true` (default)
  - Validates data before returning results

### Changed
- 📦 **Internal**: Added `dart:developer` import for logging in `AccurateStepCounterImpl`
- 🔧 **Behavior**: `start()` method now includes terminated state sync in initialization flow
  - Maintains backward compatibility - no breaking changes
  - Existing code continues to work without modifications

### Technical Details
- **Sensor Wait Logic**: Kotlin plugin now waits up to 1500ms for sensor data with 50ms check intervals
- **Validation**: All existing validation checks remain in place (max steps, step rate, time checks)
- **Thread Safety**: Sensor wait loop properly handles interruptions
- **Fallback Chain**: Sensor → Wait for callback → SharedPreferences → null

### Migration Guide
No breaking changes! Existing implementations continue to work. To use the new callback feature:

```dart
// Before starting, register the callback
stepCounter.onTerminatedStepsDetected = (missedSteps, startTime, endTime) {
  // Handle missed steps (e.g., write to Health Connect)
  print('Synced $missedSteps steps from terminated state');
};

// Start as usual - sync happens automatically
await stepCounter.start();
```

### Performance Impact
- Minimal: Adds ~0-1.5 seconds to app startup only when terminated state data exists
- No impact during normal operation or when no missed steps are found
- Sensor wait timeout is configurable in Kotlin code if needed

### Testing
Verified fix with test scenario:
1. Start app → step counter active
2. Walk 100 steps → confirmed counted
3. Force kill app → terminate completely
4. Walk 50 steps while terminated
5. Reopen app → automatic sync triggers
6. ✅ Callback receives ~50 missed steps correctly

### Known Issues
- None identified in this release

---

## [1.0.0] - 2025-01-20

### Added
- ✨ Initial release of Accurate Step Counter plugin
- 📱 Accelerometer-based step detection with advanced filtering algorithms
- 🔧 Configurable sensitivity with preset modes (walking, running)
- 📊 Real-time step count event stream
- 🛡️ Comprehensive state management:
  - Foreground tracking with real-time updates
  - Background tracking support
  - Terminated state recovery (syncs steps taken while app was closed)
- 🔒 Validated step data with safety checks:
  - Maximum reasonable step count (50,000)
  - Maximum step rate validation (3 steps/second)
  - Device reboot detection
  - Time validation
- 📱 Android native integration:
  - OS-level step counter synchronization
  - SharedPreferences for state persistence
  - TYPE_STEP_COUNTER sensor support
- 📚 Complete documentation:
  - Comprehensive README with examples
  - API reference documentation
  - Integration tests
  - Example application
- 🎯 Core features:
  - Low-pass filtering to reduce noise
  - Peak detection algorithm
  - Minimum time between steps validation
  - Configurable threshold and filter parameters
  - Battery-efficient implementation

### Supported Platforms
- ✅ Android (Full support)
- 🚧 iOS (Planned for future release)

### Requirements
- Flutter SDK: >=3.3.0
- Dart SDK: ^3.9.0
- Android: API 19+ (Android 4.4 KitKat)

### Dependencies
- `sensors_plus`: ^6.0.1 - For accelerometer access
- `plugin_platform_interface`: ^2.0.2 - For plugin architecture

### Known Limitations
- iOS support not yet implemented
- Requires ACTIVITY_RECOGNITION permission on Android 10+
- Background tracking may be limited by device-specific battery optimization settings

### Breaking Changes
- None (initial release)

### Migration Guide
- None (initial release)

---

## Future Roadmap

### Planned for v1.2.0
- 📊 Step history tracking with daily/weekly summaries
- 🔔 Configurable step goal notifications
- 📈 Calorie estimation based on step count
- 🎨 Additional preset configurations (stairs, hiking, etc.)

### Planned for v2.0.0
- 🍎 iOS support with CoreMotion integration
- 🔄 Cloud sync capabilities
- 📊 Advanced analytics and insights
- 🏃 Activity type detection (walking, running, cycling)

---

## Contributing

Found a bug or have a feature request? Please [open an issue](https://github.com/rahulshahDEV/accurate_step_counter/issues).

Want to contribute? Check out our [contributing guidelines](CONTRIBUTING.md).

---

## Version History

- **1.2.0** (2025-12-30) - Foreground service support for Android ≤10
- **1.1.1** (2025-12-03) - Removed unnecessary health dependency, added logging
- **1.1.0** (2025-01-27) - Fixed terminated state sync + added callback feature
- **1.0.0** (2025-01-20) - Initial release with Android support
