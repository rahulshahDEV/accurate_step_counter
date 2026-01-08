# Comprehensive Test Scenarios for accurate_step_counter v1.5.0

This document provides 6 comprehensive test scenarios to verify the `accurate_step_counter` package is working correctly after recent changes, including:

- **New Feature**: Inactivity timeout functionality
- **New Feature**: External source import (`writeStepsToAggregated`)
- **Updated Config**: Aggregated mode with no warmup by default
- **Fixed**: Stream initialization with initial values
- **Fixed**: Proper step persistence after restart

---

## Prerequisites

Before testing, ensure:

1. **Permissions granted**:
   ```bash
   adb shell pm grant your.package.name android.permission.ACTIVITY_RECOGNITION
   adb shell pm grant your.package.name android.permission.POST_NOTIFICATIONS
   ```

2. **Battery optimization disabled**:
   - Settings → Apps → Your App → Battery → Unrestricted

3. **Device ready**:
   - Real Android device (emulator may not have step detector)
   - Android 6.0+ (API 23+)

4. **Debug logging enabled** (for verification):
   ```bash
   adb logcat -s AccurateStepCounter StepCounter StepSync
   ```

---

## Test Scenario 1: Inactivity Timeout Functionality

**Goal**: Verify that the step counter properly handles inactivity timeouts and resets warmup state when the user stops walking for a configured period.

### Configuration

```dart
final stepCounter = AccurateStepCounter();

// Use custom config with inactivity timeout
await stepCounter.initializeLogging(debugLogging: true);
await stepCounter.start(config: StepDetectorConfig.walking());
await stepCounter.startLogging(
  config: StepRecordConfig.walking().copyWith(
    inactivityTimeoutMs: 10000, // 10 seconds
    warmupDurationMs: 5000,      // 5 seconds warmup
  ),
);
```

### Test Procedure

1. **Start app** and initialize step counter with config above
2. **Walk continuously** for 50 steps (should pass warmup)
3. **Stop completely** and wait 15 seconds (exceeds timeout)
4. **Check logs** - should see "Inactivity timeout triggered"
5. **Walk again** for 30 steps
6. **Verify** new warmup session started

### Expected Results

- ✅ First walking session: Warmup completes after ~5s, steps logged
- ✅ After 10s inactivity: "Inactivity timeout triggered - ending current session"
- ✅ Second walking session: New warmup starts from scratch
- ✅ Steps from both sessions correctly logged with separate entries
- ✅ No phantom steps logged during idle period

### Verification Code

```dart
// Check logs to see session boundaries
final logs = await stepCounter.getStepLogs();
print('Total log entries: ${logs.length}');

for (final log in logs) {
  print('${log.stepCount} steps | ${log.fromTime} → ${log.toTime} | ${log.source}');
}
```

### Expected Console Output

```
AccurateStepCounter: Warmup started
AccurateStepCounter: Warmup validated - 8 steps at 1.60/s
AccurateStepCounter: Logged 8 warmup steps (source: foreground)
AccurateStepCounter: Logged 42 steps (source: foreground)
AccurateStepCounter: Inactivity timeout triggered - ending current session
AccurateStepCounter: Warmup state reset - new session will require validation
AccurateStepCounter: Warmup started
AccurateStepCounter: Warmup validated - 9 steps at 1.80/s
AccurateStepCounter: Logged 9 warmup steps (source: foreground)
AccurateStepCounter: Logged 21 steps (source: foreground)
```

### Pass/Fail Criteria

| Criterion | Pass | Fail |
|-----------|------|------|
| Inactivity timeout triggers after configured time | ✅ | ❌ |
| Warmup resets after timeout | ✅ | ❌ |
| New session requires new warmup validation | ✅ | ❌ |
| No steps logged during idle period | ✅ | ❌ |
| Both sessions have separate log entries | ✅ | ❌ |

### How to Verify

1. **Timeline check**: Verify time gaps in logs match timeout
2. **Step accuracy**: Count manual steps vs logged steps
3. **Session separation**: Confirm distinct log entries for each walking session
4. **Warmup reset**: Second session should show warmup logs again

---

## Test Scenario 2: External Source Import

**Goal**: Verify that steps can be imported from external sources (Google Fit, Apple Health, wearables) and correctly update the aggregated count.

### Configuration

```dart
final stepCounter = AccurateStepCounter();

// Initialize with aggregated mode
await stepCounter.initSteps(); // Uses aggregated mode by default

// Watch aggregated count
stepCounter.watchAggregatedStepCounter().listen((totalSteps) {
  print('Total steps: $totalSteps');
});
```

