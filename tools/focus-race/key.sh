#!/bin/zsh
# Send a key code to AppTape after raising its window. key.sh <keycode>   (125 = down arrow)
HERE=${0:a:h}
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
sleep 0.4
osascript -e "tell application \"System Events\" to key code $1"
sleep 0.8
