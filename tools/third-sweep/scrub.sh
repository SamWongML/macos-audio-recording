#!/bin/zsh
# THIRD-SWEEP harness (#108). Put the playhead over the *trimmed-away* lane, which ordinary
# playback never reaches — `AudioPlayer` starts at the Trim's lower bound and `TrimTimeline.scrub`
# seeks without clamping, so scrubbing is the only route into that region.
#
# **This is the one click into the lane the map's Notes forbid, and it is taken only with the
# arithmetic done first.** `nearestHandle` grabs a handle within 2% of the visible span; the target
# x below is checked to be many times that clear of both handles, `click.py` presses and releases
# without travel so `draggingHandle` resolves nil, and every Trim in the Library is backed up and
# re-read afterwards.
#   scrub.sh <out.png> <lane-x> <lane-y>
set -e
HERE=${0:a:h}
read -r WID X Y W H <<< "$(python3 "$HERE/winid.py")"
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXRaise\" of window 1" >/dev/null 2>&1 || true
sleep 0.5
python3 "$HERE/click.py" $(( X + $2 )) $(( Y + $3 )) >/dev/null
sleep 1.2
screencapture -x -o -l $WID "$1"
echo "shot $1"
