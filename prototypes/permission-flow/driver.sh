#!/bin/bash
# PROTOTYPE — issue #14. Drives the whole permission experiment in one go.
#
# Five runs across every TCC state the app can meet, with an on-screen instruction before
# each one so the click order cannot be got wrong. Every run writes its own log; the
# outcome is recoverable from the logs even if a button is mis-clicked.
set -uo pipefail
cd "$(dirname "$0")"
HERE="$PWD"
ID=com.samwongml.AppTape.PermProbe
APP="$HERE/build/PermProbe.app"

say() { osascript -e "display dialog \"$1\" buttons {\"Ready\"} default button 1 with title \"AppTape permission experiment — step $2 of 5\"" >/dev/null 2>&1; }

run() {  # run <label>
  local label="$1"
  local before; before=$(ls logs 2>/dev/null | wc -l)
  open -n "$APP"
  # Each run is ~9s of measurement plus however long a prompt sits unanswered.
  for _ in $(seq 1 300); do
    local newest; newest=$(ls -t logs/perm-*.txt 2>/dev/null | head -1)
    if [ -n "$newest" ] && [ "$(ls logs | wc -l)" -gt "$before" ] && grep -q "probe.done" "$newest" 2>/dev/null; then
      echo "=================== RUN ${label} → $(basename "$newest")"
      grep -E "device.start RETURNED|VERDICT|tap.format|tone.start|output.running.after" "$newest"
      return 0
    fi
    sleep 1
  done
  echo "=================== RUN ${label} → TIMED OUT"
}

mkdir -p logs
# Build and sign fresh; a stable identity keeps grants across rebuilds (ADR-0002).
rm -rf build && mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PermProbe</string>
  <key>CFBundleIdentifier</key><string>${ID}</string>
  <key>CFBundleName</key><string>AppTape Permission Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSAudioCaptureUsageDescription</key><string>AppTape records only the audio of the app you pick, so you can trim and export it. Nothing leaves this Mac.</string>
  <key>ProbeLogDirectory</key><string>${HERE}/logs</string>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/PermProbe" Probe.swift || exit 1
codesign --force --sign "Apple Development: senwong1991@gmail.com (DV2H9Y6436)" "$APP" || exit 1

# Start from no TCC entry at all, whatever the machine was in before.
tccutil reset AudioCapture "$ID" >/dev/null 2>&1

say "A short 440 Hz tone plays during each run — that is deliberate, it gives the tap something to capture.\n\nSTEP 1: a permission prompt will appear.\n\nClick ALLOW." 1
run "A — first ask, ALLOW"

say "STEP 2: no prompt expected. Nothing to click; this measures the settled GRANTED state." 2
run "B — settled granted"

tccutil reset AudioCapture "$ID" >/dev/null 2>&1
say "STEP 3: the grant has been reset, so the prompt returns.\n\nThis time click DON'T ALLOW." 3
run "C — first ask, DENY"

say "STEP 4: no prompt expected. This is the measurement the whole ticket hangs on — what a settled DENIAL looks like from inside the app." 4
run "D — settled denied   <<< THE KEY RUN"

tccutil reset AudioCapture "$ID" >/dev/null 2>&1
say "STEP 5: the denial has been reset. Does the prompt come back, or is a denial permanent?\n\nIf a prompt appears, click ALLOW." 5
run "E — after resetting a denial"

# Leave the machine exactly as it was found: no TCC entry for the probe.
tccutil reset AudioCapture "$ID" >/dev/null 2>&1
echo "=================== done; probe's TCC entry removed"
