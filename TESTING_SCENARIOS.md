# Accurate Step Counter - Real-Life Testing Scenarios

This document provides 7 comprehensive real-life scenarios to verify that step counting works correctly in **all app states**: foreground, background, and terminated.

## Prerequisites

Before running any scenarios, ensure:

1. ✅ Permissions granted:
   - `ACTIVITY_RECOGNITION` (required)
   - `POST_NOTIFICATIONS` (for Android 13+ with foreground service)
2. ✅ Battery optimization disabled for the app (Settings → Apps → Your App → Battery → Unrestricted)
3. ✅ Logging initialized: `await stepCounter.initializeLogging(debugLogging: true)`
4. ✅ App lifecycle observer configured to call `stepCounter.setAppState(state)`

## Quick Setup Verification

```dart
// Add this to verify setup before testing
Future<void> verifySetup() async {
  final stepCounter = AccurateStepCounter();

  // 1. Check permission
  final hasPermission = await stepCounter.hasActivityRecognitionPermission();
  print('✓ Permission granted: $hasPermission');

  // 2. Initialize logging
  await stepCounter.initializeLogging(debugLogging: true);
  print('✓ Logging initialized: ${stepCounter.isLoggingInitialized}');

  // 3. Start step counter
  await stepCounter.start();
  print('✓ Step counter started: ${stepCounter.isStarted}');

  // 4. Check native detector
  final isHardware = await stepCounter.isUsingNativeDetector();
  print('✓ Using hardware detector: $isHardware');

  // 5. Start logging
  await stepCounter.startLogging(config: StepRecordConfig.walking());
  print('✓ Logging enabled: ${stepCounter.isLoggingEnabled}');

  print('\n🎉 Setup complete! Ready for testing.\n');
}
```

---

## Scenario 1: Morning Walk (Foreground State)

**Goal**: Verify accurate step counting while app is in the foreground.

### Setup
```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initializeLogging(debugLogging: true);
await stepCounter.start();
await stepCounter.startLogging(config: StepRecordConfig.walking());

// Listen to real-time steps
stepCounter.stepEventStream.listen((event) {
  print('📱 Current steps: ${event.stepCount}');
});
```

### Test Steps
1. **Start the app** and keep it open on screen
2. **Walk normally** for 100 steps (count manually)
3. **Observe** real-time updates in the UI
4. **Stop** and check results

### Expected Results
- ✅ Real-time step updates in UI
- ✅ Accuracy: ±5% (95-105 steps for 100 actual steps)
- ✅ Warmup validation completes after ~5 seconds
- ✅ Source tracked as `StepRecordSource.foreground`

### Verification Commands
```dart
final total = await stepCounter.getTotalSteps();
final foregroundSteps = await stepCounter.getStepsBySource(StepRecordSource.foreground);
final logs = await stepCounter.getStepLogs();

print('Total steps: $total');
print('Foreground steps: $foregroundSteps');
print('Log entries: ${logs.length}');
```

### Console Output (Expected)
```
AccurateStepCounter: Logging database initialized
AccurateStepCounter: Warmup started
AccurateStepCounter: Warmup validated - 15 steps at 1.87/s
AccurateStepCounter: Logged 15 warmup steps (source: foreground)
AccurateStepCounter: Logged 25 steps (source: foreground)
```

---

## Scenario 2: Background Mode While Shopping

**Goal**: Verify step counting continues when app is in background.

### Setup
```dart
// In your State class
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final stepCounter = AccurateStepCounter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    stepCounter.setAppState(state);
    print('🔄 App state: $state');
  }
}
```

### Test Steps
1. **Start the app** with logging enabled
2. **Walk 50 steps** with app in foreground
3. **Press home button** (app goes to background)
4. **Walk another 50 steps** with app in background
5. **Return to app** and check results

### Expected Results
- ✅ Background steps counted (Android 11+: native detector continues)
- ✅ Background steps counted (Android ≤10: foreground service active)
- ✅ Notification shown on Android ≤10 only
- ✅ Source tracked as `StepRecordSource.background` for background steps
- ✅ Total: ~100 steps

