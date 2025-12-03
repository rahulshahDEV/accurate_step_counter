import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'accurate_step_counter_platform_interface.dart';

/// An implementation of [AccurateStepCounterPlatform] that uses method channels.
///
/// NOTE: This is legacy boilerplate from the Flutter plugin template.
/// The actual step counter implementation uses [StepCounterPlatform] directly
/// (see src/platform/step_counter_platform.dart).
///
/// This class is kept for compatibility with the plugin platform interface
/// structure but is not used in the actual plugin functionality.
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