### Test Procedure

1. **Start app** with aggregated mode
2. **Note initial step count** (e.g., 0 steps)
3. **Walk 20 steps** manually
4. **Verify count increases** to ~20
5. **Import external steps**:
   ```dart
   await stepCounter.writeStepsToAggregated(
     stepCount: 500,
     fromTime: DateTime.now().subtract(Duration(hours: 2)),
     toTime: DateTime.now().subtract(Duration(hours: 1)),
     source: StepRecordSource.external,
   );
   ```
6. **Verify stream emits** updated count (~520)
7. **Walk 10 more steps**
8. **Verify count** now shows ~530

### Expected Results

- ✅ Stream emits immediately after `writeStepsToAggregated` call
- ✅ Aggregated count = previous + imported + new live steps
- ✅ External steps stored with `StepRecordSource.external`
- ✅ No double-counting of steps
- ✅ Multiple imports can be done without conflicts

### Verification Code

```dart
// Check total by source
final total = await stepCounter.getTodayStepCount();
final external = await stepCounter.getStepsBySource(StepRecordSource.external);
final foreground = await stepCounter.getStepsBySource(StepRecordSource.foreground);

print('Total steps: $total');
print('External: $external');
print('Foreground: $foreground');
print('Expected: ${external + foreground}');

// Get logs to verify entries
final logs = await stepCounter.getStepLogs();
final externalLogs = logs.where((l) => l.source == StepRecordSource.external).toList();
print('External log entries: ${externalLogs.length}');
```

### Expected Console Output

```
AccurateStepCounter: Initialized aggregated mode: 0 steps from today
Total steps: 20
AccurateStepCounter: Manually wrote 500 steps to aggregated database
AccurateStepCounter: Aggregated count updated to 520
Total steps: 520
Total steps: 530
```

### Pass/Fail Criteria

| Criterion | Pass | Fail |
|-----------|------|------|
| `writeStepsToAggregated` completes without error | ✅ | ❌ |
| Stream emits updated count immediately | ✅ | ❌ |
| External steps tracked separately by source | ✅ | ❌ |
| Total = external + live steps (no double-counting) | ✅ | ❌ |
| Multiple imports work correctly | ✅ | ❌ |

### How to Verify

1. **Database check**: Query by source to confirm external entries
2. **Math verification**: Total should equal sum of all sources
3. **Stream behavior**: Should emit within 100ms of write
4. **Edge case**: Import 0 steps - should throw error
5. **Edge case**: Import with future time - should throw error

---

## Test Scenario 3: Aggregated Mode with No Warmup

**Goal**: Verify that the new default aggregated mode (no warmup) starts counting immediately without validation delays.

### Configuration

```dart
final stepCounter = AccurateStepCounter();

// New simplified API with defaults
await stepCounter.initSteps(); // This uses aggregated mode with no warmup by default
```

### Test Procedure

1. **Fresh install** or clear all data:
   ```dart
   await stepCounter.clearStepLogs();
   stepCounter.reset();
   ```
2. **Initialize** using `initSteps()`
3. **Take 1 step immediately** (within 1 second)
4. **Verify** step is logged (no warmup delay)
5. **Walk 10 more steps** continuously
6. **Check database** - all 11 steps should be logged

### Expected Results

- ✅ **No warmup validation** - immediate step logging
- ✅ First step logged within 1 second of walking
- ✅ `warmupDurationMs = 0` in config
- ✅ No "Warmup started" messages in logs
- ✅ Steps written on every step event (continuous logging)

### Verification Code

```dart
// Wait 2 seconds after first step
await Future.delayed(Duration(seconds: 2));

final logs = await stepCounter.getStepLogs();
print('Log entries after 1 step: ${logs.length}'); // Should be 1

// Walk 10 more steps
// ... wait ...

final logs2 = await stepCounter.getStepLogs();
print('Log entries after 11 steps: ${logs2.length}'); // Should be 11 or fewer (batched)
```

### Expected Console Output

```
AccurateStepCounter: Initialized aggregated mode: 0 steps from today
AccurateStepCounter: Aggregated step logging started - loaded 0 steps from today
AccurateStepCounter: Logged 1 steps (source: foreground)
AGGREGATED: 1 steps
AccurateStepCounter: Logged 1 steps (source: foreground)
AGGREGATED: 2 steps
... (continues for each step)
```

### Pass/Fail Criteria

