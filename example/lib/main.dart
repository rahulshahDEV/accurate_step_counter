import 'package:flutter/material.dart';
import 'dart:async';

import 'package:accurate_step_counter/accurate_step_counter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _stepCounter = AccurateStepCounter();
  int _stepCount = 0;
  bool _isTracking = false;
  StreamSubscription<StepCountEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _initStepCounter();
  }

  Future<void> _initStepCounter() async {
    // Listen to step events
    _subscription = _stepCounter.stepEventStream.listen((event) {
      setState(() {
        _stepCount = event.stepCount;
      });
    });
  }

  Future<void> _startTracking() async {
    try {
      await _stepCounter.start(config: StepDetectorConfig.walking());
      setState(() {
        _isTracking = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting: $e')),
        );
      }
    }
  }

  Future<void> _stopTracking() async {
    await _stepCounter.stop();
    setState(() {
      _isTracking = false;
    });
  }

  void _resetCounter() {
    _stepCounter.reset();
    setState(() {
      _stepCount = 0;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accurate Step Counter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Accurate Step Counter'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Steps Detected:',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 20),
              Text(
                '$_stepCount',
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isTracking ? null : _startTracking,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isTracking ? _stopTracking : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _resetCounter,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      'How to test:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Tap Start\n'
                      '2. Walk around with your device\n'
                      '3. Watch the counter increase\n'
                      '4. Tap Stop when done',
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
