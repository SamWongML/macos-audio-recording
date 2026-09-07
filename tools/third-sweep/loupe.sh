#!/bin/zsh
# THIRD-SWEEP harness (#108). Photograph the loupe, which exists only while a Trim handle is under
# the hand — so the shot happens with the button still down.
#
# **Driven on an untrimmed Recording, and released at a hard clamp.** The map's Notes: a drag
# commits to the master's `com.apptape.trim` xattr and #105 lost a real Trim value that way. The
# left handle of an untrimmed Recording is at t = 0, so releasing well left of the lane clamps it
# back to exactly 0 and the Recording is returned as found. Every Trim in the Library is backed up
# before the run regardless.
#   loupe.sh <out.png> <grab-x> <to-x> <release-x> <lane-centre-y>  (logical points, window origin)
set -e
HERE=${0:a:h}
OUT=$1; GRAB=$2; TO=$3; REL=$4; LANEY=${5:-251}
read -r WID X Y W H <<< "$(python3 "$HERE/winid.py")"
CY=$(( Y + LANEY ))
python3 "$HERE/drag.py" hold $(( X + GRAB )) $CY $(( X + TO )) $CY
sleep 0.6
screencapture -x -o -l $WID "$OUT"
python3 "$HERE/drag.py" release $(( X + REL )) $CY
sleep 1.2
echo "shot $OUT"