| Criterion | Pass | Fail |
|-----------|------|------|
| No warmup delay - immediate logging | ✅ | ❌ |
| First step logged within 1-2 seconds | ✅ | ❌ |
| No "Warmup started" in logs | ✅ | ❌ |
| Every step event creates a log entry | ✅ | ❌ |
| `StepRecordConfig.aggregated()` has `warmupDurationMs = 0` | ✅ | ❌ |

### How to Verify

1. **Timing check**: Measure time from first step to first log entry
2. **Config inspection**: Check `StepRecordConfig.aggregated()` values
3. **Log pattern**: Should not see warmup validation messages
4. **Continuous logging**: Each step should create an entry (not batched by interval)

---

## Test Scenario 4: Stream Initialization and Data Flow

**Goal**: Verify that `watchAggregatedStepCounter()` emits an initial value immediately upon subscription, and that late subscribers also receive the current value.

### Configuration

```dart
final stepCounter = AccurateStepCounter();

await stepCounter.initSteps();
```

### Test Procedure

#### Part A: Initial Subscription
1. **Start app** and initialize
2. **Subscribe to stream BEFORE any steps**:
   ```dart
   int? firstEmission;
   final sub1 = stepCounter.watchAggregatedStepCounter().listen((steps) {
     if (firstEmission == null) {
       firstEmission = steps;
       print('First emission: $steps');
     }
   });
   ```
3. **Wait 1 second** without walking
4. **Verify** `firstEmission` is not null (should be 0 or stored value)

#### Part B: Late Subscription
1. **Walk 50 steps**
2. **Subscribe to stream AFTER steps are counted**:
   ```dart
   int? lateFirstEmission;
   final sub2 = stepCounter.watchAggregatedStepCounter().listen((steps) {
     if (lateFirstEmission == null) {
       lateFirstEmission = steps;
       print('Late subscriber first emission: $steps');
     }
   });
   ```
3. **Wait 1 second**
4. **Verify** `lateFirstEmission` is ~50 (not null)

#### Part C: App Restart with Stored Steps
1. **Walk 100 steps** (total now ~150)
2. **Kill the app** completely
3. **Reopen app** and initialize
4. **Subscribe immediately**:
   ```dart
   int? restartEmission;
   final sub3 = stepCounter.watchAggregatedStepCounter().listen((steps) {
     if (restartEmission == null) {
       restartEmission = steps;
       print('After restart first emission: $steps');
     }
   });
   ```
5. **Verify** `restartEmission` is ~150 (stored steps loaded)

### Expected Results

- ✅ **Immediate emission**: Stream emits within 100ms of subscription
- ✅ **Initial value**: First emission matches current aggregated count
- ✅ **Late subscribers**: Get current value immediately (not stale)
- ✅ **After restart**: Stored steps emitted as initial value
- ✅ **No null emissions**: Stream never emits null

### Verification Code

```dart
// Test immediate emission timing
final stopwatch = Stopwatch()..start();
int? firstValue;

stepCounter.watchAggregatedStepCounter().listen((steps) {
  if (firstValue == null) {
    firstValue = steps;
    stopwatch.stop();
    print('First emission after ${stopwatch.elapsedMilliseconds}ms: $steps');
  }
});

await Future.delayed(Duration(milliseconds: 200));
assert(firstValue != null, 'Stream should emit within 200ms');
```

### Expected Console Output

```
AccurateStepCounter: Initialized aggregated mode: 0 steps from today
First emission after 5ms: 0
AccurateStepCounter: Logged 1 steps (source: foreground)
AGGREGATED: 1 steps
... (walk 50 steps) ...
Late subscriber first emission: 50
... (walk 100 more, kill app, restart) ...
AccurateStepCounter: Initialized aggregated mode: 150 steps from today
After restart first emission: 150
```

### Pass/Fail Criteria

| Criterion | Pass | Fail |
|-----------|------|------|
| Initial subscription emits within 100ms | ✅ | ❌ |
| Late subscriber gets current value immediately | ✅ | ❌ |
| After restart, stored value emitted first | ✅ | ❌ |
| No null or missing initial emissions | ✅ | ❌ |
| Stream continues to emit on new steps | ✅ | ❌ |

### How to Verify

1. **Timing measurement**: Use `Stopwatch` to verify emission speed
2. **Late subscriber test**: Subscribe after steps are counted
3. **Restart test**: Kill and reopen app, verify persistence
4. **Multiple subscribers**: Both should get same initial value

---

