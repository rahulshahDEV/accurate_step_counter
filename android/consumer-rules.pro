# Keep step-counter entry points when host apps enable R8/ProGuard.
-keep class com.example.accurate_step_counter.StepCounterService { *; }
-keep class com.example.accurate_step_counter.StepCounterForegroundService { *; }
-keep class com.example.accurate_step_counter.AccurateStepCounterPlugin { *; }
-keep class com.example.accurate_step_counter.BootReceiver { *; }
-keep class com.example.accurate_step_counter.MidnightReceiver { *; }
-keep class com.example.accurate_step_counter.TimeChangeReceiver { *; }
-keep class com.example.accurate_step_counter.ActivityTransitionReceiver { *; }
-keep class com.example.accurate_step_counter.ActivityClassifier { *; }
-keep class com.example.accurate_step_counter.NativeStepDetector { *; }
