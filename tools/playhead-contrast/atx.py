import sys
from collections import Counter
from PIL import Image
sys.path.insert(0, sys.argv[0].rsplit('/',1)[0])
from measure import ratio, sample, LANE
img = Image.open(sys.argv[1]).convert("RGB")
cx = int(sys.argv[2])
rows = sample(img, cx)
ph = Counter(r[1] for r in rows)
print("playhead column colours:", ph.most_common(4))
c = ph.most_common(1)[0][0]
nb = Counter()
for y, p_, l, r in rows:
    nb[l] += 1; nb[r] += 1
print(f"\nfills beside the playhead, contrast vs {c}:")
for col, n in nb.most_common(6):
    print(f"  {col}  n={n:3d}  {ratio(c, col):5.2f} : 1")