## Test Scenario 5: Error Handling and Recovery

**Goal**: Verify that the step counter handles errors gracefully and recovers properly from various failure conditions.

### Configuration

```dart
final stepCounter = AccurateStepCounter();
```

### Test Procedure

#### Part A: Invalid External Source Import
1. **Initialize**: `await stepCounter.initSteps()`
2. **Try to import negative steps**:
   ```dart
   try {
     await stepCounter.writeStepsToAggregated(
       stepCount: -10,
       fromTime: DateTime.now().subtract(Duration(hours: 1)),
       toTime: DateTime.now(),
     );
     print('ERROR: Should have thrown ArgumentError');
   } catch (e) {
     print('✓ Correctly rejected negative steps: $e');
   }
   ```
3. **Verify** exception thrown and count unchanged

#### Part B: Invalid Time Range
1. **Try to import with future time**:
   ```dart
   try {
     await stepCounter.writeStepsToAggregated(
       stepCount: 100,
       fromTime: DateTime.now(),
       toTime: DateTime.now().subtract(Duration(hours: 1)), // toTime before fromTime
     );
     print('ERROR: Should have thrown ArgumentError');
   } catch (e) {
     print('✓ Correctly rejected invalid time range: $e');
   }
   ```

#### Part C: Call Before Initialization
1. **Create new instance** (don't initialize)
2. **Try to call methods**:
   ```dart
   final newCounter = AccurateStepCounter();
   try {
     await newCounter.getTodayStepCount();
     print('ERROR: Should have thrown StateError');
   } catch (e) {
     print('✓ Correctly rejected call before init: $e');
   }
   ```

#### Part D: Permission Denied Recovery
1. **Revoke permission**: `adb shell pm revoke your.package.name android.permission.ACTIVITY_RECOGNITION`
2. **Try to start**: `await stepCounter.start()`
3. **Check permission**: `final hasPermission = await stepCounter.hasActivityRecognitionPermission()`
4. **Verify** graceful handling (no crash)
5. **Re-grant permission** and retry

#### Part E: Database Recovery
1. **Corrupt database** (delete Hive box file while app running)
2. **Try to write steps**
3. **Verify** app doesn't crash
4. **Reinitialize** logging
5. **Verify** recovery

### Expected Results

- ✅ **Invalid inputs rejected**: ArgumentError for negative steps, invalid times
- ✅ **State validation**: StateError when called before initialization
- ✅ **Permission handling**: Graceful failure when permission denied
- ✅ **No crashes**: All error conditions handled without app crash
- ✅ **Clear error messages**: User-friendly error descriptions

### Verification Code

```dart
// Test error handling comprehensively
Future<void> testErrorHandling() async {
  final counter = AccurateStepCounter();
  int errorsHandled = 0;
  
  // Test 1: Negative steps
  try {
    await counter.initSteps();
    await counter.writeStepsToAggregated(
      stepCount: -1,
      fromTime: DateTime.now(),
      toTime: DateTime.now(),
    );
  } catch (e) {
    errorsHandled++;
    print('✓ Test 1: Negative steps rejected');
  }
  
  // Test 2: Invalid time range
  try {
    await counter.writeStepsToAggregated(
      stepCount: 100,
      fromTime: DateTime.now(),
      toTime: DateTime.now().subtract(Duration(hours: 1)),
    );
  } catch (e) {
    errorsHandled++;
    print('✓ Test 2: Invalid time range rejected');
  }
  
  // Test 3: Not initialized
  try {
    final newCounter = AccurateStepCounter();
    await newCounter.getTodayStepCount();
  } catch (e) {
    errorsHandled++;
    print('✓ Test 3: Not initialized error');
  }
  
  print('Errors handled: $errorsHandled/3');
}
```

### Expected Console Output

```
✓ Correctly rejected negative steps: ArgumentError: Step count must be positive
✓ Correctly rejected invalid time range: ArgumentError: toTime must be after fromTime
✓ Correctly rejected call before init: StateError: Logging not initialized. Call initializeLogging() first.
```

### Pass/Fail Criteria

| Criterion | Pass | Fail |
|-----------|------|------|
| Negative steps rejected with ArgumentError | ✅ | ❌ |
| Invalid time range rejected with ArgumentError | ✅ | ❌ |
| Calls before init rejected with StateError | ✅ | ❌ |
| No app crashes on any error | ✅ | ❌ |
| Error messages are clear and actionable | ✅ | ❌ |

### How to Verify

1. **Exception types**: Verify correct exception classes thrown
2. **State preservation**: Ensure errors don't corrupt internal state
3. **Recovery**: After error, app should continue working normally
4. **Edge cases**: Test boundary conditions (0 steps, same fromTime/toTime)

---

## Test Scenario 6: Lifecycle Management

**Goal**: Verify that the step counter properly manages its lifecycle across app state changes, restarts, and disposal.

### Configuration

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final stepCounter = AccurateStepCounter();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    stepCounter.setAppState(state); // Important!
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stepCounter.dispose();
    super.dispose();
  }
}
```

### Test Procedure

#### Part A: Foreground → Background → Foreground
1. **Start app** and walk 20 steps (foreground)
2. **Minimize app** (press home button)
3. **Walk 30 steps** with phone in pocket (background)
4. **Wait 10 seconds**
5. **Reopen app** (foreground)
6. **Verify** proper source tracking:
   - First 20 steps: `StepRecordSource.foreground`
   - Next 30 steps: `StepRecordSource.background`

#### Part B: App Termination → Restart with Data
1. **Walk 50 steps** (aggregated count: 100)
2. **Force kill app**: swipe away from recent apps
3. **Wait 5 seconds**
4. **Reopen app**
5. **Verify** aggregated count still shows 100

#### Part C: Terminated State Sync (Android 11+)
1. **Start app**, walk 20 steps
2. **Force kill app**
3. **Walk 50 steps while app is closed**
4. **Reopen app**
5. **Check for sync callback**:
   ```dart
   stepCounter.onTerminatedStepsDetected = (steps, from, to) {
     print('Synced $steps missed steps from terminated state!');
   };
   ```
6. **Verify** ~50 steps synced and added

#### Part D: Multiple Dispose/Init Cycles
1. **Initialize**: `await stepCounter.initSteps()`
2. **Walk 10 steps**
3. **Dispose**: `await stepCounter.dispose()`
4. **Re-initialize**: `await stepCounter.initSteps()`
5. **Walk 10 more steps**
6. **Verify** no memory leaks, no crashes

#### Part E: Rapid State Changes
1. **Start app** in foreground
2. **Quickly cycle** through states:
   - Minimize → Reopen → Minimize → Reopen (5 times quickly)
3. **Walk 20 steps** during cycling
4. **Verify** all steps logged correctly without duplicates

### Expected Results

- ✅ **Source tracking**: Correct source (foreground/background) for each state
- ✅ **Data persistence**: Aggregated count preserved across restarts
- ✅ **Terminated sync**: Missed steps recovered on Android 11+ (optional)
- ✅ **No memory leaks**: Multiple init/dispose cycles work correctly
- ✅ **Rapid state changes**: No crashes or data loss
- ✅ **Proper cleanup**: No zombie listeners after dispose

### Verification Code

```dart
// Check source breakdown
final fg = await stepCounter.getStepsBySource(StepRecordSource.foreground);
final bg = await stepCounter.getStepsBySource(StepRecordSource.background);
final term = await stepCounter.getStepsBySource(StepRecordSource.terminated);

