/// Accurate step counter plugin with accelerometer-based detection
///
/// This plugin provides highly accurate step counting using:
/// - Accelerometer-based detection with low-pass filtering
/// - Peak detection algorithm for reliable step counting
/// - Configurable sensitivity parameters
/// - OS-level step counter sync (Android)
/// - Background tracking support
/// - Zero data loss across app states
///
/// ## Quick Start
///
/// ```dart
/// import 'package:accurate_step_counter/accurate_step_counter.dart';
///
/// // Create instance
/// final stepCounter = AccurateStepCounter();
///
/// // Listen to step events
/// stepCounter.stepEventStream.listen((event) {
///   print('Steps: ${event.stepCount}');
/// });
///
/// // Start counting
/// await stepCounter.start();
///
/// // Stop counting
/// await stepCounter.stop();
/// ```
///
/// ## Custom Configuration
///
/// ```dart
/// // Start with custom sensitivity
/// await stepCounter.start(
///   config: StepDetectorConfig(
///     threshold: 1.2,           // Movement threshold
///     filterAlpha: 0.85,        // Smoothing factor
///     minTimeBetweenStepsMs: 250,
///   ),
/// );
///
/// // Or use presets
/// await stepCounter.start(config: StepDetectorConfig.walking());
/// await stepCounter.start(config: StepDetectorConfig.running());
/// ```
library;

// Export public API
export 'src/accurate_step_counter_impl.dart' show AccurateStepCounterImpl;
export 'src/models/step_count_event.dart' show StepCountEvent;
export 'src/models/step_detector_config.dart' show StepDetectorConfig;
// New names
export 'src/models/step_record.dart' show StepRecord, StepLogEntry;
export 'src/models/step_record_source.dart'
    show StepRecordSource, StepLogSource;
export 'src/models/step_record_config.dart'
    show StepRecordConfig, StepLoggingConfig;
export 'src/services/step_record_store.dart'
    show StepRecordStore, StepLogDatabase;

// Main class for easier access
import 'src/accurate_step_counter_impl.dart';

/// Main entry point for the accurate step counter plugin
///
/// This is a convenience wrapper around [AccurateStepCounterImpl]
/// for a simpler API.
///
/// Example:
/// ```dart
/// final stepCounter = AccurateStepCounter();
/// await stepCounter.start();
/// ```
class AccurateStepCounter extends AccurateStepCounterImpl {
  /// Creates a new instance of the step counter
  AccurateStepCounter();
}
