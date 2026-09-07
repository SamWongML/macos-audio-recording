#!/bin/zsh
# PROTOTYPE harness (#111). Launch fresh with a variant forced, open the editor from the panel,
# optionally pick a row, shoot the window by id and measure the two fills.
#   shoot.sh <SP> <A|B|C|D|E> <out.png> [select]
set -e
SP=$1; V=$2; OUT=$3; SELECT=$4
APP=/Users/demon/Library/Developer/Xcode/DerivedData/AppTape-fbylfxhrhjwkuohgbegywcrbzppo/Build/Products/Release/AppTape.app
pkill -f "Release/AppTape.app" 2>/dev/null || true
sleep 1.5
APPTAPE_COLUMN_VARIANT=$V "$APP/Contents/MacOS/AppTape" >/dev/null 2>&1 &
sleep 4
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript "$SP/statusclick.applescript" $PID >/dev/null; sleep 1.6
python3 "$SP/openeditor.py" >/dev/null; sleep 2.5
osascript "$SP/statusclick.applescript" $PID >/dev/null; sleep 1.2   # dismiss the panel
read -r WID X Y W H <<< "$(python3 "$SP/winid.py")"
if [[ -n $SELECT ]]; then
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
  sleep 0.6
  python3 "$SP/click.py" $((X+120)) $((Y+473)) >/dev/null; sleep 1.6   # the QuickTime Player row
fi
sleep 0.6
screencapture -x -o -l $WID "$OUT"
printf "%-2s %-9s " $V ${SELECT:-empty}
python3 "$SP/probe.py" "$OUT" $W 2>/dev/null
