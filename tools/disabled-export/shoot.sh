#!/bin/zsh
# THIRD-SWEEP harness (#108). Shoot the editor window by CGWindow id.
#   shoot.sh <out.png>
set -e
HERE=${0:a:h}
read -r WID X Y W H <<< "$(python3 "$HERE/winid.py")"
screencapture -x -o -l $WID "$1"
echo "$WID $X $Y $W $H"
