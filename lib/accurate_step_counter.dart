/// Production-grade Android step counter for Flutter.
///
/// Primary path: hardware **TYPE_STEP_COUNTER** foreground service (all API 24+),
/// with SQLite logging and production-hardened merge helpers for BYO Health Connect.
///
/// ## Quick Start (recommended)
///
/// ```dart
/// import 'package:accurate_step_counter/accurate_step_counter.dart';
/// import 'package:permission_handler/permission_handler.dart';
///
/// final steps = AccurateStepCounter();
/// await Permission.activityRecognition.request();
/// await Permission.notification.request();
/// await steps.startTracking();
/// steps.watchTodaySteps().listen((n) => print('Today: $n'));
/// ```
///
/// Wire [AccurateStepCounter.setAppState] from your [WidgetsBindingObserver]
/// so midnight rotation drains on resume.
library;

// Export public API
export 'src/accurate_step_counter_impl.dart' show AccurateStepCounterImpl;
export 'src/models/step_count_event.dart' show StepCountEvent;
export 'src/models/step_detector_config.dart' show StepDetectorConfig;
export 'src/models/step_runtime_state.dart' show StepRuntimeState;
export 'src/models/step_record.dart' show StepRecord;
export 'src/models/step_record_source.dart' show StepRecordSource;
export 'src/models/step_record_config.dart' show StepRecordConfig;
export 'src/services/step_record_store.dart' show StepRecordStore;
export 'src/services/smart_merge_helper.dart' show SmartMergeHelper;

// production-grade merge / smoothing / rotation policies (BYO Health Connect)
export 'src/policy/step_logic.dart'
    show StepLogic, StepMergeResult, StepRateLimiter;
export 'src/policy/merge_policy.dart'
    show MergePolicy, MergeInputs, MergeDecision;
export 'src/policy/hc_smoothing.dart'
    show HcSmoothingInputs, HcSmoothingDecision, smoothHcReading;
export 'src/policy/rotation_guard.dart'
    show RotationGuard, RotationInputs, RotationVerdict, RotationDecision;

// Widgets
export 'src/widgets/step_logs_viewer.dart' show StepLogsViewer;

import 'src/accurate_step_counter_impl.dart';

/// Main entry point for the accurate step counter plugin.
///
/// Prefer [AccurateStepCounterImpl.startTracking] for a one-call setup.
///
/// ```dart
/// final steps = AccurateStepCounter();
/// await steps.startTracking();
/// ```
class AccurateStepCounter extends AccurateStepCounterImpl {
  /// Creates a new instance of the step counter
  AccurateStepCounter();
}
