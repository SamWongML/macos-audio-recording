"""Locate the playhead by differencing two frames, then measure it per row.

The map's Notes: the playhead is the only thing in the window that moves, so a diff of two frames
1.2 s apart finds it. And #105: contrast must be read **per row**, never off a single sampled
"playhead colour" — the ink composites differently over each of the lane's three fills, and
sampling it as one column is exactly what first suggested `Color.primary` had passed.

  playhead.py <a.png> <b.png> <logical-w> <lane-x0> <lane-y0> <lane-x1> <lane-y1>
"""
import sys, collections
from PIL import Image

def lum(p):
    def f(v):
        v /= 255.0
        return v/12.92 if v <= 0.04045 else ((v+0.055)/1.055) ** 2.4
    return 0.2126*f(p[0]) + 0.7152*f(p[1]) + 0.0722*f(p[2])

def ratio(a, b):
    L1, L2 = sorted((lum(a), lum(b)), reverse=True)
    return (L1+0.05)/(L2+0.05)

a, b, lw = sys.argv[1], sys.argv[2], float(sys.argv[3])
x0, y0, x1, y1 = (float(v) for v in sys.argv[4:8])
A = Image.open(a).convert('RGB'); B = Image.open(b).convert('RGB')
s = A.size[0]/lw
px0, py0, px1, py1 = round(x0*s), round(y0*s), round(x1*s), round(y1*s)

# The playhead's column in frame B: the column with the largest summed change between frames that
# is *darker or brighter* than both frames' own lane. Take the strongest-diff column in B's half.
best = None
pa, pb = A.load(), B.load()
for x in range(px0, px1):
    d = sum(abs(lum(pb[x, y]) - lum(pa[x, y])) for y in range(py0, py1, 4))
    if best is None or d > best[1]:
        best = (x, d)
col = best[0]
print(f"playhead column x={col} (logical {col/s:.1f}), diff {best[1]:.2f}")

# Per row: the ink at the column vs the lane fill 8 logical pt to the right of the mark.
off = round(8*s)
rows = collections.defaultdict(list)
for y in range(py0, py1):
    ink = pb[col, y]
    fill = pb[col + off, y]
    rows[fill].append((ratio(ink, fill), ink))
print(f"{'lane fill':<18} {'rows':>5}  {'ink (modal)':<18} {'min':>7} {'median':>7} {'max':>7}")
for fill, vals in sorted(rows.items(), key=lambda kv: -len(kv[1]))[:5]:
    rs = sorted(v[0] for v in vals)
    inks = collections.Counter(v[1] for v in vals).most_common(1)[0][0]
    print(f"{str(fill):<18} {len(vals):>5}  {str(inks):<18} {rs[0]:>7.2f} {rs[len(rs)//2]:>7.2f} {rs[-1]:>7.2f}")
