import 'package:hive/hive.dart';

import 'step_record_source.dart';

part 'step_record.g.dart';

/// A record of steps taken during a time period
///
/// Similar to Health Connect's StepsRecord, this captures step data
/// with start/end times and source information.
@HiveType(typeId: 1)
class StepRecord extends HiveObject {
  /// Number of steps in this record
  @HiveField(0)
  final int stepCount;

  /// Start time of this record period
  @HiveField(1)
  final DateTime fromTime;

  /// End time of this record period
  @HiveField(2)
  final DateTime toTime;

  /// Source of the step data
  @HiveField(3)
  final StepRecordSource source;

  /// Detection confidence (0.0 - 1.0, if available)
  @HiveField(4)
  final double? confidence;

  StepRecord({
    required this.stepCount,
    required this.fromTime,
    required this.toTime,
    required this.source,
    this.confidence,
  });

  /// Duration of this record in milliseconds
  int get durationMs => toTime.difference(fromTime).inMilliseconds;

  /// Steps per second rate
  double get stepsPerSecond {
    final seconds = durationMs / 1000.0;
    return seconds > 0 ? stepCount / seconds : 0;
  }

  @override
  String toString() {
    return 'StepRecord(steps: $stepCount, from: $fromTime, to: $toTime, source: $source)';
  }
}

// Backwards compatibility
@Deprecated('Use StepRecord instead')
typedef StepLogEntry = StepRecord;
