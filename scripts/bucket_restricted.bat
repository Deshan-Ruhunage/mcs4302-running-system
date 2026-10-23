@REM Part 4 (J4): on battery, put the app in the RESTRICTED standby bucket (run AFTER pressing Home)
@REM Change PKG if your package name differs.
@set PKG=com.example.mobile_client
adb shell dumpsys battery unplug
adb shell am set-standby-bucket %PKG% restricted
adb shell am get-standby-bucket %PKG%
