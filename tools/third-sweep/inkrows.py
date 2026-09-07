"""Per-row contrast of a known vertical mark against the fill beside it.

#105: the ink composites differently over each fill, so a single sampled "playhead colour" is
meaningless. The mark's column is found as the darkest/brightest column in a narrow search band.
  inkrows.py <png> <logical-w> <search-x0> <search-x1> <y0> <y1> <side-offset-pt>
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

path, lw = sys.argv[1], float(sys.argv[2])
sx0, sx1, y0, y1, offpt = (float(v) for v in sys.argv[3:8])
im = Image.open(path).convert('RGB'); s = im.size[0]/lw; px = im.load()
py0, py1 = round(y0*s), round(y1*s)
band = range(round(sx0*s), round(sx1*s))
# The lane's own median luminance, so "the mark" is whatever departs from it most consistently.
med = sorted(lum(px[x, (py0+py1)//2]) for x in band)[len(list(band))//2]
col = max(band, key=lambda x: sum(abs(lum(px[x, y]) - med) for y in range(py0, py1, 3)))
print(f"mark column x={col} (logical {col/s:.1f})")
off = round(offpt*s)
rows = collections.defaultdict(list)
for y in range(py0, py1):
    ink, fill = px[col, y], px[col+off, y]
    rows[fill].append((ratio(ink, fill), ink))
print(f"{'lane fill':<18} {'rows':>5}  {'ink (modal)':<18} {'min':>7} {'median':>7}")
for fill, vals in sorted(rows.items(), key=lambda kv: -len(kv[1]))[:6]:
    rs = sorted(v[0] for v in vals)
    inks = collections.Counter(v[1] for v in vals).most_common(1)[0][0]
    print(f"{str(fill):<18} {len(vals):>5}  {str(inks):<18} {rs[0]:>7.2f} {rs[len(rs)//2]:>7.2f}")
