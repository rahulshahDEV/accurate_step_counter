package com.example.accurate_step_counter

import android.content.ContextWrapper
import android.content.SharedPreferences
import org.mockito.Mockito.*
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals

internal class NativeColdRotationTest {
    @Test fun alarmInFreshProcessRestoresCountersBeforeRotating() {
        val values = mutableMapOf<String, Any?>()
        val prefs = mock(SharedPreferences::class.java)
        val editor = mock(SharedPreferences.Editor::class.java)
        val context = object : ContextWrapper(null) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences = prefs
        }
        `when`(prefs.edit()).thenReturn(editor)
        `when`(prefs.contains(anyString())).thenAnswer { values.containsKey(it.getArgument<String>(0)) }
        `when`(prefs.getInt(anyString(), anyInt())).thenAnswer { values[it.getArgument<String>(0)] as? Int ?: it.getArgument<Int>(1) }
        `when`(prefs.getLong(anyString(), anyLong())).thenAnswer { values[it.getArgument<String>(0)] as? Long ?: it.getArgument<Long>(1) }
        `when`(prefs.getBoolean(anyString(), anyBoolean())).thenAnswer { values[it.getArgument<String>(0)] as? Boolean ?: it.getArgument<Boolean>(1) }
        `when`(editor.putInt(anyString(), anyInt())).thenAnswer {
            values[it.getArgument<String>(0)] = it.getArgument<Int>(1); editor
        }
        `when`(editor.putLong(anyString(), anyLong())).thenAnswer {
            values[it.getArgument<String>(0)] = it.getArgument<Long>(1); editor
        }
        `when`(editor.putBoolean(anyString(), anyBoolean())).thenAnswer {
            values[it.getArgument<String>(0)] = it.getArgument<Boolean>(1); editor
        }
        `when`(editor.putString(anyString(), anyString())).thenAnswer {
            values[it.getArgument<String>(0)] = it.getArgument<String>(1); editor
        }
        `when`(editor.clear()).thenAnswer { values.clear(); editor }

        // Simulate companion defaults in a new process, with yesterday's valid
        // persisted state still on disk. No Service instance is constructed.
        StepCounterService.resetState(context)
        val oldDay = Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, -1) }
        values["last_reset_year"] = oldDay.get(Calendar.YEAR)
        values["last_reset_day"] = oldDay.get(Calendar.DAY_OF_YEAR)
        values["today_steps"] = 2345
        values["yesterday_steps"] = 1234
        values["tracking_enabled"] = true

        StepCounterService.performMidnightReset(context)

        assertEquals(0, values["today_steps"])
        assertEquals(2345, values["yesterday_steps"])
        assertEquals(1234, values["day_before_steps"])
        assertEquals(2345, values["last_rotation_prev_today"])
        assertEquals(SimpleDateFormat("yyyy-MM-dd", Locale.US).format(oldDay.time), values["rotation_previous_date"])
    }
}
