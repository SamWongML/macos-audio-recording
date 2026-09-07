#!/bin/zsh
# THIRD-SWEEP harness (#108). Drive playback with the transport button and shoot the lane twice,
# 1.2 s apart. **Never click into the lane** — the map's Notes: a click within 2% of a Trim handle
# grabs the handle and commits a new Trim to the master's xattr (#105 lost a real value that way).
# Two frames because the playhead is the only thing in the window that moves, so differencing them
# is how it is located.
#   play.sh <out-prefix> <transport-x> <transport-y>   (logical points from the window origin)
set -e
HERE=${0:a:h}
PREFIX=$1; TX=$2; TY=$3
read -r WID X Y W H <<< "$(python3 "$HERE/winid.py")"
python3 "$HERE/click.py" $(( X + TX )) $(( Y + TY )) >/dev/null
sleep 1.4
screencapture -x -o -l $WID "${PREFIX}-a.png"
sleep 1.2
screencapture -x -o -l $WID "${PREFIX}-b.png"
python3 "$HERE/click.py" $(( X + TX )) $(( Y + TY )) >/dev/null   # pause
echo "shot ${PREFIX}-a.png ${PREFIX}-b.png"
