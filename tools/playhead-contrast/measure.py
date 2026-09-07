import sys, math
from PIL import Image

def lum(c):
    def f(v):
        v = v/255.0
        return v/12.92 if v <= 0.04045 else ((v+0.055)/1.055)**2.4
    return 0.2126*f(c[0]) + 0.7152*f(c[1]) + 0.0722*f(c[2])

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi+0.05)/(lo+0.05)

# lane in *points* for a 1200x680 window; images are 2x
LANE = (292, 95, 900, 410)

def find_playhead(imgA, imgB, scale=2):
    x0, y0, x1, y1 = [v*scale for v in LANE]
    a, b = imgA.load(), imgB.load()
    ys = range(y0+10, y1-10, 7)
    best = []
    for x in range(x0, x1):
        d = sum(abs(a[x,y][i]-b[x,y][i]) for y in ys for i in range(3))
        best.append((d, x))
    best.sort(reverse=True)
    xs = sorted({x for d, x in best[:12]})
    # group into runs
    runs, cur = [], [xs[0]]
    for x in xs[1:]:
        if x - cur[-1] <= 2: cur.append(x)
        else: runs.append(cur); cur = [x]
    runs.append(cur)
    return runs

def sample(img, cx, scale=2):
    """Return playhead colour and the three fills beside it, per row band."""
    x0, y0, x1, y1 = [v*scale for v in LANE]
    p = img.load()
    out = []
    for y in range(y0+4, y1-4, 2):
        ph = p[cx, y][:3]
        left = p[cx-6, y][:3]
        right = p[cx+6, y][:3]
        out.append((y, ph, left, right))
    return out

if __name__ == "__main__":
    A, B = Image.open(sys.argv[1]).convert("RGB"), Image.open(sys.argv[2]).convert("RGB")
    runs = find_playhead(A, B)
    print("moving runs (px, 2x):", runs)
    cx = sum(runs[-1])//len(runs[-1])
    print("playhead centre in B at px x =", cx)
    rows = sample(B, cx)
    # classify neighbour colours into clusters
    from collections import Counter
    ph_colours = Counter(r[1] for r in rows)
    print("playhead column colours (top 3):", ph_colours.most_common(3))
    ph = ph_colours.most_common(1)[0][0]
    nb = Counter()
    for y, p_, l, r in rows:
        nb[l] += 1; nb[r] += 1
    print("\nneighbour fills, most common 6, with contrast against playhead", ph)
    for c, n in nb.most_common(6):
        print(f"  {c}  n={n:3d}  ratio={ratio(ph, c):.2f} : 1")
