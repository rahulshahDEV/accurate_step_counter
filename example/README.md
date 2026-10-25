# Android step counter example

Demonstrates `accurate_step_counter` 4.x on Android API 24+.

```sh
flutter pub get
flutter run
```

Use a physical phone with `TYPE_STEP_COUNTER` for accuracy tests. Grant activity
recognition and notifications when prompted, then enable unrestricted battery or
OEM auto-start if you need overnight tracking.

The example uses `startTracking()` with automatic lifecycle handling and shows
live today/aggregate values, raw events, source statistics, foreground-service
status, battery settings, and verification/warmup pages. iOS tracking is not
supported.

For the Android integration suite, install the debug APK with runtime permissions
before starting the tracking tests:

```sh
flutter build apk --debug
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk
flutter test integration_test/plugin_integration_test.dart -d <device-id>
flutter test integration_test/database_isolate_test.dart -d <device-id>
```

The tracking suite fails clearly when activity permission has not been granted.
The isolate test does not require sensor permission.

On API 29+ the denied-permission check can be run separately:

```sh
adb shell pm revoke com.example.accurate_step_counter_example android.permission.ACTIVITY_RECOGNITION
flutter test integration_test/permission_denied_test.dart -d <device-id>
```

Grant activity permission again before running the normal tracking suite.

Follow [the acceptance matrix](../doc/ANDROID_TEST_MATRIX.md) before claiming a
phone or OS version is verified. An emulator build or green unit tests do not
establish physical step accuracy.
