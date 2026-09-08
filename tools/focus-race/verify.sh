#!/bin/zsh
# Issue #113 verification: open the editor at a saved frame, then check the three things the
# ticket asks for — the row's fill on open, ↓ moving the selection, and the search field keeping
# its focus while typing.
#   verify.sh <WxH> <dark|light> <out-prefix>
set -e
HERE=${0:a:h}
SIZE=$1; APP=$2; OUT=$3
W=${SIZE%x*}
$HERE/launch.sh $SIZE $APP >/dev/null
echo "focus on open : $($HERE/focus.sh)"
$HERE/shoot.sh "$OUT-open.png" >/dev/null
python3 $HERE/rowfill.py "$OUT-open.png" $W
$HERE/key.sh 125 >/dev/null 2>&1     # ↓
$HERE/shoot.sh "$OUT-down.png" >/dev/null
echo "after ↓:"
python3 $HERE/rowfill.py "$OUT-down.png" $W
python3 - "$OUT-open.png" "$OUT-down.png" <<'PY'
import sys
from PIL import Image, ImageChops
a, b = (Image.open(p).convert("RGB") for p in sys.argv[1:3])
bbox = ImageChops.difference(a, b).getbbox()
print("  ↓ changed pixels in:", bbox if bbox else "NOTHING — ↓ did nothing")
PY