### Verification Commands
```dart
final total = await stepCounter.getTotalSteps();
final fgSteps = await stepCounter.getStepsBySource(StepRecordSource.foreground);
final bgSteps = await stepCounter.getStepsBySource(StepRecordSource.background);

print('Foreground: $fgSteps, Background: $bgSteps, Total: $total');

// Should show: Foreground: ~50, Background: ~50, Total: ~100
```

### Android Version Differences

#### Android 11+ (API 30+)
- ❌ No notification shown
- ✅ Native `TYPE_STEP_DETECTOR` continues in background
- ✅ Steps auto-sync when app returns to foreground

#### Android ≤10 (API ≤29)
- ✅ Foreground service notification shown
- ✅ WakeLock keeps sensor active
- ✅ Continuous counting via service

---

## Scenario 3: App Terminated State Recovery

**Goal**: Verify missed steps are recovered after app termination (Android 11+ only).

### Setup
```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initializeLogging(debugLogging: true);

// Enable OS-level sync for terminated state
await stepCounter.start(
  config: StepDetectorConfig(
    enableOsLevelSync: true,  // Required for terminated sync
  ),
);

await stepCounter.startLogging(config: StepRecordConfig.walking());

// Handle terminated steps callback
stepCounter.onTerminatedStepsDetected = (missedSteps, startTime, endTime) {
  print('🔴 Recovered $missedSteps steps from terminated state');
  print('   Time range: $startTime to $endTime');
};
```

### Test Steps
1. **Start the app** with OS-level sync enabled
2. **Walk 30 steps** to establish baseline
3. **Force kill the app** (Settings → Apps → Force Stop)
4. **Walk 50 steps** while app is killed
5. **Relaunch the app**
6. **Check** if missed steps were synced

### Expected Results
- ✅ App syncs missed steps on launch
- ✅ `onTerminatedStepsDetected` callback fires with ~50 steps
- ✅ Steps logged with `StepRecordSource.terminated`
- ✅ Total steps = 30 (before) + 50 (missed) = ~80

### Verification Commands
```dart
final total = await stepCounter.getTotalSteps();
final terminatedSteps = await stepCounter.getStepsBySource(StepRecordSource.terminated);
final logs = await stepCounter.getStepLogs(source: StepRecordSource.terminated);

print('Total: $total');
print('Terminated steps: $terminatedSteps');
print('Terminated log entries: ${logs.length}');

for (final log in logs) {
  print('  ${log.stepCount} steps from ${log.fromTime} to ${log.toTime}');
}
```

### Console Output (Expected)
```
AccurateStepCounter: Checking for steps from terminated state...
AccurateStepCounter: Syncing 52 steps from terminated state
AccurateStepCounter: Time range: 2025-01-07 10:15:30 to 2025-01-07 10:18:45
🔴 Recovered 52 steps from terminated state
AccurateStepCounter: Logged 52 terminated steps
```

