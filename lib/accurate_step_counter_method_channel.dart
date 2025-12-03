import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'accurate_step_counter_platform_interface.dart';

/// An implementation of [AccurateStepCounterPlatform] that uses method channels.
class MethodChannelAccurateStepCounter extends AccurateStepCounterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('accurate_step_counter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
