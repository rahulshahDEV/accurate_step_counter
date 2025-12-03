import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'accurate_step_counter_method_channel.dart';

abstract class AccurateStepCounterPlatform extends PlatformInterface {
  /// Constructs a AccurateStepCounterPlatform.
  AccurateStepCounterPlatform() : super(token: _token);

  static final Object _token = Object();

  static AccurateStepCounterPlatform _instance = MethodChannelAccurateStepCounter();

  /// The default instance of [AccurateStepCounterPlatform] to use.
  ///
  /// Defaults to [MethodChannelAccurateStepCounter].
  static AccurateStepCounterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AccurateStepCounterPlatform] when
  /// they register themselves.
  static set instance(AccurateStepCounterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
