import 'dart:io';

import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late AccurateStepCounter counter;

  setUpAll(() async {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'Android tracking integration suite',
    );
    final probe = AccurateStepCounter();
    expect(
      await probe.hasActivityRecognitionPermission(),
      isTrue,
      reason:
          'Grant ACTIVITY_RECOGNITION before this suite (see example README).',
    );
    await probe.dispose();
  });

  setUp(() => counter = AccurateStepCounter());
  tearDown(() => counter.dispose());

  testWidgets('complete startup is repeatable and exposes real detector mode', (
    tester,
  ) async {
    await Future.wait([counter.startTracking(), counter.startTracking()]);
    await counter.startTracking();
    expect(counter.isStarted, isTrue);
    expect(counter.isLoggingInitialized, isTrue);
    expect(counter.isLoggingEnabled, isTrue);
    expect(await counter.watchTodaySteps().first, greaterThanOrEqualTo(0));
    expect(
      await counter.watchAggregatedStepCounter().first,
      greaterThanOrEqualTo(0),
    );
    final hardware = await counter.hasNativeStepServiceSensor();
    debugPrint(
      'Hardware counter available: $hardware; native service selected: ${counter.isUsingNativeStepService}',
    );
    if (hardware) {
      expect(counter.isUsingNativeStepService, isTrue);
      expect(await counter.isNativeStepServiceRunning(), isTrue);
    }
  });

  testWidgets('stop flushes storage and the complete pipeline can restart', (
    tester,
  ) async {
    await counter.startTracking();
    await counter.stop();
    expect(counter.isStarted, isFalse);
    expect(counter.isLoggingEnabled, isFalse);
    await counter.startTracking();
    expect(counter.isStarted, isTrue);
    expect(await counter.getTodayStepCount(), greaterThanOrEqualTo(0));
  });

  testWidgets('logout sequence clears stored data and stops native tracking', (
    tester,
  ) async {
    await counter.startTracking();
    await counter.stop();
    await counter.clearStepLogs();
    await counter.resetNativeStepState();
    expect(await counter.getTotalSteps(), 0);
    expect(await counter.isNativeStepServiceRunning(), isFalse);
    await counter.startTracking();
    expect(counter.isStarted, isTrue);
  });
}
