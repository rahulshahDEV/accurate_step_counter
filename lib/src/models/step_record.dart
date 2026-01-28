import 'step_record_source.dart';

/// A record of steps taken during a time period
///
/// Similar to Health Connect's StepsRecord, this captures step data
/// with start/end times and source information.
class StepRecord {
  /// Database ID (null for new records)
  final int? id;

  /// Number of steps in this record
  final int stepCount;

  /// Start time of this record period
  final DateTime fromTime;

  /// End time of this record period
  final DateTime toTime;

  /// Source of the step data
  final StepRecordSource source;

  /// Detection confidence (0.0 - 1.0, if available)
  final double? confidence;

  StepRecord({
    this.id,
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

  /// Create a StepRecord from a database map
  factory StepRecord.fromMap(Map<String, dynamic> map) {
    return StepRecord(
      id: map['id'] as int?,
      stepCount: map['step_count'] as int,
      fromTime: DateTime.fromMillisecondsSinceEpoch(
        map['from_time'] as int,
        isUtc: true,
      ).toLocal(),
      toTime: DateTime.fromMillisecondsSinceEpoch(
        map['to_time'] as int,
        isUtc: true,
      ).toLocal(),
      source: StepRecordSource.values[map['source'] as int],
      confidence: map['confidence'] as double?,
    );
  }

  /// Convert to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'step_count': stepCount,
      'from_time': fromTime.toUtc().millisecondsSinceEpoch,
      'to_time': toTime.toUtc().millisecondsSinceEpoch,
      'source': source.index,
      'confidence': confidence,
    };
  }

  /// Create a copy with modified fields
  StepRecord copyWith({
    int? id,
    int? stepCount,
    DateTime? fromTime,
    DateTime? toTime,
    StepRecordSource? source,
    double? confidence,
  }) {
    return StepRecord(
      id: id ?? this.id,
      stepCount: stepCount ?? this.stepCount,
      fromTime: fromTime ?? this.fromTime,
      toTime: toTime ?? this.toTime,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() {
    return 'StepRecord(steps: $stepCount, from: $fromTime, to: $toTime, source: $source)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StepRecord &&
        other.stepCount == stepCount &&
        other.fromTime == fromTime &&
        other.toTime == toTime &&
        other.source == source &&
        other.confidence == confidence;
  }

  @override
  int get hashCode {
    return stepCount.hashCode ^
        fromTime.hashCode ^
        toTime.hashCode ^
        source.hashCode ^
        confidence.hashCode;
  }
}

// Backwards compatibility
@Deprecated('Use StepRecord instead')
typedef StepLogEntry = StepRecord;
