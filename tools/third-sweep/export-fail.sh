#!/bin/zsh
# THIRD-SWEEP harness (#108). Force the Export dock's **failed** phase — the one phase whose text
# is the payload, and the one #104 rewrote (`Try Again…` -> `Retry…`) to fit both figures inside
# the shared 34 pt dock. #104 verified it at 1200 x 680; this shoots it at the 960 floor, where the
# column has to scroll.
#
# A 2 MB HFS+ image is the smallest thing that makes the encode fail for the right reason, the way
# #104 did it. Attached and detached in the same shell invocation.
#   export-fail.sh <WxH> <dark|light> <out.png> <export-button-x> <export-button-y>
set -e
HERE=${0:a:h}
SIZE=$1; APPEARANCE=$2; OUT=$3; BX=$4; BY=$5
IMG=/tmp/apptape-tiny-108.dmg
VOL=/Volumes/Tiny108
cleanup() {
  pkill -f "Release/AppTape.app" 2>/dev/null || true
  sleep 1
  hdiutil detach "$VOL" -quiet 2>/dev/null || true
  rm -f "$IMG"
  echo "volume detached, image removed"
}
trap cleanup EXIT INT TERM
rm -f "$IMG"
hdiutil create -size 2m -fs HFS+ -volname Tiny108 -quiet "$IMG"
hdiutil attach "$IMG" -quiet
zsh "$HERE/launch.sh" $SIZE $APPEARANCE >/dev/null
read -r WID X Y W H <<< "$(python3 "$HERE/winid.py")"
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
sleep 0.5
python3 "$HERE/click.py" $(( X + BX )) $(( Y + BY )) >/dev/null
sleep 2.5
# Save panel: Cmd-Shift-G, the volume's path, Return to go there, Return to save.
osascript <<APPLESCRIPT
tell application "System Events"
  keystroke "g" using {command down, shift down}
  delay 1.2
  keystroke "$VOL/"
  delay 1.0
  key code 36
  delay 1.5
  key code 36
end tell
APPLESCRIPT
sleep 4
screencapture -x -o -l $WID "$OUT"
echo "shot $OUT"
ls -la "$VOL" || true
