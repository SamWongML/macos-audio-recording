#!/bin/bash
# PROTOTYPE — builds the menu-bar-surface variants (issue #8) into a throwaway menu bar
# app and runs it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MenuBarSurfacePrototype.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MenuBarSurfacePrototype</string>
  <key>CFBundleIdentifier</key><string>com.samwongml.AppTape.MenuBarSurfacePrototype</string>
  <key>CFBundleName</key><string>Menu Bar Surface Prototype</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>AppTape shows a live waveform for each app that is playing audio.</string>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/MenuBarSurfacePrototype" \
  AudioSources.swift Diag.swift LevelMonitor.swift Baseline.swift Session.swift \
  VariantI.swift VariantJ.swift VariantK.swift VariantL.swift App.swift
codesign --force --sign "Apple Development: senwong1991@gmail.com (DV2H9Y6436)" "$APP"

echo "Running — waveform icon in the menu bar."
echo "  ← / →  switch panel variant (I J K L)"
echo "  ↑ / ↓  switch menu bar icon treatment"
echo "  ⌘Q     quit"
# Launch through LaunchServices, not directly: TCC attribution follows the responsible
# process, and a terminal-launched bundle reads all-zero audio (source-picker prototype).
open "$APP"
