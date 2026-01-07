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
  int _liveStepCount = 0;
  int _loggedSteps = 0;
  int _aggregatedSteps = 0;
  int _fgSteps = 0;
  int _bgSteps = 0;
  int _termSteps = 0;
  bool _isTracking = false;
  bool _isAggregatedMode = false;
  String _currentPreset = 'None';
  String _appState = 'resumed';
  final List<String> _logMessages = [];

  StreamSubscription<StepCountEvent>? _stepSubscription;
  StreamSubscription<int>? _totalSubscription;
  StreamSubscription<int>? _aggregatedSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLogging();
  }

  Future<void> _initLogging() async {
    await _stepCounter.initializeLogging();
    _log('Database initialized');

    // Listen to live steps
    _stepSubscription = _stepCounter.stepEventStream.listen((event) {
      setState(() => _liveStepCount = event.stepCount);
    });

    // Listen to logged total
    _totalSubscription = _stepCounter.watchTotalSteps().listen((total) {
      setState(() => _loggedSteps = total);
      _updateSourceStats();
    });

    // Set callback for terminated steps
    _stepCounter.onTerminatedStepsDetected = (steps, from, to) {
      _log('TERMINATED: $steps steps synced');
    };

    _updateSourceStats();
  }

  Future<void> _updateSourceStats() async {
    final fg = await _stepCounter.getStepsBySource(StepRecordSource.foreground);
    final bg = await _stepCounter.getStepsBySource(StepRecordSource.background);
    final term = await _stepCounter.getStepsBySource(StepRecordSource.terminated);
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
  }

  void _log(String message) {
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute}:${now.second}';
    setState(() {
      _logMessages.insert(0, '[$time] $message');
      if (_logMessages.length > 20) _logMessages.removeLast();
    });
  }

  Future<void> _startWithPreset(String preset, StepRecordConfig config) async {
    if (_isTracking) await _stop();

    try {
      await _stepCounter.start(config: StepDetectorConfig.walking());
      await _stepCounter.startLogging(config: config);

      // Check if aggregated mode is enabled
      final isAggregated = config.enableAggregatedMode;

      setState(() {
        _isTracking = true;
        _isAggregatedMode = isAggregated;
        _currentPreset = preset;
      });

      // Listen to aggregated stream if enabled
      if (isAggregated) {
        await _aggregatedSubscription?.cancel();
        _aggregatedSubscription =
            _stepCounter.watchAggregatedStepCounter().listen((count) {
          setState(() => _aggregatedSteps = count);
        });
        _log('Started with $preset preset (AGGREGATED MODE)');
      } else {
        _log('Started with $preset preset');
      }
    } catch (e) {
      _log('Error: $e');
    }
  }

  Future<void> _stop() async {
    await _aggregatedSubscription?.cancel();
    await _stepCounter.stopLogging();
    await _stepCounter.stop();
    setState(() {
      _isTracking = false;
      _isAggregatedMode = false;
      _currentPreset = 'None';
    });
    _log('Stopped');
  }

  Future<void> _clearLogs() async {
    await _stepCounter.clearStepLogs();
    _stepCounter.reset();
    setState(() {
      _liveStepCount = 0;
      _aggregatedSteps = 0;
    });
    _log('Logs cleared');
    _updateSourceStats();
  }

  Future<void> _manuallyAddSteps() async {
    if (!_isAggregatedMode) {
      _log('Error: Manual add only works in aggregated mode');
      return;
    }

    try {
      // Write 50 steps to the database
      await _stepCounter.writeStepsToAggregated(
        stepCount: 50,
        fromTime: DateTime.now().subtract(const Duration(minutes: 5)),
        toTime: DateTime.now(),
        source: StepRecordSource.foreground,
      );
      _log('Manually added 50 steps');
      _updateSourceStats();
    } catch (e) {
      _log('Error adding steps: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepSubscription?.cancel();
    _totalSubscription?.cancel();
    _aggregatedSubscription?.cancel();
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
              // Stats Card
              _buildStatsCard(),
              const SizedBox(height: 16),

              // Preset Buttons
              _buildPresetSection(),
              const SizedBox(height: 16),

              // Control Buttons
              _buildControlButtons(),
              const SizedBox(height: 16),

              // Log Output
              _buildLogSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isAggregatedMode)
              Column(
                children: [
                  Text(
                    'Aggregated: $_aggregatedSteps',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.tealAccent,
                    ),
                  ),
                  const Text(
                    '(Today\'s stored + Live)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(),
                ],
              )
            else
              Text(
                'Live: $_liveStepCount | Logged: $_loggedSteps',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('FG', _fgSteps, Colors.green),
                _statItem('BG', _bgSteps, Colors.orange),
                _statItem('TERM', _termSteps, Colors.red),
              ],
            ),
            const SizedBox(height: 8),
            Text('Preset: $_currentPreset'),
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
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Start with Preset:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _presetButton('Aggregated', StepRecordConfig.aggregated(),
                    isSpecial: true),
                _presetButton('Walking', StepRecordConfig.walking()),
                _presetButton('Running', StepRecordConfig.running()),
                _presetButton('Sensitive', StepRecordConfig.sensitive()),
                _presetButton('Conservative', StepRecordConfig.conservative()),
                _presetButton(
                  'No Validation',
                  StepRecordConfig.noValidation(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetButton(String name, StepRecordConfig config,
      {bool isSpecial = false}) {
    final isActive = _currentPreset == name;
    return ElevatedButton(
      onPressed: () => _startWithPreset(name, config),
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive
            ? (isSpecial ? Colors.tealAccent : Colors.teal)
            : (isSpecial ? Colors.teal[800] : null),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontWeight: isSpecial ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isTracking ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _clearLogs,
                icon: const Icon(Icons.delete),
                label: const Text('Clear'),
              ),
            ),
          ],
        ),
        if (_isAggregatedMode) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _manuallyAddSteps,
              icon: const Icon(Icons.add),
              label: const Text('Add 50 Steps Manually'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[700],
              ),
            ),
          ),
        ],
      ],
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
                      fontSize: 12,
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
