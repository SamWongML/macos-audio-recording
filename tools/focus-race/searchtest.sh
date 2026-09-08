#!/bin/zsh
# Issue #113: typing in the sidebar search field must keep its focus (ADR-0029's own guarantee).
#   searchtest.sh <WxH> <dark|light>
set -e
HERE=${0:a:h}
$HERE/launch.sh $1 $2 >/dev/null
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
echo "on open        : $($HERE/focus.sh)"
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
sleep 0.5
osascript -e 'tell application "System Events" to key code 48'   # Tab -> the search field
sleep 1.0
echo "after Tab      : $($HERE/focus.sh)"
osascript -e 'tell application "System Events" to keystroke "hhh"'
sleep 1.5
echo "after typing   : $($HERE/focus.sh)"
osascript -e 'tell application "System Events" to keystroke "zzzz"'   # a query that matches nothing
sleep 1.5
echo "after no-match : $($HERE/focus.sh)"
