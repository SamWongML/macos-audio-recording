"""Modal RGB of two boxes in a window screenshot: the detail pane and the trailing column.

Boxes are given in *logical* points measured from the window's own top-left, so the same
numbers work at any backing scale. The column is 276 pt wide and flush to the trailing edge.
"""
import sys, collections
from PIL import Image

path = sys.argv[1]
im = Image.open(path).convert('RGB')
W, H = im.size
logical_w = float(sys.argv[2]) if len(sys.argv) > 2 else 1200.0
s = W / logical_w                       # backing scale

def modal(x0, y0, x1, y1):
    box = im.crop((int(x0*s), int(y0*s), int(x1*s), int(y1*s)))
    c = collections.Counter(box.getdata())
    (rgb, n), = c.most_common(1)
    return rgb, n, box.size[0]*box.size[1]

Hl = H / s
# Detail: a strip left of the column, low in the pane (below the brief / the empty sentence).
d, dn, dt = modal(560, Hl-90, 800, Hl-40)
# Column: inside the trailing 276 pt, clear of both edges.
c, cn, ct = modal(logical_w-230, Hl-90, logical_w-60, Hl-40)

def lum(p):
    def f(v):
        v /= 255.0
        return v/12.92 if v <= 0.04045 else ((v+0.055)/1.055) ** 2.4
    return 0.2126*f(p[0]) + 0.7152*f(p[1]) + 0.0722*f(p[2])

L1, L2 = sorted((lum(d), lum(c)), reverse=True)
ratio = (L1 + 0.05) / (L2 + 0.05)
delta = (c[0] - d[0]) / d[0] * 100 if d[0] else 0
print(f"detail {d} ({dn*100//dt}%)   column {c} ({cn*100//ct}%)   step {ratio:.3f}:1   column {delta:+.1f}%")
