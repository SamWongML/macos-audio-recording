#!/bin/bash
# PROTOTYPE — builds the source-picker variants into a throwaway menu bar app and runs it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SourcePickerPrototype.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>SourcePickerPrototype</string>
  <key>CFBundleIdentifier</key><string>com.samwongml.AppTape.SourcePickerPrototype</string>
  <key>CFBundleName</key><string>Source Picker Prototype</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/SourcePickerPrototype" \
  AudioSources.swift Variants.swift Variants2.swift App.swift
codesign --force --sign - "$APP"

echo "Running — look for the waveform icon in the menu bar. ← / → switch variants, ⌘Q quits."
open "$APP"
