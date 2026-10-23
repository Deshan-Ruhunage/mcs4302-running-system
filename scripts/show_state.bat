@REM Show Doze state, standby bucket and the app's Android JobScheduler entries (WorkManager uses JobScheduler underneath)
@REM Change PKG if your package name differs.
@set PKG=com.example.mobile_client
adb shell dumpsys deviceidle get deep
adb shell am get-standby-bucket %PKG%
adb shell "dumpsys jobscheduler | grep -A3 %PKG% | head -40"
