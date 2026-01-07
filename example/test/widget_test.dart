// Basic Flutter widget test for the Step Counter Test App

import 'package:flutter_test/flutter_test.dart';

import 'package:accurate_step_counter_example/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const StepCounterTestApp());

    // Verify that the stats card is displayed
    expect(find.text('Start with Preset:'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
  });
}
