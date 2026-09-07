import sys
from PIL import Image
path, winw = sys.argv[1], float(sys.argv[2])
im = Image.open(path).convert("RGB"); W,H = im.size
sx = W/winw
# the overlay scroller rides ~6pt in from the window's right edge
best = 0
for dx in range(3, 14):
    x = W - int(dx*sx)
    run = cur = 0
    for y in range(H):
        r,g,b = im.getpixel((x,y))
        if r > 90 and abs(r-g) < 12 and abs(g-b) < 12:   # light neutral knob
            cur += 1; run = max(run, cur)
        else: cur = 0
    best = max(best, run)
print(f"{'SCROLLER' if best/sx > 60 else 'clean   '}  longest light run {best/sx:.0f}pt")
