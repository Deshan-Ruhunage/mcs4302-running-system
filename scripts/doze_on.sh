#!/usr/bin/env sh
# Part 4 (J2): pretend the device is on battery, then force it into deep Doze
PKG=com.example.mobile_client   # change if your package name differs
set -x
adb shell dumpsys battery unplug
adb shell dumpsys deviceidle force-idle
adb shell dumpsys deviceidle get deep
