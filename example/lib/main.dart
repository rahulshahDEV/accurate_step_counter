import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'verification_page.dart';
import 'warmup_test_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StepCounterApp());
}

class StepCounterApp extends StatelessWidget {
  const StepCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accurate Step Counter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const StepCounterHomePage(),
    );
  }
}

class StepCounterHomePage extends StatefulWidget {
  const StepCounterHomePage({super.key});

  @override
  State<StepCounterHomePage> createState() => _StepCounterHomePageState();
}

class _StepCounterHomePageState extends State<StepCounterHomePage>
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

      // Simple one-line initialization with debug logging
      await _stepCounter.initSteps(debugLogging: true);
      _log('✓ Step counter initialized');

      // Check detector type
      final isHardware = await _stepCounter.isUsingNativeDetector();
      setState(() => _detectorType = isHardware ? 'Hardware' : 'Accelerometer');
      _log('Detector type: $_detectorType');

      // Subscribe to aggregated count stream (stored + live steps)
      _aggregatedSubscription = _stepCounter
          .watchAggregatedStepCounter()
          .listen(
            (steps) {
              dev.log('AGGREGATED: $steps');
              _log('AGGREGATED: $steps steps');
              setState(() => _aggregatedCount = steps);
            },
            onError: (e) => _log('Aggregated stream error: $e'),
          );
      _log('✓ watchAggregatedStepCounter subscribed');

      // Subscribe to DB total for today
      _todaySubscription = _stepCounter.watchTodaySteps().listen(
        (steps) {
          dev.log('DB TOTAL: $steps');
          setState(() => _todaySteps = steps);
          _updateSourceStats();
        },
        onError: (e) => _log('Today stream error: $e'),
      );
      _log('✓ watchTodaySteps subscribed');

      // Subscribe to raw step events from detector
      _stepSubscription = _stepCounter.stepEventStream.listen(
        (event) {
          dev.log('RAW STEP EVENT: ${event.stepCount}');
          _log('RAW: ${event.stepCount} steps');
          setState(() => _liveStepCount = event.stepCount);
        },
        onError: (e) => _log('Step stream error: $e'),
      );
      _log('✓ stepEventStream subscribed');

      // Terminated steps callback
      _stepCounter.onTerminatedStepsDetected = (steps, from, to) {
        _log('TERMINATED SYNC: $steps steps!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced $steps missed steps from terminated state!'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      };

      // Mark as initialized AFTER streams are set up
      setState(() => _isInitialized = true);

      // Load initial data (stats by source)
      await _refreshData();
      _log('=== READY! Walk to test ===');
    } catch (e, stack) {
      _log('ERROR during initialization: $e');
      dev.log('Init error: $e\n$stack');

      // Cleanup on error
      setState(() => _isInitialized = false);
      await _cleanupStreams();
    }
  }

  Future<void> _cleanupStreams() async {
    await _stepSubscription?.cancel();
    await _aggregatedSubscription?.cancel();
    await _todaySubscription?.cancel();
    _stepSubscription = null;
    _aggregatedSubscription = null;
    _todaySubscription = null;
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
    dev.log('[StepCounter] $message');
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

  Future<void> _openVerificationPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VerificationPage()),
    );
  }

  Future<void> _openWarmupTestPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WarmupTestPage()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupStreams();
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accurate Step Counter'),
        actions: [
          Chip(
            label: Text(_appState),
            backgroundColor:
                _appState == 'resumed' ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _openVerificationPage,
            icon: const Icon(Icons.verified),
            tooltip: 'Setup Verification',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color:
                  _hasPermission ? Colors.green.shade900 : Colors.red.shade900,
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

            // Main Stats - Aggregated Count
            Card(
              color: Colors.teal.shade900,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Today\'s Steps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_aggregatedCount',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color: Colors.tealAccent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aggregated (Stored + Live)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Source Breakdown
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Steps by Source',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMiniStat('Database', '$_todaySteps', Colors.blue),
                        _buildMiniStat('Live', '$_liveStepCount', Colors.purple),
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
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _openVerificationPage,
              icon: const Icon(Icons.verified_user),
              label: const Text('Run Setup Verification'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _openWarmupTestPage,
              icon: const Icon(Icons.timer),
              label: const Text('Test Warmup Validation'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 16),

            // Step Logs Viewer
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Step Logs (Database):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (_isInitialized)
                      StepLogsViewer(
                        stepCounter: _stepCounter,
                        maxHeight: 200,
                        showFilters: true,
                        showExportButton: true,
                        showDatePicker: false,
                      )
                    else
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Initializing...'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Debug Log
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Debug Log:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _logMessages.clear()),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
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
                          if (msg.contains('AGGREGATED:')) color = Colors.cyan;
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
    );
  }

  Widget _buildMiniStat(String label, String value, [Color? color]) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color ?? Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
