package com.example.accurate_step_counter

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import java.util.Calendar
import java.util.TimeZone

internal class NativeStepPolicyTest {
    @Test fun dayDifferenceHandlesLeapAndYearBoundaries() {
        assertEquals(1, NativeStepPolicy.dayDifference(2024, 366, 2025, 1))
        assertEquals(3, NativeStepPolicy.dayDifference(2026, 200, 2026, 203))
        assertEquals(-1, NativeStepPolicy.dayDifference(2026, 200, 2026, 199))
    }

    @Test fun alarmUsesTheNextLocalDayAcrossAMidnightDstGap() {
        val zone = TimeZone.getTimeZone("America/Sao_Paulo")
        val now = Calendar.getInstance(zone).apply {
            clear()
            set(2018, Calendar.NOVEMBER, 3, 12, 0, 0)
        }.timeInMillis
        val next = Calendar.getInstance(zone).apply {
            timeInMillis = NativeStepPolicy.nextMidnight(now, zone)
        }
        assertEquals(4, next.get(Calendar.DAY_OF_MONTH))
        assertEquals(1, next.get(Calendar.HOUR_OF_DAY))
        assertEquals(5, next.get(Calendar.SECOND))
        assertTrue(next.timeInMillis > now)
    }

    @Test fun firstMidnightIsAllowedEvenAfterLateInstall() {
        assertTrue(NativeStepPolicy.canRotate(1000, 500000, 0, 0))
    }

    @Test fun restartDoesNotRestartRotationWindow() {
        val day = 24 * 60 * 60 * 1000L
        assertTrue(NativeStepPolicy.canRotate(day + 5000, day + 10000, 5000, 10000))
        assertFalse(NativeStepPolicy.canRotate(6000, 11000, 5000, 10000))
    }

    @Test fun rebootUsesPersistedWallGuard() {
        assertFalse(NativeStepPolicy.canRotate(1000, 15000, 100000, 10000))
        assertTrue(NativeStepPolicy.canRotate(1000, 100000000, 100000, 10000))
    }

    @Test fun migrationRetainsSeededSteps() {
        assertEquals(500, NativeStepPolicy.restoredOffset(800, 1000, 1300))
        assertEquals(800, NativeStepPolicy.restoredOffset(800, null, -1))
    }

    @Test fun counterRecoveryDoesNotRequireDetectorEventsFromDeadProcess() {
        assertFalse(NativeStepPolicy.detectorMismatch(1000, 0, 5000, 4000, true))
        assertFalse(NativeStepPolicy.detectorMismatch(10, 0, 5000, 0, false))
        assertTrue(NativeStepPolicy.detectorMismatch(10, 0, 5000, 4000, false))
    }

    @Test fun recoveryAllowanceScalesWithGapInsteadOfCappingWholeGapAt180() {
        assertEquals(9180, NativeStepPolicy.recoveryAllowance(3600000))
        assertEquals(80000, NativeStepPolicy.recoveryAllowance(Long.MAX_VALUE / 1000))
    }

    @Test fun aScreenOffTenMinuteBatchRetainsLegitimateStepsAndBoundsSpikes() {
        assertEquals(900, NativeStepPolicy.admitRecovery(900, 600000, 9000, 180))
        assertEquals(1680, NativeStepPolicy.admitRecovery(100000, 600000, 9000, 180))
    }
}
