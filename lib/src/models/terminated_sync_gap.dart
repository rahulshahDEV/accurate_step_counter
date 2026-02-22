/// A terminated-state sync gap returned by the platform layer.
///
/// Represents a single "missed steps while app was terminated" window.
/// The [gapKey] and per-segment idempotency keys are deterministic so the
/// same gap can be processed exactly-once.
class TerminatedSyncGap {
  final int missedSteps;
  final DateTime startTime;
  final DateTime endTime;

  const TerminatedSyncGap({
    required this.missedSteps,
    required this.startTime,
    required this.endTime,
  });

  /// Stable identifier for this gap.
  String get gapKey {
    final startMs = startTime.toUtc().millisecondsSinceEpoch;
    final endMs = endTime.toUtc().millisecondsSinceEpoch;
    return '$startMs|$endMs|$missedSteps';
  }

  /// Prefix used to generate per-segment idempotency keys.
  String get idempotencyNamespace => 'terminated_gap|$gapKey';

  /// Split the gap into day-bounded segments with proportional step allocation.
  ///
  /// This mirrors the production day-splitting logic used for writing records.
  List<TerminatedSyncSegment> splitIntoDailySegments() {
    if (missedSteps <= 0) {
      return const [];
    }

    final totalDurationMs = endTime.difference(startTime).inMilliseconds;
    if (totalDurationMs <= 0) {
      return [
        TerminatedSyncSegment(
          index: 0,
          stepCount: missedSteps,
          fromTime: startTime,
          toTime: endTime,
          idempotencyKey: '$idempotencyNamespace|seg:0',
        ),
      ];
    }

    final segments = <TerminatedSyncSegment>[];
    var remainingSteps = missedSteps;
    var segmentIndex = 0;
    var currentStart = startTime;

    while (currentStart.isBefore(endTime)) {
      final currentDate = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day,
      );
      final nextDay = currentDate.add(const Duration(days: 1));
      final currentEnd = nextDay.isBefore(endTime) ? nextDay : endTime;

      final segmentDurationMs = currentEnd
          .difference(currentStart)
          .inMilliseconds;
      final proportion = segmentDurationMs / totalDurationMs;

      int segmentSteps;
      if (currentEnd == endTime) {
        segmentSteps = remainingSteps;
      } else {
        segmentSteps = (missedSteps * proportion).round();
        remainingSteps -= segmentSteps;
      }

      if (segmentSteps > 0) {
        segments.add(
          TerminatedSyncSegment(
            index: segmentIndex,
            stepCount: segmentSteps,
            fromTime: currentStart,
            toTime: currentEnd,
            idempotencyKey: '$idempotencyNamespace|seg:$segmentIndex',
          ),
        );
        segmentIndex++;
      }

      currentStart = currentEnd;
    }

    if (segments.isEmpty) {
      return [
        TerminatedSyncSegment(
          index: 0,
          stepCount: missedSteps,
          fromTime: startTime,
          toTime: endTime,
          idempotencyKey: '$idempotencyNamespace|seg:0',
        ),
      ];
    }

    return segments;
  }
}

/// One persisted record segment derived from a [TerminatedSyncGap].
class TerminatedSyncSegment {
  final int index;
  final int stepCount;
  final DateTime fromTime;
  final DateTime toTime;
  final String idempotencyKey;

  const TerminatedSyncSegment({
    required this.index,
    required this.stepCount,
    required this.fromTime,
    required this.toTime,
    required this.idempotencyKey,
  });
}
