import 'package:flutter/material.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:permission_handler/permission_handler.dart';

/// Setup Verification Page
///
/// This page helps verify that the step counter plugin is properly configured
/// and ready for testing. It checks permissions, initializes logging, and
/// validates the detector setup.
class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _stepCounter = AccurateStepCounter();
  final List<VerificationStep> _steps = [];
  bool _isRunning = false;
  bool _allPassed = false;

  @override
  void initState() {
    super.initState();
    _initializeSteps();
  }

  void _initializeSteps() {
    _steps.addAll([
      VerificationStep(
        title: 'Activity Recognition Permission',
        description: 'Check if ACTIVITY_RECOGNITION permission is granted',
        check: _checkPermission,
      ),
      VerificationStep(
        title: 'Notification Permission',
        description: 'Check notification permission for foreground service',
        check: _checkNotificationPermission,
      ),
      VerificationStep(
        title: 'Initialize Logging',
        description: 'Initialize Hive database for step logging',
        check: _initializeLogging,
      ),
      VerificationStep(
        title: 'Start Step Counter',
        description: 'Start the step detection engine',
        check: _startStepCounter,
      ),
      VerificationStep(
        title: 'Check Native Detector',
        description: 'Verify hardware step detector availability',
        check: _checkNativeDetector,
      ),
      VerificationStep(
        title: 'Enable Step Logging',
        description: 'Start auto-logging steps to database',
        check: _enableLogging,
      ),
      VerificationStep(
        title: 'Test Real-time Stream',
        description: 'Verify step events are emitted',
        check: _testStream,
      ),
    ]);
  }

  Future<VerificationResult> _checkPermission() async {
    try {
      final hasPermission = await _stepCounter.hasActivityRecognitionPermission();

      if (!hasPermission) {
        final status = await Permission.activityRecognition.request();
        if (status.isGranted) {
          return VerificationResult.success('Permission granted');
        } else {
          return VerificationResult.failure(
            'Permission denied. Please grant ACTIVITY_RECOGNITION permission in Settings.',
          );
        }
      }

      return VerificationResult.success('Permission already granted');
    } catch (e) {
      return VerificationResult.failure('Error checking permission: $e');
    }
  }

  Future<VerificationResult> _checkNotificationPermission() async {
    try {
      final status = await Permission.notification.status;

      if (status.isDenied) {
        final result = await Permission.notification.request();
        if (result.isGranted) {
          return VerificationResult.success('Notification permission granted');
        } else {
          return VerificationResult.warning(
            'Notification permission denied. Foreground service may not work on Android 13+.',
          );
        }
      }

      return VerificationResult.success('Notification permission granted');
    } catch (e) {
      return VerificationResult.warning(
        'Could not check notification permission: $e',
      );
    }
  }

  Future<VerificationResult> _initializeLogging() async {
    try {
      await _stepCounter.initializeLogging(debugLogging: true);

      if (_stepCounter.isLoggingInitialized) {
        return VerificationResult.success('Logging database initialized');
      } else {
        return VerificationResult.failure('Failed to initialize logging');
      }
    } catch (e) {
      return VerificationResult.failure('Error initializing logging: $e');
    }
  }

  Future<VerificationResult> _startStepCounter() async {
    try {
      await _stepCounter.start(
        config: StepDetectorConfig(
          enableOsLevelSync: true,
          useForegroundServiceOnOldDevices: true,
        ),
      );

      if (_stepCounter.isStarted) {
        return VerificationResult.success('Step counter started');
      } else {
        return VerificationResult.failure('Failed to start step counter');
      }
    } catch (e) {
      return VerificationResult.failure('Error starting step counter: $e');
    }
  }

  Future<VerificationResult> _checkNativeDetector() async {
    try {
      final isHardware = await _stepCounter.isUsingNativeDetector();

      if (isHardware) {
        return VerificationResult.success(
          'Using hardware step detector (TYPE_STEP_DETECTOR)',
        );
      } else {
        return VerificationResult.warning(
          'Using accelerometer fallback. Hardware detector not available.',
        );
      }
    } catch (e) {
      return VerificationResult.failure('Error checking detector: $e');
    }
  }

  Future<VerificationResult> _enableLogging() async {
    try {
      await _stepCounter.startLogging(
        config: StepRecordConfig.walking(),
      );

      if (_stepCounter.isLoggingEnabled) {
        return VerificationResult.success(
          'Step logging enabled with walking preset',
        );
      } else {
        return VerificationResult.failure('Failed to enable logging');
      }
    } catch (e) {
      return VerificationResult.failure('Error enabling logging: $e');
    }
  }

  Future<VerificationResult> _testStream() async {
    try {
      // Wait for a step event or timeout after 5 seconds
      final event = await _stepCounter.stepEventStream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('No step events received'),
      );

      return VerificationResult.success(
        'Stream working. Current steps: ${event.stepCount}',
      );
    } on TimeoutException {
      return VerificationResult.warning(
        'No step events yet (walk a few steps to test). Stream is listening.',
      );
    } catch (e) {
      return VerificationResult.failure('Stream error: $e');
    }
  }

  Future<void> _runVerification() async {
    setState(() {
      _isRunning = true;
      _allPassed = false;
      for (final step in _steps) {
        step.reset();
      }
    });

    bool allSuccess = true;

    for (int i = 0; i < _steps.length; i++) {
      final step = _steps[i];

      setState(() {
        step.status = VerificationStatus.running;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      final result = await step.check();

      setState(() {
        step.status = result.status;
        step.message = result.message;
      });

      if (result.status == VerificationStatus.failure) {
        allSuccess = false;
        // Continue running other checks even if one fails
      }

      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() {
      _isRunning = false;
      _allPassed = allSuccess;
    });

    if (allSuccess) {
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('Setup Complete!'),
          ],
        ),
        content: const Text(
          'All verification checks passed. Your step counter is ready for testing!\n\n'
          'You can now:\n'
          '• Test real-time step counting\n'
          '• Try background mode\n'
          '• Test terminated state recovery\n'
          '• View comprehensive scenarios in TESTING_SCENARIOS.md',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Start Testing'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Verification'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Step Counter Setup Verification',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This tool verifies that the step counter plugin is properly configured.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Verification Steps List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _steps.length,
              itemBuilder: (context, index) {
                final step = _steps[index];
                return _buildVerificationTile(index + 1, step);
              },
            ),
          ),

          // Run Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _runVerification,
                icon: _isRunning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _isRunning ? 'Running Verification...' : 'Run Verification',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationTile(int number, VerificationStep step) {
    IconData icon;
    Color iconColor;

    switch (step.status) {
      case VerificationStatus.pending:
        icon = Icons.circle_outlined;
        iconColor = Colors.grey;
        break;
      case VerificationStatus.running:
        icon = Icons.sync;
        iconColor = Colors.blue;
        break;
      case VerificationStatus.success:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case VerificationStatus.warning:
        icon = Icons.warning;
        iconColor = Colors.orange;
        break;
      case VerificationStatus.failure:
        icon = Icons.error;
        iconColor = Colors.red;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (step.status == VerificationStatus.running)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, color: iconColor, size: 24),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              step.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            if (step.message != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getMessageBackgroundColor(step.status),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getMessageIcon(step.status),
                      size: 16,
                      color: iconColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.message!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getMessageBackgroundColor(VerificationStatus status) {
    switch (status) {
      case VerificationStatus.success:
        return Colors.green.shade50;
      case VerificationStatus.warning:
        return Colors.orange.shade50;
      case VerificationStatus.failure:
        return Colors.red.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  IconData _getMessageIcon(VerificationStatus status) {
    switch (status) {
      case VerificationStatus.success:
        return Icons.check_circle_outline;
      case VerificationStatus.warning:
        return Icons.warning_amber;
      case VerificationStatus.failure:
        return Icons.error_outline;
      default:
        return Icons.info_outline;
    }
  }

  @override
  void dispose() {
    // Note: Don't dispose stepCounter here as it may be used in other parts of the app
    super.dispose();
  }
}

// Models
class VerificationStep {
  final String title;
  final String description;
  final Future<VerificationResult> Function() check;
  VerificationStatus status;
  String? message;

  VerificationStep({
    required this.title,
    required this.description,
    required this.check,
    this.status = VerificationStatus.pending,
    this.message,
  });

  void reset() {
    status = VerificationStatus.pending;
    message = null;
  }
}

enum VerificationStatus {
  pending,
  running,
  success,
  warning,
  failure,
}

class VerificationResult {
  final VerificationStatus status;
  final String message;

  VerificationResult.success(this.message) : status = VerificationStatus.success;
  VerificationResult.warning(this.message) : status = VerificationStatus.warning;
  VerificationResult.failure(this.message) : status = VerificationStatus.failure;
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
}
