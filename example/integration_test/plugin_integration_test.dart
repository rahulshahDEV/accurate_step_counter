// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:accurate_step_counter/accurate_step_counter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AccurateStepCounter stepCounter;

  setUp(() {
    stepCounter = AccurateStepCounter();
  });

  tearDown(() async {
    await stepCounter.dispose();
  });

  testWidgets('step counter can start and stop', (WidgetTester tester) async {
    // Test starting
    await stepCounter.start();
    expect(stepCounter.isStarted, true);
    expect(stepCounter.currentConfig, isNotNull);

    // Wait a bit
    await tester.pump(const Duration(seconds: 1));

    // Test stopping
    await stepCounter.stop();
    expect(stepCounter.isStarted, false);
  });

  testWidgets('step counter can be reset', (WidgetTester tester) async {
    await stepCounter.start();

    // Reset counter
    stepCounter.reset();
    expect(stepCounter.currentStepCount, 0);

    await stepCounter.stop();
  });

  testWidgets('step counter with custom config', (WidgetTester tester) async {
    final config = StepDetectorConfig.walking();

    await stepCounter.start(config: config);
    expect(stepCounter.isStarted, true);
    expect(stepCounter.currentConfig, isNotNull);
    expect(stepCounter.currentConfig?.threshold, config.threshold);

    await stepCounter.stop();
  });

  testWidgets('step counter stream emits events', (WidgetTester tester) async {
    final subscription = stepCounter.stepEventStream.listen((event) {
      // Verify event structure
      expect(event.stepCount, greaterThanOrEqualTo(0));
    });

    await stepCounter.start();
    await tester.pump(const Duration(seconds: 2));
    await stepCounter.stop();

    await subscription.cancel();

    // Note: No steps may be detected in an automated test environment
    // This test verifies the stream works, not that steps are actually detected
  });
}
