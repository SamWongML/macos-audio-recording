"""Modal fills inside a logical box, ranked by area, with each one's contrast against the ground.

The lane has three fills (ground, muted body, peaks) plus whatever is drawn over it. Reporting the
top-N modal colours is how you see them all without guessing where each one lives.
  lane.py <png> <logical-w> <label> <x0> <y0> <x1> <y1> [...]
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

path, logical_w = sys.argv[1], float(sys.argv[2])
im = Image.open(path).convert('RGB'); s = im.size[0]/logical_w
args = sys.argv[3:]
for i in range(0, len(args), 5):
    label = args[i]; x0,y0,x1,y1 = (float(v) for v in args[i+1:i+5])
    box = im.crop((round(x0*s), round(y0*s), round(x1*s), round(y1*s)))
    px = list(box.getdata()); tot = len(px)
    top = collections.Counter(px).most_common(4)
    ground = top[0][0]
    print(f"{label}")
    for rgb, n in top:
        print(f"    {str(rgb):<18} {n*100/tot:5.1f}%   vs ground {ratio(rgb, ground):5.2f}:1   L={lum(rgb):.4f}")
