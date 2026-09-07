import sys
from collections import defaultdict
from PIL import Image
sys.path.insert(0, sys.argv[0].rsplit('/',1)[0])
from measure import ratio, LANE

def near(c, t, tol=10):
    return all(abs(c[i]-t[i]) <= tol for i in range(3))

FILLS = {"peaks": None, "body": None, "ground": None}

img = Image.open(sys.argv[1]).convert("RGB")
cx = int(sys.argv[2])
peaks = tuple(int(v) for v in sys.argv[3].split(","))
body  = tuple(int(v) for v in sys.argv[4].split(","))
ground= tuple(int(v) for v in sys.argv[5].split(","))
named = {"peaks": peaks, "body": body, "ground": ground}

p = img.load()
x0,y0,x1,y1 = [v*2 for v in LANE]
buckets = defaultdict(list)
for y in range(y0+4, y1-4, 1):
    ph = p[cx, y][:3]
    for side in (-6, 6):
        nb = p[cx+side, y][:3]
        for k, v in named.items():
            if near(nb, v):
                buckets[k].append(ratio(ph, nb))
                break
print(f"playhead column x={cx}")
for k in ("peaks","body","ground"):
    vs = buckets[k]
    if not vs:
        print(f"  {k:7s}  no samples"); continue
    print(f"  {k:7s}  n={len(vs):4d}  min={min(vs):5.2f}  median={sorted(vs)[len(vs)//2]:5.2f}  max={max(vs):5.2f}")
