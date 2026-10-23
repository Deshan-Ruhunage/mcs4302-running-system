@REM Part 4 (J2): move Doze to its next state; repeat until IDLE_MAINTENANCE
@REM Change PKG if your package name differs.
@set PKG=com.example.mobile_client
adb shell dumpsys deviceidle step
adb shell dumpsys deviceidle get deep
