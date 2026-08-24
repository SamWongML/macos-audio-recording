#!/bin/bash
# PROTOTYPE — issue #14. Does flipping the System Settings toggle reach a tap that already exists?
#
# Sequence: put the probe into the DENIED state, hold a tap open in a live process, have the
# human flip the switch, and watch whether audio starts flowing — on the original tap, only on
# a rebuilt one, or not at all without a relaunch.
set -uo pipefail
cd "$(dirname "$0")"
HERE="$PWD"; ID=com.samwongml.AppTape.PermProbe; APP="$HERE/build/PermProbe.app"

prompt_msgid() {
  /usr/bin/log show --start "$1" --style compact 2>/dev/null \
    | grep -E "AUTHREQ_PROMPTING.*kTCCServiceAudioCapture.*PermProbe" \
    | grep -oE "msgID=[0-9]+\.[0-9]+" | tail -1
}
result_for() {
  /usr/bin/log show --start "$1" --style compact 2>/dev/null \
    | grep -E "AUTHREQ_RESULT: $2," | grep -oE "authValue=[0-9]" | tail -1
}

# ---------- step 1: reach the DENIED state ----------
tccutil reset AudioCapture "$ID" >/dev/null 2>&1
osascript -e 'display dialog "STEP 1 of 2\n\nA system audio permission prompt is about to appear.\n\nClick DON'"'"'T ALLOW on it — we need the denied state to test recovery from." buttons {"I am ready"} default button 1 with title "AppTape — recovery experiment"' >/dev/null 2>&1
STAMP=$(date "+%Y-%m-%d %H:%M:%S")
open -n "$APP"
DENIED=""
for i in $(seq 1 240); do
  M=$(prompt_msgid "$STAMP")
  if [ -n "$M" ]; then
    V=$(result_for "$STAMP" "$M")
    [ "$V" = "authValue=0" ] && { DENIED=yes; echo "tccd: DENIED after ${i}s"; break; }
    [ "$V" = "authValue=2" ] && { echo "tccd: ALLOWED — wrong button, aborting"; exit 2; }
  fi
  sleep 1
done
[ "$DENIED" != yes ] && { echo "no deny landed"; exit 1; }
pkill -f PermProbe >/dev/null 2>&1; sleep 3

# ---------- step 2: hold a tap open across the toggle flip ----------
osascript -e 'display dialog "STEP 2 of 2\n\nWhen you click below, two things happen:\n  • the probe starts and holds a tap open\n  • System Settings opens on Screen & System Audio Recording\n\nScroll to the SYSTEM AUDIO RECORDING ONLY section and switch ON\n\"AppTape Permission Probe\".\n\nYou have about 70 seconds. If macOS offers \"Quit & Reopen\", DO NOT click it — that would end the process we are measuring." buttons {"Start"} default button 1 with title "AppTape — recovery experiment"' >/dev/null 2>&1

BEFORE=$(ls logs/perm-*.txt 2>/dev/null | wc -l | tr -d ' ')
FLIP=$(date "+%Y-%m-%d %H:%M:%S")
open -n "$APP" --args recover
sleep 2
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"

# Watch tccd independently, so the moment the switch actually moved is on the record.
( for i in $(seq 1 150); do
    V=$(/usr/bin/log show --start "$FLIP" --style compact 2>/dev/null \
        | grep -E "com.apple.TCC:access" | grep -B2 "AUTHREQ_RESULT" \
        | grep -A2 "subject=com.samwongml.AppTape.PermProbe" \
        | grep -oE "authValue=2" | tail -1)
    [ -n "$V" ] && { echo "   tccd: toggle observed ON at +${i}s"; break; }
    sleep 1
  done ) &

for _ in $(seq 1 220); do
  NEW=$(ls -t logs/perm-*.txt 2>/dev/null | head -1)
  if [ -n "$NEW" ] && [ "$(ls logs/perm-*.txt | wc -l | tr -d ' ')" -gt "$BEFORE" ] && grep -q probe.done "$NEW"; then
    echo; echo "=========== RECOVERY RUN ==========="; cat "$NEW"; break
  fi
  if [ -n "$NEW" ] && [ "$(ls logs/perm-*.txt | wc -l | tr -d ' ')" -gt "$BEFORE" ] && ! pgrep -f PermProbe >/dev/null; then
    echo; echo "=========== PROBE DIED — macOS terminated it on the TCC change ==========="; cat "$NEW"; break
  fi
  sleep 1
done
wait
tccutil reset AudioCapture "$ID" >/dev/null 2>&1
echo "=========== probe TCC entry reset ==========="
