#!/usr/bin/env sh
# Part 4 (J3): on battery, put the app in the RARE standby bucket (run AFTER pressing Home)
PKG=com.example.mobile_client   # change if your package name differs
set -x
adb shell dumpsys battery unplug
adb shell am set-standby-bucket $PKG rare
adb shell am get-standby-bucket $PKG
