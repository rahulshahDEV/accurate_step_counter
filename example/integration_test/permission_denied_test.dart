import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'denied activity permission fails before tracking or storage startup',
    (tester) async {
      final sdk = await const MethodChannel(
        'accurate_step_counter',
      ).invokeMethod<int>('getAndroidVersion');
      if (sdk == null || sdk < 29) {
        markTestSkipped(
          'Runtime activity permission is only required on API 29+.',
        );
        return;
      }
      final counter = AccurateStepCounter();
      try {
        expect(
          await counter.hasActivityRecognitionPermission(),
          isFalse,
          reason:
              'Revoke ACTIVITY_RECOGNITION before this suite (see example README).',
        );
        await expectLater(counter.startTracking(), throwsStateError);
        expect(counter.isStarted, isFalse);
        expect(counter.isLoggingInitialized, isFalse);
      } finally {
        await counter.dispose();
      }
    },
  );
}
