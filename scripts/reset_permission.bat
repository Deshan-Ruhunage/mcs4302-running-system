@REM Part 3: revoke the notification permission and clear the don't-ask-again flags
@REM Change PKG if your package name differs.
@set PKG=com.example.mobile_client
adb shell pm revoke %PKG% android.permission.POST_NOTIFICATIONS
adb shell pm clear-permission-flags %PKG% android.permission.POST_NOTIFICATIONS user-set user-fixed
