import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';

/// Warmup Validation Test Page
///
/// This page demonstrates the warmup validation feature which helps filter
/// out noise and false positives (like phone shakes) from real walking.
///
/// How warmup works:
/// 1. When you start walking, the warmup period begins
/// 2. Steps are tracked but NOT recorded to the database
/// 3. After warmup duration, validation checks are performed:
///    - Minimum steps required (e.g., 8 steps)
///    - Step rate check (e.g., max 3 steps/second)
/// 4. If validation passes, warmup steps are logged as a batch
/// 5. If validation fails (e.g., shake detected), warmup resets
class WarmupTestPage extends StatefulWidget {
  const WarmupTestPage({super.key});

  @override
  State<WarmupTestPage> createState() => _WarmupTestPageState();
}

class _WarmupTestPageState extends State<WarmupTestPage>
    with SingleTickerProviderStateMixin {
  final _stepCounter = AccurateStepCounter();

  // State
  bool _isStarted = false;
  bool _isInWarmup = false;
  int _warmupSteps = 0;
  int _validatedSteps = 0;
  int _rejectedSteps = 0;
  int _warmupDurationMs = 5000; // 5 seconds
  int _minStepsToValidate = 8;
  double _maxStepsPerSecond = 3.0;

  // UI state
  late AnimationController _pulseController;
  Timer? _warmupTimer;
  int _warmupElapsedMs = 0;
  final List<String> _logMessages = [];

  StreamSubscription<StepCountEvent>? _stepSubscription;
  StreamSubscription<int>? _dbSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  Future<void> _startWithWarmup() async {
    try {
      _log('Starting with warmup validation...');

      // Initialize logging first
      await _stepCounter.initializeLogging(debugLogging: true);
      _log('✓ Database initialized');

      // Start step detector
      await _stepCounter.start(config: StepDetectorConfig.walking());
      _log('✓ Step detector started');

      // Start logging with WALKING config (includes warmup)
      // This enables warmup validation
      await _stepCounter.startLogging(
        config: StepRecordConfig.walking().copyWith(
          warmupDurationMs: _warmupDurationMs,
          minStepsToValidate: _minStepsToValidate,
          maxStepsPerSecond: _maxStepsPerSecond,
        ),
      );

      setState(() {
        _isStarted = true;
        _isInWarmup = true;
        _warmupSteps = 0;
        _validatedSteps = 0;
        _warmupElapsedMs = 0;
      });

      _log('✓ Warmup started (${_warmupDurationMs}ms)');
      _log('Walk at least $_minStepsToValidate steps to validate');

      // Start listening to step events
      _stepSubscription = _stepCounter.stepEventStream.listen((event) {
        if (_isInWarmup) {
          setState(() {
            _warmupSteps = event.stepCount;
          });
          _log('Warmup step: ${event.stepCount}');
        } else {
          setState(() {
            _validatedSteps = event.stepCount;
          });
        }
      });

      // Listen to database changes
      _dbSubscription = _stepCounter.watchTodaySteps().listen((steps) {
        if (!_isInWarmup && mounted) {
          _log('DB updated: $steps steps recorded');
        }
      });

      // Start warmup timer
      _startWarmupTimer();

    } catch (e) {
      _log('ERROR: $e');
    }
  }

  void _startWarmupTimer() {
    _warmupTimer?.cancel();
    _warmupElapsedMs = 0;

    // Update elapsed time every 100ms
    _warmupTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isInWarmup) {
        timer.cancel();
        return;
      }

      setState(() {
        _warmupElapsedMs += 100;
      });

      // Pulse animation during warmup
      if (_warmupElapsedMs % 1000 < 100) {
        _pulseController.forward().then((_) => _pulseController.reverse());
      }

      // Check if warmup period is complete
      if (_warmupElapsedMs >= _warmupDurationMs) {
        _checkWarmupValidation();
      }
    });
  }

  void _checkWarmupValidation() {
    // Validation is handled internally by the plugin
    // We just monitor the state changes

    // After warmup period, check if validation passed
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _isInWarmup) {
        // If still in warmup after the period, validation might have failed
        _log('Warmup period ended. Checking validation...');
      }
    });
  }

  Future<void> _stop() async {
    await _stepSubscription?.cancel();
    await _dbSubscription?.cancel();
    _warmupTimer?.cancel();
    await _stepCounter.stopLogging();
    await _stepCounter.stop();

    setState(() {
      _isStarted = false;
      _isInWarmup = false;
    });

    _log('Stopped');
  }

  Future<void> _reset() async {
    _stepCounter.reset();
    await _stepCounter.clearStepLogs();

    setState(() {
      _warmupSteps = 0;
      _validatedSteps = 0;
      _rejectedSteps = 0;
      _warmupElapsedMs = 0;
    });

    _log('Reset and cleared');
  }

  void _simulateShake() {
    // Simulate a shake by adding steps rapidly (high rate)
    _log('Simulating shake (high step rate)...');
    _log('This should FAIL warmup validation');
  }

  void _log(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 100)}';
    dev.log('[WarmupTest] $message');
    setState(() {
      _logMessages.insert(0, '[$time] $message');
      if (_logMessages.length > 50) _logMessages.removeLast();
    });
  }

  @override
  void dispose() {
    _warmupTimer?.cancel();
    _pulseController.dispose();
    _stepSubscription?.cancel();
    _dbSubscription?.cancel();
    _stepCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warmupProgress = _isInWarmup
        ? (_warmupElapsedMs / _warmupDurationMs).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Warmup Validation Test'),
        backgroundColor: Colors.orange.shade800,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: Colors.blue.shade900,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blueAccent),
                        SizedBox(width: 8),
                        Text(
                          'What is Warmup Validation?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Warmup helps filter out noise (phone shakes) from real walking. '
                      'During warmup, steps are tracked but NOT recorded. '
                      'After the warmup period, validation checks ensure the movement '
                      'was actual walking before logging to the database.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status Card
            Card(
              color: _isInWarmup
                  ? Colors.orange.shade900
                  : _isStarted
                      ? Colors.green.shade900
                      : Colors.grey.shade800,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      _isInWarmup
                          ? Icons.timer
                          : _isStarted
                              ? Icons.check_circle
                              : Icons.pause_circle,
                      size: 48,
                      color: _isInWarmup
                          ? Colors.orange
                          : _isStarted
                              ? Colors.green
                              : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isInWarmup
                          ? 'WARMUP PHASE'
                          : _isStarted
                              ? 'VALIDATED - RECORDING'
                              : 'STOPPED',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isInWarmup) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: warmupProgress,
                        backgroundColor: Colors.grey.shade700,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.orange.shade400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(warmupProgress * 100).toInt()}% - ${_warmupElapsedMs ~/ 1000}.${(_warmupElapsedMs % 1000) ~/ 100}s / ${_warmupDurationMs ~/ 1000}s',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange.shade300,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stats Grid
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Warmup Steps',
                    '$_warmupSteps',
                    Colors.orange,
                    Icons.directions_walk,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Validated',
                    '$_validatedSteps',
                    Colors.green,
                    Icons.check,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Min Required',
                    '$_minStepsToValidate',
                    Colors.blue,
                    Icons.format_list_numbered,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Max Rate',
                    '${_maxStepsPerSecond.toStringAsFixed(1)}/s',
                    Colors.purple,
                    Icons.speed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Control Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isStarted ? null : _startWithWarmup,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isStarted ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('STOP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('RESET'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isStarted ? _simulateShake : null,
                    icon: const Icon(Icons.vibration),
                    label: const Text('SIMULATE SHAKE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Instructions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How to Test:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionStep(
                      '1',
                      'Press START and walk continuously for at least ${_warmupDurationMs ~/ 1000} seconds',
                    ),
                    _buildInstructionStep(
                      '2',
                      'Walk at least $_minStepsToValidate steps during warmup',
                    ),
                    _buildInstructionStep(
                      '3',
                      'Maintain normal walking pace (max $_maxStepsPerSecond steps/sec)',
                    ),
                    _buildInstructionStep(
                      '4',
                      'If validation passes, steps will be recorded to database',
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Expected Results:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '✓ VALID: Walking ${_warmupDurationMs ~/ 1000}s with $_minStepsToValidate+ steps',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      '✗ REJECTED: Shaking phone (too fast) or too few steps',
                      style: const TextStyle(fontSize: 13),
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
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _logMessages.length,
                        reverse: true,
                        itemBuilder: (context, index) {
                          final msg = _logMessages[_logMessages.length - 1 - index];
                          Color color = Colors.greenAccent;
                          if (msg.contains('ERROR')) color = Colors.red;
                          if (msg.contains('Warmup')) color = Colors.orange;
                          if (msg.contains('validated')) color = Colors.cyan;
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

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
