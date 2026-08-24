#!/bin/bash
# PROTOTYPE — builds and launches the issue #12 tap probe.
#
# It must be launched with `open`, not run from the terminal: TCC attribution follows the
# responsible process, so a binary started from a shell is attributed to the terminal and
# reads all-zero (found in issue #6).
set -euo pipefail
cd "$(dirname "$0")"
HERE="$PWD"

APP=build/TapProbe.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" logs

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TapProbe</string>
  <key>CFBundleIdentifier</key><string>com.samwongml.AppTape.TapProbe</string>
  <key>CFBundleName</key><string>AppTape Tap Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSAudioCaptureUsageDescription</key><string>AppTape is proving it can capture a chosen app's audio.</string>
  <key>AppTapeProbeLogDirectory</key><string>${HERE}/logs</string>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/TapProbe" \
  Log.swift CoreAudioSupport.swift Probe.swift Model.swift App.swift

# A stable signing identity keeps the TCC grant across rebuilds — ADR-0002.
codesign --force --sign "Apple Development: senwong1991@gmail.com (DV2H9Y6436)" "$APP"

echo "Launching. Logs land in ${HERE}/logs/"
open "$APP"
