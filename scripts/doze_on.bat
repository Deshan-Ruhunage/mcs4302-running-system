@REM Part 4 (J2): pretend the device is on battery, then force it into deep Doze
@REM Change PKG if your package name differs.
@set PKG=com.example.mobile_client
adb shell dumpsys battery unplug
adb shell dumpsys deviceidle force-idle
adb shell dumpsys deviceidle get deep
