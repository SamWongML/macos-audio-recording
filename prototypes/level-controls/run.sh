#!/bin/bash
# PROTOTYPE — builds the level-controls prototype into a throwaway app and runs it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/LevelControlsPrototype.app
# Versioned bundle id and rebuild-in-place, for the same LaunchServices / Window-scene
# reasons the editor-window prototype documents. Bump the trailing digit if it ever launches
# with no windows.
mkdir -p "$APP/Contents/MacOS"
rm -rf "$APP/Contents/_CodeSignature"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>LevelControlsPrototype</string>
  <key>CFBundleIdentifier</key><string>com.samwongml.AppTape.LevelControls1</string>
  <key>CFBundleName</key><string>Level Controls Prototype</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/LevelControlsPrototype" \
  Diag.swift Library.swift Waveform.swift Timeline.swift Player.swift \
  Loudness.swift Fixtures.swift Model.swift Level.swift App.swift

# This prototype only plays audio — it never creates a capture tap — so it needs no TCC grant
# and no real identity. Sign with the Personal Team if it's available (keeps parity with the
# app), else fall back to ad-hoc, which is fine here precisely because there is nothing to
# grant: ADR-0002's "ad-hoc resets the grant on rebuild" is a capture concern, and there is
# no capture.
IDENTITY="Apple Development: senwong1991@gmail.com (DV2H9Y6436)"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "note: developer identity unavailable, signing ad-hoc (fine — this prototype never captures)"
  codesign --force --sign - "$APP"
fi

echo "First run writes ~45 MB of loudness fixtures into ~/Music/AppTape — see the README."
echo "space plays · switcher window toggles treatment A/B and the fixture · ⌘Q quits."
open "$APP"
