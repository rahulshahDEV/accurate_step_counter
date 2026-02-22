// Basic Flutter widget test for the Step Counter Test App

import 'package:flutter_test/flutter_test.dart';

import 'package:accurate_step_counter_example/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const StepCounterApp());

    // Verify that core UI sections are visible
    expect(find.text('Accurate Step Counter'), findsOneWidget);
    expect(find.text('Today\'s Steps'), findsOneWidget);
    expect(find.text('Run Setup Verification'), findsOneWidget);
  });
}
