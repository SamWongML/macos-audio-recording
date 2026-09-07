#!/bin/zsh
# THIRD-SWEEP harness (#108). As export-fail.sh, but narrows the Library to one long Recording
# first, so the estimate is large enough that the failure message carries two big figures — the
# case #104's `Retry…` rename was measured against. Typing in the search field is also the only way
# to reach a row that is below the fold at the 960 floor.
#   export-fail2.sh <WxH> <dark|light> <out.png> <query> <export-x> <export-y>
set -e
HERE=${0:a:h}
SIZE=$1; APPEARANCE=$2; OUT=$3; QUERY=$4; BX=$5; BY=$6
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
python3 "$HERE/click.py" $(( X + 130 )) $(( Y + 75 )) >/dev/null    # the search field
sleep 0.8
osascript -e "tell application \"System Events\" to keystroke \"$QUERY\""
sleep 1.5
python3 "$HERE/click.py" $(( X + 90 )) $(( Y + 150 )) >/dev/null    # the first matching row
sleep 2.0
screencapture -x -o -l $WID "${OUT%.png}-selected.png"
python3 "$HERE/click.py" $(( X + BX )) $(( Y + BY )) >/dev/null
sleep 2.5
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
