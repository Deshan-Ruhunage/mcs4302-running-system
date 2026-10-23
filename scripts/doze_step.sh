#!/usr/bin/env sh
# Part 4 (J2): move Doze to its next state; repeat until IDLE_MAINTENANCE
PKG=com.example.mobile_client   # change if your package name differs
set -x
adb shell dumpsys deviceidle step
adb shell dumpsys deviceidle get deep
