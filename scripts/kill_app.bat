@REM Part 2: kill the app process (the app must be in the background)
@REM Change PKG if your package name differs.
@set PKG=com.example.mobile_client
adb shell am kill %PKG%
adb shell pidof %PKG% || echo Process is gone