print('Foreground: $fg');
print('Background: $bg');
print('Terminated: $term');

// Check logs for proper state transitions
final logs = await stepCounter.getStepLogs();
for (final log in logs) {
  print('${log.source}: ${log.stepCount} steps at ${log.fromTime}');
}
```

### Expected Console Output

```
AccurateStepCounter: App state changed to resumed
AccurateStepCounter: Logged 20 steps (source: foreground)
AccurateStepCounter: App state changed to paused
AccurateStepCounter: Logged steps before background
AccurateStepCounter: App state changed to inactive
AccurateStepCounter: Logged 30 steps (source: background)
AccurateStepCounter: App state changed to resumed
AccurateStepCounter: Checking for steps from terminated state...
AccurateStepCounter: Syncing 50 steps from terminated state
```

### Pass/Fail Criteria

| Criterion | Pass | Fail |
|-----------|------|------|
| Foreground steps tracked correctly | ✅ | ❌ |
| Background steps tracked correctly | ✅ | ❌ |
| Aggregated count persists across restarts | ✅ | ❌ |
| Terminated state sync works (Android 11+) | ✅ | ⚠️ Optional |
| Multiple dispose/init cycles work | ✅ | ❌ |
| No crashes during rapid state changes | ✅ | ❌ |

### How to Verify

1. **Source breakdown**: Query by source to confirm proper tracking
2. **Restart test**: Kill app, verify persistence on reopen
3. **Terminated sync**: Walk while killed, verify sync on reopen (Android 11+ only)
4. **Memory profiling**: Use Flutter DevTools to check for leaks
5. **Stress test**: Rapid state changes should not cause issues

---

## Programmatic vs Manual Testing Analysis

### Scenarios That Can Be Automated

#### ✅ Scenario 2: External Source Import (100% Automated)
- **Why**: All API calls, no physical walking required
- **How**: Use `writeStepsToAggregated()` directly
- **Verification**: Query database and check math

```dart
testWidgets('External source import test', (tester) async {
  final stepCounter = AccurateStepCounter();
  await stepCounter.initSteps();
  
  await stepCounter.writeStepsToAggregated(
    stepCount: 500,
    fromTime: DateTime.now().subtract(Duration(hours: 1)),
    toTime: DateTime.now(),
    source: StepRecordSource.external,
  );
  
  final external = await stepCounter.getStepsBySource(StepRecordSource.external);
  expect(external, 500);
});
```

#### ✅ Scenario 3: Aggregated Mode Config (100% Automated)
- **Why**: Configuration verification, no sensors needed
- **How**: Check config values and initial behavior
- **Verification**: Assert config properties

```dart
test('Aggregated mode has no warmup by default', () {
  final config = StepRecordConfig.aggregated();
  expect(config.warmupDurationMs, 0);
  expect(config.enableAggregatedMode, true);
});
```

#### ✅ Scenario 4: Stream Initialization (95% Automated)
- **Why**: Stream behavior testing, use mock detector
- **How**: Mock step events, verify emissions
- **Verification**: Assert emission timing and values

#### ✅ Scenario 5: Error Handling (100% Automated)
- **Why**: Exception testing, no hardware needed
- **How**: Try invalid inputs, catch exceptions
- **Verification**: Assert correct exception types

#### ⚠️ Scenario 6: Lifecycle Management (70% Automated)
- **Why**: State changes can be simulated, but not sensor behavior
- **How**: Mock app lifecycle states
- **Limitation**: Real sensor behavior needs device testing

### Scenarios That Require Manual Testing

#### ❌ Scenario 1: Inactivity Timeout (Requires Manual)
- **Why**: Needs real walking and real inactivity periods
- **Limitation**: Can't simulate realistic accelerometer patterns
- **Verification**: Physical walking required

### Automation Summary

| Scenario | Automated % | Manual Required | Reason |
|----------|-------------|-----------------|--------|
| 1. Inactivity Timeout | 30% | Yes | Needs real sensor data |
| 2. External Source Import | 100% | No | Pure API testing |
| 3. Aggregated Mode Config | 100% | No | Configuration only |
| 4. Stream Initialization | 95% | Minimal | Can mock events |
| 5. Error Handling | 100% | No | Exception testing |
| 6. Lifecycle Management | 70% | Yes | Needs real state changes |

**Overall Automation Coverage**: ~82%

---

## Summary

These 6 comprehensive scenarios cover all critical aspects of the `accurate_step_counter` package:

1. **Inactivity Timeout** - New feature validation ✅
2. **External Source Import** - New feature validation ✅
3. **Aggregated Mode (No Warmup)** - Updated default behavior ✅
4. **Stream Initialization** - Bug fix verification ✅
5. **Error Handling** - Edge cases and recovery ✅
6. **Lifecycle Management** - State transitions and persistence ✅

### Test Coverage

- **New Features**: Inactivity timeout, external source import
- **Configuration**: No warmup default, aggregated mode
- **Bug Fixes**: Stream initial value, step persistence after restart
- **Error Cases**: Invalid inputs, missing permissions, state errors
- **Edge Cases**: Rapid state changes, multiple dispose/init cycles
- **Data Flow**: Stream emissions, database persistence, source tracking

### Recommended Testing Order

1. Start with **Scenario 5** (Error Handling) - quick, automated
2. Then **Scenario 3** (Config) - verify defaults are correct
3. Next **Scenario 2** (External Import) - test new API
4. Then **Scenario 4** (Streams) - verify critical bug fix
5. Finally **Scenarios 1 & 6** - manual testing with real device

### Success Criteria

All scenarios should pass their respective pass/fail criteria with:
- No crashes or unhandled exceptions
- Accurate step counting (±5% variance)
- Correct source tracking
- Proper data persistence
- Expected stream behavior
- Clear error messages

---

**Document Version**: 1.0  
**Package Version**: v1.5.0  
**Last Updated**: 2026-01-08
