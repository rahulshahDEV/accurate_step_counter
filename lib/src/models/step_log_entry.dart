import 'package:hive/hive.dart';

import 'step_log_source.dart';

part 'step_log_entry.g.dart';

/// A single step log entry stored in the local Hive database
///
/// This model represents a batch of steps recorded during a specific
/// time period, along with metadata about the source and confidence.
///
/// Example:
/// ```dart
/// final entry = StepLogEntry(
///   stepCount: 150,
///   fromTime: startOfWalk,
///   toTime: endOfWalk,
///   source: StepLogSource.foreground,
///   confidence: 0.95,
/// );
/// ```
@HiveType(typeId: 0)
class StepLogEntry extends HiveObject {
  /// Number of steps recorded in this entry
  @HiveField(0)
  final int stepCount;

  /// Start time of the recording period
  @HiveField(1)
  final DateTime fromTime;

  /// End time of the recording period
  @HiveField(2)
  final DateTime toTime;

  /// Source indicating app state when steps were recorded
  @HiveField(3)
  final StepLogSource source;

  /// Name of the step counter source
  ///
  /// Always "accurate_step_counter" for entries from this plugin
  @HiveField(4)
  final String sourceName;

  /// Confidence level of the detection (0.0 to 1.0)
  ///
  /// Higher values indicate more reliable step counting
  @HiveField(5)
  final double confidence;

  /// Creates a new step log entry
  StepLogEntry({
    required this.stepCount,
    required this.fromTime,
    required this.toTime,
    required this.source,
    this.sourceName = 'accurate_step_counter',
    this.confidence = 1.0,
  }) : assert(stepCount >= 0, 'Step count must be non-negative'),
       assert(
         confidence >= 0.0 && confidence <= 1.0,
         'Confidence must be between 0.0 and 1.0',
       );

  /// Duration of the recording period
  Duration get duration => toTime.difference(fromTime);

  /// Steps per minute during this recording period
  double get stepsPerMinute {
    final minutes = duration.inSeconds / 60.0;
    if (minutes <= 0) return 0;
    return stepCount / minutes;
  }

  /// Creates a copy with the given fields replaced
  StepLogEntry copyWith({
    int? stepCount,
    DateTime? fromTime,
    DateTime? toTime,
    StepLogSource? source,
    String? sourceName,
    double? confidence,
  }) {
    return StepLogEntry(
      stepCount: stepCount ?? this.stepCount,
      fromTime: fromTime ?? this.fromTime,
      toTime: toTime ?? this.toTime,
      source: source ?? this.source,
      sourceName: sourceName ?? this.sourceName,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() {
    return 'StepLogEntry(stepCount: $stepCount, from: $fromTime, to: $toTime, '
        'source: $source, confidence: $confidence)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is StepLogEntry &&
        other.stepCount == stepCount &&
        other.fromTime == fromTime &&
        other.toTime == toTime &&
        other.source == source &&
        other.sourceName == sourceName &&
        other.confidence == confidence;
  }

  @override
  int get hashCode {
    return stepCount.hashCode ^
        fromTime.hashCode ^
        toTime.hashCode ^
        source.hashCode ^
        sourceName.hashCode ^
        confidence.hashCode;
  }
}
