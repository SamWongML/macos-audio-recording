#!/bin/bash
# PROTOTYPE — issue #14. Builds, signs and launches the permission probe.
#
# `open`, never a bare shell run: TCC attribution follows the responsible process, so a
# binary started from a terminal is attributed to the terminal and reads all-zero (issue #6).
#
# Runs under com.samwongml.AppTape.PermProbe, NOT com.samwongml.AppTape, so denying it
# never touches the real app's grant.
set -euo pipefail
cd "$(dirname "$0")"
HERE="$PWD"

APP=build/PermProbe.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" logs

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PermProbe</string>
  <key>CFBundleIdentifier</key><string>com.samwongml.AppTape.PermProbe</string>
  <key>CFBundleName</key><string>AppTape Permission Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSAudioCaptureUsageDescription</key><string>AppTape records only the audio of the app you pick, so you can trim and export it. Nothing leaves this Mac.</string>
  <key>ProbeLogDirectory</key><string>${HERE}/logs</string>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/PermProbe" Probe.swift

# Stable identity so the grant survives rebuilds — ADR-0002.
codesign --force --sign "Apple Development: senwong1991@gmail.com (DV2H9Y6436)" "$APP"

open "$APP"
