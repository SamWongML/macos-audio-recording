"""Contrast of text (or any mark) against its own background, inside a logical-point box.

Boxes are given in *logical* points from the window's top-left, so the same numbers work at any
backing scale. Background is the modal colour of the box; the mark is the pixel furthest from it in
luminance. That is the strongest-glyph reading, i.e. the most generous one: if this fails, the text
fails.

  measure.py <png> <logical-window-width> <label> <x0> <y0> <x1> <y1> [...]
"""
import sys, collections
from PIL import Image

def lum(p):
    def f(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(p[0]) + 0.7152 * f(p[1]) + 0.0722 * f(p[2])

def ratio(a, b):
    L1, L2 = sorted((lum(a), lum(b)), reverse=True)
    return (L1 + 0.05) / (L2 + 0.05)

def main():
    path, logical_w = sys.argv[1], float(sys.argv[2])
    im = Image.open(path).convert('RGB')
    s = im.size[0] / logical_w
    args = sys.argv[3:]
    for i in range(0, len(args), 5):
        label = args[i]
        x0, y0, x1, y1 = (float(v) for v in args[i+1:i+5])
        box = im.crop((round(x0*s), round(y0*s), round(x1*s), round(y1*s)))
        px = list(box.getdata())
        bg, n = collections.Counter(px).most_common(1)[0]
        lb = lum(bg)
        mark = max(px, key=lambda p: abs(lum(p) - lb))
        print(f"{label:<34} bg {str(bg):<16} {n*100//len(px):>3}%   mark {str(mark):<16} {ratio(mark, bg):>6.2f} : 1")

main()
