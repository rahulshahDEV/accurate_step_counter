import 'package:accurate_step_counter/src/platform/step_counter_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native listeners share a channel and one cancellation keeps the other alive',
    () async {
      const name = 'accurate_step_counter/native_step_service_events';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var listens = 0;
      var cancels = 0;
      messenger.setMockMethodCallHandler(const MethodChannel(name), (
        call,
      ) async {
        if (call.method == 'listen') listens++;
        if (call.method == 'cancel') cancels++;
        return null;
      });
      final firstValues = <int>[];
      final secondValues = <int>[];
      final first = StepCounterPlatform.instance.nativeStepServiceStream.listen(
        firstValues.add,
      );
      final second = StepCounterPlatform.instance.nativeStepServiceStream
          .listen(secondValues.add);
      await Future<void>.delayed(Duration.zero);
      expect(listens, 1);

      Future<void> send(int value) async {
        await messenger.handlePlatformMessage(
          name,
          const StandardMethodCodec().encodeSuccessEnvelope(value),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      await send(5);
      await first.cancel();
      expect(cancels, 0);
      await send(6);
      expect(firstValues, [5]);
      expect(secondValues, [5, 6]);
      await second.cancel();
      expect(cancels, 1);
      messenger.setMockMethodCallHandler(const MethodChannel(name), null);
    },
  );
}
