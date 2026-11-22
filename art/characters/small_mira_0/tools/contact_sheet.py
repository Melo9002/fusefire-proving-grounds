# python contact_sheet.py <dir> <out.png> <cols> pattern...  (labels each tile with its filename)
import sys, glob, os
from PIL import Image, ImageDraw
d, out, cols, pats = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
files = [f for p in pats for f in sorted(glob.glob(os.path.join(d, p)))]
ims = [Image.open(f).convert("RGB") for f in files]
w, h = ims[0].size; rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows), (40, 40, 40))
for i, (f, im) in enumerate(zip(files, ims)):
    ImageDraw.Draw(im).text((6, 6), os.path.basename(f)[:-4], fill=(255, 220, 0))
    sheet.paste(im, ((i % cols) * w, (i // cols) * h))
sheet.save(out); print(out, len(ims))
