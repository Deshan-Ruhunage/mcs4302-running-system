#!/usr/bin/env sh
# Part 3: revoke the notification permission and clear the don't-ask-again flags
PKG=com.example.mobile_client   # change if your package name differs
set -x
adb shell pm revoke $PKG android.permission.POST_NOTIFICATIONS
adb shell pm clear-permission-flags $PKG android.permission.POST_NOTIFICATIONS user-set user-fixed
