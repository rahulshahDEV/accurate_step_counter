import 'dart:async';

import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';

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
  int _yesterdaySteps = 0;
  int _liveStepCount = 0;
  int _fgSteps = 0;
  int _bgSteps = 0;
  int _termSteps = 0;
  bool _isInitialized = false;
  String _appState = 'resumed';
  final List<String> _logMessages = [];

  StreamSubscription<int>? _todaySubscription;
  StreamSubscription<StepCountEvent>? _stepSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initStepCounter();
  }

  /// Initialize step counter using the simplified API
  Future<void> _initStepCounter() async {
    try {
      // Simple one-line initialization!
      await _stepCounter.initSteps(debugLogging: true);

      setState(() => _isInitialized = true);
      _log('Step counter initialized successfully!');

      // Watch today's steps in real-time
      _todaySubscription = _stepCounter.watchTodaySteps().listen((steps) {
        setState(() => _todaySteps = steps);
        _log('Today steps updated: $steps');
        _updateSourceStats();
      });

      // Also listen to raw step events for debugging
      _stepSubscription = _stepCounter.stepEventStream.listen((event) {
        setState(() => _liveStepCount = event.stepCount);
      });

      // Set callback for terminated steps
      _stepCounter.onTerminatedStepsDetected = (steps, from, to) {
        _log(
          'TERMINATED: $steps steps synced from ${from.toString().split('.')[0]} to ${to.toString().split('.')[0]}',
        );
      };

      // Load initial data
      await _refreshData();
    } catch (e) {
      _log('Error initializing: $e');
    }
  }

  /// Refresh all step data
  Future<void> _refreshData() async {
    if (!_isInitialized) return;

    final today = await _stepCounter.getTodayStepCount();
    final yesterday = await _stepCounter.getYesterdayStepCount();

    setState(() {
      _todaySteps = today;
      _yesterdaySteps = yesterday;
    });

    await _updateSourceStats();
    _log('Data refreshed - Today: $today, Yesterday: $yesterday');
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

    // Refresh data when coming back to foreground
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  void _log(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logMessages.insert(0, '[$time] $message');
      if (_logMessages.length > 30) _logMessages.removeLast();
    });
  }

  Future<void> _testCustomRange() async {
    try {
      // Test: Get last 7 days
      final weekSteps = await _stepCounter.getStepCount(
        start: DateTime.now().subtract(const Duration(days: 7)),
        end: DateTime.now(),
      );
      _log('Last 7 days: $weekSteps steps');

      // Test: Get last 30 days
      final monthSteps = await _stepCounter.getStepCount(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      );
      _log('Last 30 days: $monthSteps steps');
    } catch (e) {
      _log('Error getting custom range: $e');
    }
  }

  Future<void> _clearAllData() async {
    await _stepCounter.clearStepLogs();
    _stepCounter.reset();
    setState(() {
      _todaySteps = 0;
      _yesterdaySteps = 0;
      _liveStepCount = 0;
      _fgSteps = 0;
      _bgSteps = 0;
      _termSteps = 0;
    });
    _log('All step data cleared');
  }

  Future<void> _addTestSteps() async {
    try {
      // Manually add 50 test steps
      await _stepCounter.writeStepsToAggregated(
        stepCount: 50,
        fromTime: DateTime.now().subtract(const Duration(minutes: 5)),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      _log('Added 50 test steps');
      await _refreshData();
    } catch (e) {
      _log('Error adding steps: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _todaySubscription?.cancel();
    _stepSubscription?.cancel();
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step Counter Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Step Counter Test'),
          actions: [
            Chip(label: Text(_appState)),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Stats
              _buildMainStatsCard(),
              const SizedBox(height: 16),

              // Source Breakdown
              _buildSourceBreakdownCard(),
              const SizedBox(height: 16),

              // Action Buttons
              _buildActionButtons(),
              const SizedBox(height: 16),

              // Test Scenarios
              _buildTestScenarios(),
              const SizedBox(height: 16),

              // Log Output
              _buildLogSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Today\'s Steps', style: TextStyle(fontSize: 16)),
                Text(
                  '$_todaySteps',
                  style: const TextStyle(
                    fontSize: 48,
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
                _buildMiniStat('Yesterday', '$_yesterdaySteps'),
                _buildMiniStat('Live Count', '$_liveStepCount'),
                _buildMiniStat(
                  'Status',
                  _isInitialized ? 'Active' : 'Initializing...',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 18)),
      ],
    );
  }

  Widget _buildSourceBreakdownCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Source Breakdown',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('Foreground', _fgSteps, Colors.green),
                _statItem('Background', _bgSteps, Colors.orange),
                _statItem('Terminated', _termSteps, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 12)),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
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
                onPressed: _clearAllData,
                icon: const Icon(Icons.delete),
                label: const Text('Clear All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _addTestSteps,
                icon: const Icon(Icons.add),
                label: const Text('Add 50 Steps'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple[700],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _testCustomRange,
                icon: const Icon(Icons.date_range),
                label: const Text('Test Ranges'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTestScenarios() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Test Scenarios',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Fresh start: Open app, walk 20 steps\n'
              '2. Restart test: Close app, reopen - count should persist\n'
              '3. Background: Put app in background, walk, return\n'
              '4. Terminated: Force-kill app, walk, reopen\n'
              '5. Day boundary: Walk before/after midnight\n'
              '6. Custom range: Test week/month queries',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Log:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  return Text(
                    _logMessages[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.greenAccent,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