### Important Notes
- ⚠️ **Android ≤10**: Terminated state sync doesn't apply if foreground service is running (app never truly terminates)
- ⚠️ **Validation**: Terminated steps are validated (max 3 steps/second, max 50,000 steps)
- ⚠️ **Device Reboot**: If device reboots, OS step counter resets to 0 (sync won't work)

---

## Scenario 4: All-Day Tracking with Mixed States

**Goal**: Verify comprehensive tracking across foreground → background → terminated → foreground cycle.

### Setup
```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initializeLogging(debugLogging: true);
await stepCounter.start(config: StepDetectorConfig(enableOsLevelSync: true));
await stepCounter.startLogging(config: StepRecordConfig.walking());

// Track all state changes
stepCounter.onTerminatedStepsDetected = (steps, start, end) {
  print('📊 Terminated: $steps steps');
};
```

### Test Steps
1. **Morning (Foreground)**: Walk 100 steps with app open → Close app
2. **Afternoon (Terminated)**: Walk 200 steps with app killed → Open app
3. **Afternoon (Background)**: Walk 150 steps with app in background → Open app
4. **Evening (Foreground)**: Walk 50 steps with app open
5. **Check final stats**

### Expected Results
- ✅ Total: ~500 steps
- ✅ Foreground: ~150 steps
- ✅ Background: ~150 steps
- ✅ Terminated: ~200 steps
- ✅ All transitions handled smoothly

### Verification Commands
```dart
final stats = await stepCounter.getStepStats();

print('📊 All-Day Statistics:');
print('  Total Steps: ${stats['totalSteps']}');
print('  Foreground: ${stats['foregroundSteps']}');
print('  Background: ${stats['backgroundSteps']}');
print('  Terminated: ${stats['terminatedSteps']}');
print('  Entries: ${stats['entryCount']}');
print('  Avg per entry: ${stats['averagePerEntry']}');
print('  Daily avg: ${stats['averagePerDay']}');
```

### Expected Output
```
📊 All-Day Statistics:
  Total Steps: 502
  Foreground: 148
  Background: 153
  Terminated: 201
  Entries: 24
  Avg per entry: 20.9
  Daily avg: 502.0
```

---

## Scenario 5: Running/Jogging Workout

**Goal**: Verify accurate counting during high-intensity activity.

### Setup
```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initializeLogging(debugLogging: true);

// Use running preset for faster cadence
await stepCounter.start(config: StepDetectorConfig.running());
await stepCounter.startLogging(config: StepRecordConfig.running());

int currentSteps = 0;
stepCounter.stepEventStream.listen((event) {
  currentSteps = event.stepCount;
  print('🏃 Running: $currentSteps steps');
});
```

### Test Steps
1. **Start the app** with running config
2. **Run/jog** for 1 minute (expect ~150-180 steps at 2.5-3 steps/sec)
3. **Check accuracy** against manual count or treadmill
4. **Verify** warmup validation is faster (3 seconds for running preset)

### Expected Results
- ✅ Faster warmup (3s instead of 5s)
- ✅ Accepts higher step rate (up to 5 steps/second)
- ✅ Accuracy: ±7% (due to higher movement intensity)
- ✅ No false negatives during rapid steps

### Verification Commands
```dart
final total = await stepCounter.getTotalSteps();
final logs = await stepCounter.getStepLogs();

// Calculate actual step rate
if (logs.isNotEmpty) {
  final duration = logs.last.toTime.difference(logs.first.fromTime);
  final rate = total / duration.inSeconds;
  print('Average step rate: ${rate.toStringAsFixed(2)} steps/sec');
  // Should be 2.5-3.0 for running
}
```

### Running Config Details
```dart
// What running preset uses:
StepRecordConfig.running() = StepRecordConfig(
  recordIntervalMs: 3000,        // Log every 3 seconds
  warmupDurationMs: 3000,        // Only 3s warmup
  minStepsToValidate: 10,        // 10 steps in 3s = 3.3/s
  maxStepsPerSecond: 5.0,        // Accept up to 5 steps/sec
);
```

---

## Scenario 6: Device Reboot Scenario

**Goal**: Understand behavior after device reboot (OS step counter resets).

### Important Context
- Android's `TYPE_STEP_COUNTER` sensor **resets to 0** on device reboot
- This is OS-level behavior, not a plugin limitation
- Plugin handles this gracefully to prevent incorrect sync

### Setup
```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initializeLogging(debugLogging: true);
await stepCounter.start(config: StepDetectorConfig(enableOsLevelSync: true));
await stepCounter.startLogging(config: StepRecordConfig.walking());

// This will NOT fire after reboot (by design)
stepCounter.onTerminatedStepsDetected = (steps, start, end) {
  print('Terminated steps: $steps');
};
```

### Test Steps
1. **Start the app** and walk 100 steps
2. **Close the app** (check saved state in SharedPreferences)
3. **Reboot the device** (power off → power on)
4. **Walk 50 steps** before opening app
5. **Open the app**

### Expected Results
- ✅ No terminated state sync (OS counter reset detected)
- ✅ No crash or error
- ✅ Plugin saves new baseline and continues counting from 0
- ✅ Pre-reboot steps remain in database (not lost)

### Verification Commands
```dart
// After reboot, check database still has pre-reboot data
final total = await stepCounter.getTotalSteps();
print('Total steps in DB: $total'); // Should still show ~100 from before reboot

// Current session will start fresh
final currentCount = stepCounter.currentStepCount;
print('Current session: $currentCount'); // Will be ~50 (new steps)
```

### Console Output (Expected)
```
AccurateStepCounter: Checking for steps from terminated state...
AccurateStepCounter: No steps to sync from terminated state
// Plugin detected sensor reset (lastCount > currentCount) and handled gracefully
```

### Key Learnings
- 🔄 OS step counter resets on reboot (Android OS behavior)
- 💾 Database preserves historical data
- 🛡️ Plugin validates sync to prevent negative/invalid step counts
- ✅ Continues working normally after reboot

---

## Scenario 7: Permission Handling & Edge Cases

**Goal**: Verify proper handling of permission issues and edge cases.

### Test 7.1: Permission Denied

#### Setup
```dart
final stepCounter = AccurateStepCounter();

// Check permission first
final hasPermission = await stepCounter.hasActivityRecognitionPermission();
print('Permission granted: $hasPermission');

if (!hasPermission) {
  // Request permission using permission_handler
  await Permission.activityRecognition.request();
}
```

#### Test Steps
1. **Deny** ACTIVITY_RECOGNITION permission
2. **Try to start** step counter
3. **Verify** graceful handling

#### Expected Results
- ✅ No crash
- ✅ Steps may not count on Android 10+ without permission
- ✅ App prompts user to grant permission

---

### Test 7.2: No Step Sensor Available

#### Scenario
Some Android devices (rare) don't have `TYPE_STEP_DETECTOR` or `TYPE_ACCELEROMETER`.

#### Expected Results
- ✅ Plugin falls back gracefully
- ✅ Returns `isUsingNativeDetector() = false`
- ✅ No crash, but step counting won't work

#### Verification
```dart
final hasDetector = await stepCounter.isUsingNativeDetector();
if (!hasDetector) {
  print('⚠️ This device does not support step detection');
  // Show message to user
}
```

---

### Test 7.3: Battery Optimization Kills App

#### Scenario
Android's battery optimization can kill background processes.

#### Test Steps
1. **Enable** battery optimization for the app
2. **Put app in background**
3. **Wait 5-10 minutes**
4. **Walk steps** while app is killed by OS
5. **Open app**

#### Expected Results (Android 11+)
- ✅ Terminated state sync recovers missed steps
- ✅ `onTerminatedStepsDetected` callback fires

#### Expected Results (Android ≤10)
- ⚠️ Foreground service may be killed by aggressive battery optimization
- 💡 Solution: Prompt user to disable battery optimization

#### Battery Optimization Check
```dart
// Use battery_plus or similar package
// Prompt user to add app to battery optimization whitelist
```

---

## Automated Testing Checklist

Use this checklist to verify all scenarios:

```
[ ] Scenario 1: Foreground counting (100 steps, ±5% accuracy)
[ ] Scenario 2: Background counting (50 + 50 steps, proper source tracking)
[ ] Scenario 3: Terminated sync (50 missed steps recovered)
[ ] Scenario 4: Mixed states (500 total across all sources)
[ ] Scenario 5: Running mode (150-180 steps/min, higher cadence)
[ ] Scenario 6: Device reboot (graceful handling, no crash)
[ ] Scenario 7.1: Permission denied (graceful handling)
[ ] Scenario 7.2: No sensor (fallback behavior)
[ ] Scenario 7.3: Battery optimization (foreground service or sync)

Additional Checks:
[ ] Logging database initialized successfully
[ ] Real-time streams emit events
[ ] App lifecycle observer configured
[ ] Warmup validation works correctly
[ ] Stats API returns correct aggregates
[ ] Notification shows on Android ≤10 only
[ ] OS-level sync enabled for terminated state
[ ] No memory leaks (dispose() called properly)
```

---

## Debug Commands

### View Logs in ADB
```bash
# All plugin logs
adb logcat -s AccurateStepCounter NativeStepDetector StepSync StepForegroundService

# Only step events
adb logcat -s NativeStepDetector

# Only terminated state sync
adb logcat -s StepSync

# Clear logs first
adb logcat -c && adb logcat -s AccurateStepCounter
```

### Check SharedPreferences
```bash
adb shell
run-as com.example.your_app
cat /data/data/com.example.your_app/shared_prefs/accurate_step_counter_prefs.xml
```

### Verify Hive Database
```dart
final logs = await stepCounter.getStepLogs();
print('Database has ${logs.length} entries');

for (final log in logs) {
  print('${log.stepCount} steps - ${log.source} - ${log.toTime}');
}
```

---

## Troubleshooting Guide

| Issue | Check | Solution |
|-------|-------|----------|
| Steps not counting in foreground | Permission granted? | Request ACTIVITY_RECOGNITION |
| Steps not counting in background (Android 11+) | Is detector hardware-based? | Check `isUsingNativeDetector()` |
| Steps not counting in background (Android ≤10) | Is foreground service running? | Check notification is visible |
| No terminated state sync | Is OS-level sync enabled? | Set `enableOsLevelSync: true` |
| Notification not showing | Android version? | Only shows on API ≤29 by default |
| Inaccurate counts | Wrong config for activity? | Use appropriate preset (walking/running) |
| App killed in background | Battery optimization? | Disable for this app |
| Warmup taking too long | Wrong preset? | Use `sensitive()` or adjust warmup time |
| Database empty | Logging initialized? | Call `initializeLogging()` first |
| No real-time updates | Stream subscribed? | Listen to `stepEventStream` |

---

## Final Validation Test

Run this comprehensive test to validate everything:

```dart
Future<void> runComprehensiveTest() async {
  print('🧪 Starting Comprehensive Test...\n');

  final stepCounter = AccurateStepCounter();

  // 1. Setup
  print('1️⃣ Initializing...');
  await stepCounter.initializeLogging(debugLogging: true);
  await stepCounter.start(config: StepDetectorConfig(enableOsLevelSync: true));
  await stepCounter.startLogging(config: StepRecordConfig.walking());

  // 2. Verify setup
  print('2️⃣ Verifying setup...');
  assert(stepCounter.isLoggingInitialized, 'Logging not initialized');
  assert(stepCounter.isStarted, 'Counter not started');
  assert(stepCounter.isLoggingEnabled, 'Logging not enabled');
  print('   ✅ Setup complete\n');

  // 3. Wait for steps
  print('3️⃣ Walk 20 steps and wait...');
  await Future.delayed(Duration(seconds: 30));

  // 4. Check results
  print('4️⃣ Checking results...');
  final total = await stepCounter.getTotalSteps();
  final fgSteps = await stepCounter.getStepsBySource(StepRecordSource.foreground);
  final stats = await stepCounter.getStepStats();

  print('   Total steps: $total');
  print('   Foreground: $fgSteps');
  print('   Entries: ${stats['entryCount']}');

  assert(total > 0, 'No steps recorded!');
  print('   ✅ Steps recorded successfully\n');

  // 5. Test terminated callback
  print('5️⃣ Testing terminated callback...');
  bool callbackFired = false;
  stepCounter.onTerminatedStepsDetected = (steps, start, end) {
    callbackFired = true;
    print('   ✅ Callback fired: $steps steps');
  };

  // 6. Cleanup
  print('6️⃣ Cleaning up...');
  await stepCounter.stop();
  await stepCounter.dispose();
  print('   ✅ Cleanup complete\n');

  print('🎉 Comprehensive Test Complete!\n');
}
```

---

## Scenario 8: Samsung Device Fix Verification

**Goal**: Verify the TYPE_STEP_DETECTOR priority fix works on Samsung devices.

### Background
Samsung devices sometimes don't report steps via `TYPE_STEP_COUNTER` sensor properly. The fix prioritizes `TYPE_STEP_DETECTOR` (NativeStepDetector) over the foreground service counter.

### Setup
```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initializeLogging(debugLogging: true);
await stepCounter.start();
await stepCounter.startLogging(config: StepRecordConfig.walking());
```

### Test Steps
1. **Run on Samsung device** (Android 10+)
2. **Start the app** and walk 50 steps
3. **Monitor ADB logs** for step source

### Verification Commands
```bash
# Watch logs for the Samsung fix
adb logcat -c && adb logcat -s AccurateStepCounter | grep -E "getForegroundStepCount|native:|service:"
```

### Expected Log Output
```
Foreground step count: 50 (native: 50, service: 0)
```

This confirms NativeStepDetector (TYPE_STEP_DETECTOR) is providing the count, not the foreground service (TYPE_STEP_COUNTER).

### Success Criteria
- ✅ `native:` count matches actual steps walked
- ✅ `service:` count may be 0 on Samsung devices (expected)
- ✅ Total step count is accurate

---

## Scenario 9: Duplicate Prevention Test

**Goal**: Verify no duplicate step counts across state transitions.

### Setup
```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initializeLogging(debugLogging: true);
await stepCounter.start(config: StepDetectorConfig(enableOsLevelSync: true));
await stepCounter.startLogging(config: StepRecordConfig.aggregated());
```

### Test Steps
1. **Phase 1 (Foreground)**: Walk 30 steps with app open, note the count
2. **Phase 2 (Background)**: Press home, walk 30 more steps, return to app
3. **Phase 3 (Terminated)**: Force kill app, walk 30 more steps, reopen app
4. **Verify**: Total should be ~90 steps (not 120+ due to duplicates)

### Verification Commands
```dart
final stats = await stepCounter.getStepStats();
print('Total: ${stats['totalSteps']}');
print('Foreground: ${stats['foregroundSteps']}');
print('Background: ${stats['backgroundSteps']}');
print('Terminated: ${stats['terminatedSteps']}');

// Each phase should have ~30 steps, total ~90
// If you see 120+, there's a duplicate counting issue
```

### Expected Results
- ✅ Foreground steps: ~30
- ✅ Background steps: ~30
- ✅ Terminated steps: ~30
- ✅ Total: ~90 (sum of all three)
- ❌ If total > 100: Possible duplicate counting

---

## Scenario 10: Cross-Android Version Validation

**Goal**: Verify correct behavior on both Android ≤10 and Android 11+.

### Android ≤10 (API ≤29) Testing

#### Expected Behavior
- ✅ Foreground service notification appears when app goes to background
- ✅ WakeLock keeps sensor active
- ✅ Steps counted continuously via foreground service

#### Test Steps
1. Start app, enable step counter
2. Press home button (app goes to background)
3. **Verify**: Notification appears in status bar
4. Walk 50 steps
5. Return to app
6. **Verify**: Steps are counted

```bash
# Check foreground service
adb shell dumpsys activity services | grep StepCounterForegroundService
```

### Android 11+ (API ≥30) Testing

#### Expected Behavior
- ❌ No foreground service notification
- ✅ Native TYPE_STEP_DETECTOR continues in background
- ✅ Terminated state sync works when app is killed

#### Test Steps
1. Start app, enable step counter
2. Press home button (app goes to background)
3. **Verify**: NO notification appears
4. Walk 50 steps
5. **Force kill app**: `adb shell am force-stop <package>`
6. Walk 30 more steps
7. Reopen app
8. **Verify**: ~80 total steps (50 background + 30 terminated sync)

### Quick Check Script
```bash
# Get Android version
API=$(adb shell getprop ro.build.version.sdk)
echo "API Level: $API"

if [ "$API" -le 29 ]; then
  echo "Testing Android ≤10 behavior (foreground service)"
else
  echo "Testing Android 11+ behavior (native detector + OS sync)"
fi
```

---

## Success Criteria

The package is considered **fully functional** if:

1. ✅ **Foreground counting**: Accurate within ±5% for walking
2. ✅ **Background counting**: Continues on both Android 11+ and Android ≤10
3. ✅ **Terminated state**: Syncs missed steps on Android 11+ after app kill
4. ✅ **Source tracking**: Correctly identifies foreground/background/terminated
5. ✅ **Warmup validation**: Prevents false positives during initial movement
6. ✅ **Database logging**: Persists all step records with correct timestamps
7. ✅ **Real-time streams**: Emit events for UI updates
8. ✅ **Permission handling**: Gracefully handles denied permissions
9. ✅ **Device reboot**: Handles sensor reset without crashing
10. ✅ **No crashes**: All scenarios complete without errors
11. ✅ **Samsung devices**: TYPE_STEP_DETECTOR priority works correctly
12. ✅ **No duplicates**: State transitions don't cause double-counting

---

**Ready to test?** Start with Scenario 1 and work through each one. Good luck! 🚀

