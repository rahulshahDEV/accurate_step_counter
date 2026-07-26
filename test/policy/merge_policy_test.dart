import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/src/policy/merge_policy.dart';

/// MergePolicy is a thin facade over the existing StepLogic primitives that
/// already have 105 unit tests of their own. These tests verify the facade
/// delegates correctly and exposes the right fields on the decision DTO.
void main() {
  const policy = MergePolicy();

  group('MergePolicy.mergeToday', () {
    test('delegates to StepLogic: healthy device, HC + sensor agree', () {
      final r = policy.mergeToday(const MergeInputs(
        hcSteps: 5000,
        sensorSteps: 5000,
        currentFloor: 0,
        serverRecovered: 0,
      ));
      expect(r.displayed, 5000);
      expect(r.overcountingDetected, false);
      expect(r.hcDuplicationDetected, false);
    });

    test('exposes overcountingDetected when sensor 19% above HC', () {
      final r = policy.mergeToday(const MergeInputs(
        hcSteps: 100,
        sensorSteps: 119,
        currentFloor: 0,
        serverRecovered: 0,
      ));
      expect(r.displayed, 100);
      expect(r.overcountingDetected, true);
      expect(r.hcDuplicationDetected, false);
    });

    test('exposes hcDuplicationDetected when HC is 2x sensor', () {
      final r = policy.mergeToday(const MergeInputs(
        hcSteps: 5412,
        sensorSteps: 2600,
        currentFloor: 2600,
        serverRecovered: 0,
      ));
      expect(r.displayed, 2600);
      expect(r.hcDuplicationDetected, true);
      expect(r.overcountingDetected, false);
    });

    test('floor + serverRecovered propagated to decision', () {
      final r = policy.mergeToday(const MergeInputs(
        hcSteps: 0,
        sensorSteps: 100,
        currentFloor: 200,
        serverRecovered: 500,
      ));
      expect(r.displayed, 500);
      expect(r.newFloor, 500);
      expect(r.newServerRecovered, 500);
    });
  });

  group('MergePolicy.mergeYesterday', () {
    test('HC > 0 wins by default', () {
      expect(
        policy.mergeYesterday(
            hcYesterday: 4500, sensorYesterday: 3000, currentYesterday: 0),
        4500,
      );
    });

    test('HC duplication detection kicks in for yesterday too', () {
      // ratio 2.0 in [1.5, 2.5) duplication band
      expect(
        policy.mergeYesterday(
            hcYesterday: 10000, sensorYesterday: 5000, currentYesterday: 5000),
        5000,
      );
    });

    test('asymmetric stability lock: blocks upward drift past 30%', () {
      expect(
        policy.mergeYesterday(
            hcYesterday: 16308,
            sensorYesterday: 16308,
            currentYesterday: 10619),
        10619,
      );
    });

    test('asymmetric stability lock: allows downward correction', () {
      expect(
        policy.mergeYesterday(
            hcYesterday: 5000,
            sensorYesterday: 5000,
            currentYesterday: 10619),
        5000,
      );
    });

    test('both zero, currentYesterday holds', () {
      expect(
        policy.mergeYesterday(
            hcYesterday: 0, sensorYesterday: 0, currentYesterday: 8000),
        8000,
      );
    });
  });

  group('MergePolicy.sanitizeServerSteps', () {
    test('negative becomes 0', () {
      expect(policy.sanitizeServerSteps(-100), 0);
    });

    test('over 80000 becomes 0', () {
      expect(policy.sanitizeServerSteps(99999), 0);
    });

    test('within range passes through', () {
      expect(policy.sanitizeServerSteps(50000), 50000);
    });

    test('exactly 80000 passes through', () {
      expect(policy.sanitizeServerSteps(80000), 80000);
    });
  });
}
