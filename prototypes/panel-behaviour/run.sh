#!/bin/bash
# PROTOTYPE — issue #22. Builds the panel-behaviour probe and runs it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/PanelBehaviourProbe.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PanelBehaviourProbe</string>
  <key>CFBundleIdentifier</key><string>com.samwongml.AppTape.PanelBehaviourProbe</string>
  <key>CFBundleName</key><string>Panel Behaviour Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -target arm64-apple-macos27.0 -O \
  -o "$APP/Contents/MacOS/PanelBehaviourProbe" Probe.swift
codesign --force --sign "Apple Development: senwong1991@gmail.com (DV2H9Y6436)" "$APP"

LOG=~/Library/Logs/AppTapePanelProbe.log

echo "Two items in the menu bar: S (expanded session) and T (target/action)."
echo "Log: $LOG"
# Through LaunchServices, matching the other prototypes.
open "$APP"
