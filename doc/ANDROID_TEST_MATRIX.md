# Android acceptance matrix

## Evidence levels

- **Automated**: deterministic Dart or JVM tests with fake inputs; proves the
  tested rule, not the physical sensor or OEM background behavior.
- **Built**: Android example compiled; proves build/toolchain compatibility.
- **Device verified**: scenario executed on a named physical device with OS,
  firmware, permission state, settings, and observed counts recorded.
- **User reported**: manual behavior observed by the tester; exact counts and
  test conditions were not captured, so accuracy is not quantified.
- **Pending**: no device evidence collected.

## Platform coverage to exercise

| Platform | Main checks | Physical result in this change |
| --- | --- | --- |
| API 24–25 | No NotificationChannel calls, foreground-service start compatibility | Pending |
| API 26–28 | Notification channel and foreground-service deadline | Pending |
| API 29–32 | Activity permission granted/denied/revoked; foreground start restrictions | Pending |
| API 33 | Notification allowed/denied; ongoing service and raw step access | Pending |
| API 34 | Health foreground-service permission/type and visible startup | Samsung SM-A235F: automated runtime tests passed; foreground/background/terminated tracking reported working by user; measured accuracy pending |
| API 35–36 | Health service across background/boot; no data-sync fallback | Pending |
| No counter sensor | Capability result and clearly limited legacy fallback | Pending |
| No Play Services | Counting works; vehicle filter soft-disabled | Pending |

## OEM sampling

Prioritize actual hardware rather than treating brands as compatible by name.
For each row record at least one budget and one recent device when possible.

| Device family | Additional settings/scenarios | Result |
| --- | --- | --- |
| Pixel / AOSP | Reference baseline, Doze, boot, delayed sensor batches | Pending |
| Samsung (including A-series) | Sensor drift/cadence, deep sleep, battery restriction | Galaxy A23 runtime integration checks passed; foreground/background/terminated tracking reported working by user; accuracy and extended power tests pending |
| Xiaomi / Redmi / POCO | Auto-start, unrestricted battery, recents swipe | Pending |
| OPPO / Realme | Background launch management, screen-off and reboot | Pending |
| Vivo / iQOO | Auto-start and background power controls | Pending |
| Motorola / OnePlus / other available phones | Repeat common acceptance scenarios | Pending |
| Huawei without GMS | Counter available; no crash when classifier unavailable | Pending |

## Scenario protocol

Record device/model, Android API, build fingerprint, app/package versions, detector
mode, permissions, battery/auto-start settings, start/end times, and raw, stored,
aggregate, and displayed totals. Use manually counted walks as the reference;
Google Fit/Health Connect can lag or duplicate sources and is not ground truth.

1. Fresh install before permissions: clear failure and no crash; grant and retry.
2. Count a 200-step normal walk in foreground, pocket, and hand. Record absolute
   and percentage error; choose product-specific acceptance limits in advance.
3. Repeat slowly, with short stop/start walks, stairs, and with the running preset
   at faster cadence. Ensure configured caps match the intended activity.
4. Sit/shake, drive or take transit, and cycle. Record false positives and any
   false suppression during the first minute after leaving a vehicle.
5. Screen off for 30–60 minutes, walk, then resume. Compare native, SQLite, and UI;
   allow the hardware's documented batching latency before final comparison.
6. Swipe recents, repeat a walk, reopen. Repeat with default and unrestricted
   battery settings; report OEM differences instead of assuming service survival.
7. Kill the process without force-stopping, walk, reopen. Test repeated equal-sized
   recovery gaps, and verify offsets/counters remain continuous.
8. Stay across local midnight with/without steps. Check notification, today,
   yesterday, history, streams, and no old-day floor on the new day.
9. Restart the process shortly before midnight. Repeat after two or more days away;
   historical counts must remain anchored to their original date.
10. Reboot with tracking enabled, repeat walking. Then stop tracking or log out,
    reboot, and confirm tracking stays disabled.
11. Force-stop: confirm it stays stopped until manually opened. Do not classify
    Android's force-stop behavior as automatic background recovery.
12. Revoke activity permission or notifications in Settings, resume, and retry
    after re-granting. No service crash or false success state should result.
13. Deny exact alarms; verify eventual rollover on sensor update/resume and record
    the delay. Change time zone across a date and test DST/year boundaries.
14. Use two today subscriptions; cancel one, confirm the other still updates.
15. Stop/restart repeatedly, import distinct external intervals, and switch users.
    No duplicate stored increments or activity inherited by the new user.

## Current verification

The connected Samsung Galaxy A23 (SM-A235F), Android 14 / API 34, firmware
A235FXXSEEZB1, exposes both hardware step-counter and step-detector sensors.
Tests ran in a dedicated debug QA app so existing app data was unaffected.
Hardware service startup, concurrent/repeated startup, stop/restart, logout
cleanup, and rejection of startup with activity permission denied passed.
All three tracking lifecycle tests also passed with notification permission
denied while activity permission remained granted.
SQLite isolate persistence, independently observed totals, idempotent writes,
point records, and close/reopen passed. The user subsequently tried foreground,
background, and terminated states on this phone and reported that tracking
appeared to work in all three. Exact manual step counts, duration, battery
settings, and the termination method were not supplied. This is qualitative
device evidence; it does not establish force-stop recovery or a measured error
rate. Counted walks, controlled screen-off/process-death tests, overnight
behavior, and reboot remain pending.

A read-only `Medium_Phone` emulator on API 37 passed background SQLite
isolate write/watch/close/reopen and three tracking startup/stop/logout tests. The
emulator reported no hardware step counter, so tracking used the legacy fallback.
These results do not validate hardware-counter accuracy or OEM background behavior.
The package verification results are recorded below.
The package cannot guarantee uninterrupted counting when the service/sensor is
inactive, exact time attribution for an unobserved multi-day sensor gap, or
identical accuracy across different sensor firmware.

| Check | Result on 2026-10-25 |
| --- | --- |
| Flutter analysis | No issues |
| Dart tests | 1,005 passed; 3 intentionally skipped |
| JVM tests | 11 passed, including cold-process rotation, offset restore, delayed batches, cadence, and calendar boundaries |
| Android module lint | Passed with 0 errors; dependency/style warnings remain |
| Android debug example | Built successfully |
| Android release example | Built successfully (45.8 MB) |
| API 37 emulator | 1 real database-isolate test and 3 tracking lifecycle tests passed; no hardware counter available |
| Samsung Galaxy A23, API 34 | 3 tracking lifecycle tests passed with notifications granted and again denied; 1 SQLite isolate test and 1 denied-activity-permission test passed |
| Samsung manual state checks | User reported foreground, background, and terminated tracking working; counts and termination method not recorded |
| Physical walking/OEM accuracy | Pending; runtime integration success does not measure step error |

### Connected-device walk log

The dedicated QA app started with today/native/SQLite totals of **0 / 0 / 0**
and the native service running. A manually counted 200-step foreground walk
has been requested. The first observed settled totals were **21 / 21 / 21**
while the app was resumed and the native service was running; the UI-facing
query, native persistence, and SQLite agreed. The manual reference count has
not yet been supplied, so this establishes count consistency, not accuracy.
No walking accuracy percentage is recorded until the manual reference count
and final settled totals are available.

Platform references: [Android motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion),
[foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types),
and [background service start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).
