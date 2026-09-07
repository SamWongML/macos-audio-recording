import sys
from PIL import Image
path, winw = sys.argv[1], float(sys.argv[2])
im = Image.open(path).convert("RGB"); W,H = im.size
sx = W/winw
x = int(700*sx)
top=bot=None
for y in range(H):
    v = im.getpixel((x,y))
    lane = abs(v[0]-55)<=3 and abs(v[1]-55)<=3 and abs(v[2]-55)<=3
    wave = v[2] > v[0]+20                      # indigo peaks count as lane too
    if lane or wave:
        if top is None: top=y
        bot=y
print(f"lane top {top/sx:.1f}  bottom {bot/sx:.1f}  height {(bot-top)/sx:.1f}")
