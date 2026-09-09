#!/bin/zsh
# THIRD-SWEEP harness (#108). Click a sidebar row by its logical y from the window origin.
# `AXRaise` first: with the panel dismissed the editor is often not frontmost, and a click at the
# right window coordinates otherwise lands in whatever is in front (the map's Notes, from #104).
set -e
HERE=${0:a:h}
read -r WID X Y W H <<< "$(python3 "$HERE/winid.py")"
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
sleep 0.5
python3 "$HERE/click.py" $(( X + 90 )) $(( Y + $1 )) >/dev/null
sleep 1.5
echo "picked row at y=$1"
