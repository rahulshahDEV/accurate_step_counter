/// Represents a step detection event
///
/// This event is emitted whenever a step is detected by the accelerometer algorithm.
class StepCountEvent {
  /// The total number of steps detected since tracking started
  final int stepCount;

  /// The timestamp when this step was detected
  final DateTime timestamp;

  /// Confidence level of the detection (0.0 to 1.0)
  /// Higher values indicate more confidence that this was a real step
  final double confidence;

  /// Creates a new step count event
  const StepCountEvent({
    required this.stepCount,
    required this.timestamp,
    this.confidence = 1.0,
  }) : assert(confidence >= 0.0 && confidence <= 1.0,
            'Confidence must be between 0.0 and 1.0');

  /// Creates a copy of this event with the given fields replaced
  StepCountEvent copyWith({
    int? stepCount,
    DateTime? timestamp,
    double? confidence,
  }) {
    return StepCountEvent(
      stepCount: stepCount ?? this.stepCount,
      timestamp: timestamp ?? this.timestamp,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() {
    return 'StepCountEvent(stepCount: $stepCount, timestamp: $timestamp, confidence: $confidence)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is StepCountEvent &&
        other.stepCount == stepCount &&
        other.timestamp == timestamp &&
        other.confidence == confidence;
  }

  @override
  int get hashCode {
    return stepCount.hashCode ^ timestamp.hashCode ^ confidence.hashCode;
  }
}
