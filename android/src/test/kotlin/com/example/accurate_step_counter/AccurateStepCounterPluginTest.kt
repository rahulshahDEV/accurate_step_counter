package com.example.accurate_step_counter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

/**
 * Smoke test for MethodChannel dispatch. Full sensor / FGS behavior is covered
 * by Dart policy tests and device QA — this only asserts unknown methods are
 * reported as notImplemented so regressions in the when-branch are caught.
 */
internal class AccurateStepCounterPluginTest {
    @Test
    fun onMethodCall_unknownMethod_reportsNotImplemented() {
        val plugin = AccurateStepCounterPlugin()
        val call = MethodCall("getPlatformVersion", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).notImplemented()
    }
}
