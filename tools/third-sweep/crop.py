"""Crop a logical-point box out of a window shot and save it, optionally upscaled.
  crop.py <png> <logical-w> <out.png> <x0> <y0> <x1> <y1> [zoom]
"""
import sys
from PIL import Image
path, logical_w, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
x0, y0, x1, y1 = (float(v) for v in sys.argv[4:8])
zoom = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
im = Image.open(path).convert('RGB')
s = im.size[0] / logical_w
c = im.crop((round(x0*s), round(y0*s), round(x1*s), round(y1*s)))
if zoom != 1.0:
    c = c.resize((round(c.size[0]*zoom), round(c.size[1]*zoom)), Image.NEAREST)
c.save(out)
print(out, c.size)
