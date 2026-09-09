"""Vertical extent of whatever is drawn at the seam (#115): where the line starts and stops.
  extent.py <png> <logical-w> <split-x>
"""
import sys
from PIL import Image
path, W, split = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
im = Image.open(path).convert('RGB'); s = im.size[0]/W
x = round(split*s)                      # first pixel of the detail side
Hl = im.size[1]/s
runs=[]
for py in range(im.size[1]):
    here = im.getpixel((x, py)); left = im.getpixel((x-round(2*s), py)); right = im.getpixel((x+round(3*s), py))
    line = abs(here[0]-left[0])>2 and abs(here[0]-right[0])>2
    if runs and runs[-1][0]==line: runs[-1][2]=py
    else: runs.append([line,py,py])
print(f"{path}  seam column x={split:g}pt, window {Hl:.0f}pt tall")
for line,a,b in runs:
    if (b-a)/s < 2: continue
    print(f"  {'LINE ' if line else '     '} y {a/s:7.1f} .. {(b+1)/s:7.1f}   ({(b+1-a)/s:.1f} pt)")
