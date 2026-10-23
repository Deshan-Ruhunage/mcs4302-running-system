@REM Run before and after every condition: leave Doze, plug back in, make the app active again
@REM Change PKG if your package name differs.
@set PKG=com.example.mobile_client
adb shell dumpsys deviceidle unforce
adb shell dumpsys battery reset
adb shell am set-standby-bucket %PKG% active
adb shell dumpsys deviceidle get deep
adb shell am get-standby-bucket %PKG%
