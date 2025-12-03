import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelAccurateStepCounter platform = MethodChannelAccurateStepCounter();
  const MethodChannel channel = MethodChannel('accurate_step_counter');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
