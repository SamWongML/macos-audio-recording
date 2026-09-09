#!/bin/zsh
# THIRD-SWEEP harness (#108). Launch AppTape fresh at a saved frame, in a named appearance, with
# optional accessibility flags forced in-process, and leave the editor open with the panel dismissed.
#
#   launch.sh <WxH> <dark|light> [a11y-flags]
#
# Never resizes the window programmatically: a `setFrame` before first layout produces a convincing
# artefact (the map's Notes). The frame is written to `NSWindow Frame editor` before launch instead.
set -e
HERE=${0:a:h}
SIZE=$1; APPEARANCE=$2; A11Y=$3
W=${SIZE%x*}; H=${SIZE#*x}
APP=/Users/demon/Library/Developer/Xcode/DerivedData/AppTape-fbylfxhrhjwkuohgbegywcrbzppo/Build/Products/Release/AppTape.app

pkill -f "Release/AppTape.app" 2>/dev/null || true
sleep 1.5

# Centre the frame on the 1920 x 1050 screen so no shot is clipped by an edge.
X=$(( (1920 - W) / 2 )); Y=$(( (1050 - H) / 2 ))
defaults write com.samwongml.AppTape "NSWindow Frame editor" "$X $Y $W $H 0 0 1920 1050 "
# The split view remembers its own widths; let the sidebar keep 268 and give the rest to the detail.
defaults write com.samwongml.AppTape "NSSplitView Subview Frames editor, SidebarNavigationSplitView" \
  -array "0.000000, 0.000000, 268.000000, $H.000000, NO, NO" "268.000000, 0.000000, $((W-268)).000000, $H.000000, NO, NO"

if [[ $APPEARANCE == light ]]; then
  osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'
else
  osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
fi
sleep 1.2

APPTAPE_SWEEP_A11Y=$A11Y APPTAPE_BOUNDARY=${APPTAPE_BOUNDARY:-a} "$APP/Contents/MacOS/AppTape" >/dev/null 2>&1 &
sleep 4.5
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript "$HERE/statusclick.applescript" $PID >/dev/null; sleep 1.6
python3 "$HERE/openeditor.py" >/dev/null; sleep 2.5
osascript "$HERE/statusclick.applescript" $PID >/dev/null; sleep 1.2   # dismiss the panel
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
sleep 0.8
echo $PID
