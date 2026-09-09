#!/bin/zsh
# Same as launch.sh but at a caller-chosen origin, to test whether the sidebar's fill moves with
# the desktop behind the window (#115).
set -e
HERE=${0:a:h}
X=$1; Y=$2; W=$3; H=$4; APPEARANCE=$5
APP=/Users/demon/Library/Developer/Xcode/DerivedData/AppTape-fbylfxhrhjwkuohgbegywcrbzppo/Build/Products/Release/AppTape.app
pkill -f "Release/AppTape.app" 2>/dev/null || true; sleep 1.5
defaults write com.samwongml.AppTape "NSWindow Frame editor" "$X $Y $W $H 0 0 1920 1050 "
defaults write com.samwongml.AppTape "NSSplitView Subview Frames editor, SidebarNavigationSplitView" \
  -array "0.000000, 0.000000, 268.000000, $H.000000, NO, NO" "268.000000, 0.000000, $((W-268)).000000, $H.000000, NO, NO"
osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $([[ $APPEARANCE == light ]] && echo false || echo true)"
sleep 1.2
APPTAPE_BOUNDARY=${APPTAPE_BOUNDARY:-a} "$APP/Contents/MacOS/AppTape" >/dev/null 2>&1 &
sleep 4.5
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript "$HERE/statusclick.applescript" $PID >/dev/null; sleep 1.6
python3 "$HERE/openeditor.py" >/dev/null; sleep 2.5
osascript "$HERE/statusclick.applescript" $PID >/dev/null; sleep 1.2
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
sleep 0.8
echo $PID
