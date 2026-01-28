import 'step_log_source.dart';

/// A single step log entry stored in the local database
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
@Deprecated('Use StepRecord instead')
class StepLogEntry {
  /// Database ID (null for new records)
  final int? id;

  /// Number of steps recorded in this entry
  final int stepCount;

  /// Start time of the recording period
  final DateTime fromTime;

  /// End time of the recording period
  final DateTime toTime;

  /// Source indicating app state when steps were recorded
  // ignore: deprecated_member_use_from_same_package
  final StepLogSource source;

  /// Name of the step counter source
  ///
  /// Always "accurate_step_counter" for entries from this plugin
  final String sourceName;

  /// Confidence level of the detection (0.0 to 1.0)
  ///
  /// Higher values indicate more reliable step counting
  final double confidence;

  /// Creates a new step log entry
  StepLogEntry({
    this.id,
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

  /// Create a StepLogEntry from a database map
  factory StepLogEntry.fromMap(Map<String, dynamic> map) {
    return StepLogEntry(
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
      // ignore: deprecated_member_use_from_same_package
      source: StepLogSource.values[map['source'] as int],
      sourceName: map['source_name'] as String? ?? 'accurate_step_counter',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
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
      'source_name': sourceName,
      'confidence': confidence,
    };
  }

  /// Creates a copy with the given fields replaced
  StepLogEntry copyWith({
    int? id,
    int? stepCount,
    DateTime? fromTime,
    DateTime? toTime,
    // ignore: deprecated_member_use_from_same_package
    StepLogSource? source,
    String? sourceName,
    double? confidence,
  }) {
    return StepLogEntry(
      id: id ?? this.id,
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
