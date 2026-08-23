#!/bin/bash
# PROTOTYPE — builds the editor-window variants into a throwaway app and runs it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/EditorWindowPrototype.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>EditorWindowPrototype</string>
  <key>CFBundleIdentifier</key><string>com.samwongml.AppTape.EditorWindowPrototype</string>
  <key>CFBundleName</key><string>Editor Window Prototype</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/EditorWindowPrototype" \
  Diag.swift Library.swift Fixtures.swift Waveform.swift Player.swift Timeline.swift \
  Export.swift Model.swift VariantM.swift VariantN.swift VariantO.swift VariantP.swift VariantQ.swift App.swift

codesign --force --sign "Apple Development: senwong1991@gmail.com (DV2H9Y6436)" "$APP"

echo "First run writes ~575 MB of fixture Recordings into ~/Music/AppTape — see the README."
echo "⌥← / ⌥→ variant, ⌥↑ / ⌥↓ precision, ⌘Q quits."
open "$APP"
