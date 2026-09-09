"""Side-by-side comparison sheet of the seam, one column per variant (#115)."""
import sys
from PIL import Image, ImageDraw
ap = sys.argv[1]; variants = sys.argv[2:]
crops=[]
for v in variants:
    im = Image.open(f"shots/{v}-{ap}-1200-empty.png").convert('RGB')
    s = im.size[0]/1200
    crops.append((v, im.crop((round(120*s), 0, round(560*s), im.size[1])).resize((220, round(im.size[1]/s/2)))))
w = sum(c.size[0]+8 for _,c in crops); h = crops[0][1].size[1]+22
sheet = Image.new('RGB',(w,h),(20,20,20) if ap=='dark' else (250,250,250))
d = ImageDraw.Draw(sheet); x=0
for v,c in crops:
    sheet.paste(c,(x,22)); d.text((x+6,6), f"{v}", fill=(255,255,255) if ap=='dark' else (0,0,0)); x+=c.size[0]+8
sheet.save(f"shots/sheet-{ap}.png"); print(f"shots/sheet-{ap}.png {sheet.size}")
