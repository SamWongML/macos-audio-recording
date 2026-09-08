#!/usr/bin/env python3
"""Report the sidebar's selection fill: scan a column of the sidebar in logical points and
group consecutive scanlines into bands of uniform colour."""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
W, H = img.size
# The shot is a Retina backing store; logical width is the window's declared width.
logical_w = int(sys.argv[2]) if len(sys.argv) > 2 else 1200
scale = W / logical_w
x = int(200 * scale)          # inside the row fill, clear of the name and the glyph
bands = []
for y in range(0, H):
    c = img.getpixel((x, y))
    if bands and bands[-1][0] == c:
        bands[-1][2] = y
    else:
        bands.append([c, y, y])
modal = max(bands, key=lambda b: b[2] - b[1])[0]
print(f"size={W}x{H} scale={scale:.2f} sidebar ground={modal}")
for c, y0, y1 in bands:
    h = (y1 - y0 + 1) / scale
    if h >= 12 and c != modal:
        print(f"  band y={y0/scale:6.1f}..{y1/scale:6.1f} ({h:5.1f} pt)  rgb{c}")
