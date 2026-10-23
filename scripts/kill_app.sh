#!/usr/bin/env sh
# Part 2: kill the app process (the app must be in the background)
PKG=com.example.mobile_client   # change if your package name differs
set -x
adb shell am kill $PKG
adb shell pidof $PKG || echo "Process is gone"
