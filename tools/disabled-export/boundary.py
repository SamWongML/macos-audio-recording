"""The sidebar/detail boundary, read off a screenshot in logical points (#115).

The step and the divider are one question — a hairline is a two-pixel-wide step — so this prints
both from the same scan: the two pane fills, their contrast, and every distinct colour run in the
20 logical points either side of the split.

  boundary.py <png> <logical-window-width> <split-x> [y ...]

`split-x` is where the sidebar ends (launch.sh pins it to 268). Rows default to a spread that
misses the rows, the search field and the footer.
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

def modal(im, s, x0, y0, x1, y1):
    px = list(im.crop((round(x0*s), round(y0*s), round(x1*s), round(y1*s))).getdata())
    return collections.Counter(px).most_common(1)[0][0]

def main():
    path, logical_w, split = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    rows = [float(v) for v in sys.argv[4:]] or [8, 120, 300, 480]
    im = Image.open(path).convert('RGB')
    s = im.size[0] / logical_w
    print(f"{path}   {im.size[0]}x{im.size[1]} px, {logical_w:.0f} pt logical, scale {s:g}")
    for y in rows:
        side = modal(im, s, split - 60, y - 3, split - 8, y + 3)
        det  = modal(im, s, split + 12, y - 3, split + 90, y + 3)
        # every distinct colour run across the seam, in logical points
        runs, py = [], round(y * s)
        for lx in range(round((split - 20) * s), round((split + 20) * s)):
            c = im.getpixel((lx, py))
            if runs and runs[-1][0] == c:
                runs[-1][2] = lx
            else:
                runs.append([c, lx, lx])
        seam = "  ".join(f"{str(c)}@{a/s - split:+.1f}..{(b+1)/s - split:+.1f}" for c, a, b in runs)
        print(f"  y={y:<5.0f} sidebar {str(side):<16} detail {str(det):<16} {ratio(side, det):>6.3f} : 1"
              f"   Δ{(lum(side)-lum(det))*100:+.1f}%")
        print(f"          seam  {seam}")

main()
