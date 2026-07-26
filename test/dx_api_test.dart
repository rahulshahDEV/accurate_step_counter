import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartMergeHelper DX', () {
    test('merge returns production decision not naive max', () {
      // Sensor overcount vs HC → trust HC
      final d = SmartMergeHelper.merge(
        sensorSteps: 11461,
        healthConnectSteps: 6360,
        currentDisplayed: 0,
      );
      expect(d.displayed, 6360);
      expect(d.overcountingDetected, isTrue);
    });

    test('mergeStepCounts matches merge().displayed', () {
      final displayed = SmartMergeHelper.mergeStepCounts(
        sensorSteps: 2600,
        healthConnectSteps: 5412, // HC duplication band
      );
      expect(displayed, 2600);
    });
  });

  group('Public API surface', () {
    test('AccurateStepCounter exposes startTracking and battery aliases', () {
      final steps = AccurateStepCounter();
      expect(steps.startTracking, isA<Function>());
      expect(steps.isBatteryOptimized, isA<Function>());
      expect(steps.requestBatteryOptimization, isA<Function>());
      expect(steps.getTodayStepCount, isA<Function>());
      expect(steps.getTodaySteps, isA<Function>());
    });
  });
}
