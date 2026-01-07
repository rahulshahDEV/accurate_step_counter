import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const StepCounterTestApp());
}

class StepCounterTestApp extends StatefulWidget {
  const StepCounterTestApp({super.key});

  @override
  State<StepCounterTestApp> createState() => _StepCounterTestAppState();
}

class _StepCounterTestAppState extends State<StepCounterTestApp>
    with WidgetsBindingObserver {
  final _stepCounter = AccurateStepCounter();

  // State
  int _todaySteps = 0;
  int _liveStepCount = 0;
  int _aggregatedCount = 0;
  int _fgSteps = 0;
  int _bgSteps = 0;
  int _termSteps = 0;
  bool _isInitialized = false;
  bool _hasPermission = false;
  String _appState = 'resumed';
  String _detectorType = 'Unknown';
  final List<String> _logMessages = [];

  StreamSubscription<int>? _todaySubscription;
  StreamSubscription<int>? _aggregatedSubscription;
  StreamSubscription<StepCountEvent>? _stepSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndInit();
  }

  Future<void> _requestPermissionAndInit() async {
    _log('Requesting permissions...');

    // Request activity recognition permission
    final activityStatus = await Permission.activityRecognition.request();
    _log('Activity recognition: ${activityStatus.name}');

    // Request notification permission (for foreground service on Android 13+)
    final notifStatus = await Permission.notification.request();
    _log('Notification: ${notifStatus.name}');

    if (activityStatus.isGranted) {
      setState(() => _hasPermission = true);
      await _initStepCounter();
    } else {
      _log('ERROR: Activity recognition permission denied!');
      setState(() => _hasPermission = false);
    }
  }

  Future<void> _initStepCounter() async {
    try {
      _log('Initializing step counter...');

      // Step 1: Initialize logging database
      await _stepCounter.initializeLogging(debugLogging: true);
      _log('✓ Database initialized');

      // Step 2: Start step detector with walking config
      await _stepCounter.start(config: StepDetectorConfig.walking());
      _log('✓ Step detector started');

      // Check detector type
      final isHardware = await _stepCounter.isUsingNativeDetector();
      setState(() => _detectorType = isHardware ? 'Hardware' : 'Accelerometer');
      _log('Detector type: $_detectorType');

      // Step 3: Start logging with NO WARMUP for easier testing
      await _stepCounter.startLogging(
        config: StepRecordConfig(
          recordIntervalMs: 1000,
          warmupDurationMs: 0, // NO WARMUP!
          minStepsToValidate: 1, // Just 1 step needed
          maxStepsPerSecond: 10.0,
          inactivityTimeoutMs: 0,
          enableAggregatedMode: true,
        ),
      );
      _log('✓ Logging started (NO warmup, aggregated mode)');

      setState(() => _isInitialized = true);

      // Step 4: Subscribe to streams AFTER initialization
      _log('Setting up streams...');

      // Raw step events from native detector
      _stepSubscription = _stepCounter.stepEventStream.listen((event) {
        dev.log('RAW STEP EVENT: ${event.stepCount}');
        _log('RAW: ${event.stepCount} steps');
        setState(() => _liveStepCount = event.stepCount);
      }, onError: (e) => _log('Step stream error: $e'));
      _log('✓ stepEventStream subscribed');

      // Aggregated count (stored + live)
      _aggregatedSubscription = _stepCounter
          .watchAggregatedStepCounter()
          .listen((steps) {
            dev.log('AGGREGATED: $steps');
            _log('AGGREGATED: $steps steps');
            setState(() => _aggregatedCount = steps);
          }, onError: (e) => _log('Aggregated stream error: $e'));
      _log('✓ watchAggregatedStepCounter subscribed');

      // DB total for today
      _todaySubscription = _stepCounter.watchTodaySteps().listen((steps) {
        dev.log('DB TOTAL: $steps');
        setState(() => _todaySteps = steps);
        _updateSourceStats();
      }, onError: (e) => _log('Today stream error: $e'));
      _log('✓ watchTodaySteps subscribed');

      // Terminated steps callback
      _stepCounter.onTerminatedStepsDetected = (steps, from, to) {
        _log('TERMINATED SYNC: $steps steps!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced $steps missed steps!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      };

      // Load initial data
      await _refreshData();
      _log('=== READY! Walk to test ===');
    } catch (e, stack) {
      _log('ERROR: $e');
      dev.log('Init error: $e\n$stack');
    }
  }

  Future<void> _refreshData() async {
    if (!_isInitialized) return;

    final today = await _stepCounter.getTodayStepCount();
    setState(() => _todaySteps = today);
    await _updateSourceStats();
    _log('Refreshed: $today steps today');
  }

  Future<void> _updateSourceStats() async {
    if (!_isInitialized) return;
    final fg = await _stepCounter.getStepsBySource(StepRecordSource.foreground);
    final bg = await _stepCounter.getStepsBySource(StepRecordSource.background);
    final term = await _stepCounter.getStepsBySource(
      StepRecordSource.terminated,
    );
    setState(() {
      _fgSteps = fg;
      _bgSteps = bg;
      _termSteps = term;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _stepCounter.setAppState(state);
    setState(() => _appState = state.name);
    _log('App state: ${state.name}');
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  void _log(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    dev.log('[StepTest] $message');
    setState(() {
      _logMessages.insert(0, '[$time] $message');
      if (_logMessages.length > 100) _logMessages.removeLast();
    });
  }

  Future<void> _clearAllData() async {
    await _stepCounter.clearStepLogs();
    _stepCounter.reset();
    setState(() {
      _todaySteps = 0;
      _liveStepCount = 0;
      _aggregatedCount = 0;
      _fgSteps = 0;
      _bgSteps = 0;
      _termSteps = 0;
    });
    _log('All data cleared');
  }

  Future<void> _addTestSteps() async {
    try {
      await _stepCounter.writeStepsToAggregated(
        stepCount: 10,
        fromTime: DateTime.now().subtract(const Duration(minutes: 1)),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      _log('Added 10 test steps');
    } catch (e) {
      _log('Error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _todaySubscription?.cancel();
    _aggregatedSubscription?.cancel();
    _stepSubscription?.cancel();
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step Counter Debug',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Step Counter Debug'),
          actions: [
            Chip(
              label: Text(_appState),
              backgroundColor: _appState == 'resumed'
                  ? Colors.green
                  : Colors.orange,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              Card(
                color: _hasPermission
                    ? Colors.green.shade900
                    : Colors.red.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        _hasPermission
                            ? '✓ Permission Granted'
                            : '✗ Permission DENIED',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('Detector: $_detectorType'),
                      Text(
                        'Status: ${_isInitialized ? 'Active' : 'Initializing...'}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Main Stats
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Aggregated\n(stored+live)',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '$_aggregatedCount',
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                              color: Colors.tealAccent,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMiniStat('DB Total', '$_todaySteps'),
                          _buildMiniStat('Live', '$_liveStepCount'),
                          _buildMiniStat('FG', '$_fgSteps', Colors.green),
                          _buildMiniStat('BG', '$_bgSteps', Colors.orange),
                          _buildMiniStat('Term', '$_termSteps', Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _refreshData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addTestSteps,
                      icon: const Icon(Icons.add),
                      label: const Text('+10 Steps'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _clearAllData,
                      icon: const Icon(Icons.delete),
                      label: const Text('Clear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Debug Log
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Debug Log:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _logMessages.length,
                          itemBuilder: (context, index) {
                            final msg = _logMessages[index];
                            Color color = Colors.greenAccent;
                            if (msg.contains('ERROR')) color = Colors.red;
                            if (msg.contains('RAW:')) color = Colors.yellow;
                            if (msg.contains('AGGREGATED:')) {
                              color = Colors.cyan;
                            }
                            return Text(
                              msg,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: color,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, [Color? color]) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color ?? Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
