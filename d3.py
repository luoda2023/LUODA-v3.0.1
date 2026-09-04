from PIL import Image
im=Image.open('_d.png').convert('RGB')
w,h=im.size
px=im.load()
# full-res: find bright/button-like clusters across the whole image
pts=[]
for y in range(0,h,3):
    for x in range(0,w,3):
        r,g,b=px[x,y]
        if r+g+b>300:
            pts.append((x,y))
print('bright',len(pts))
ys=sorted(set(p[1] for p in pts))
bands=[]; s=None; prev=None
for yy in ys:
    if prev is None or yy-prev>40:
        if s is not None: bands.append((s,prev))
        s=yy
    prev=yy
if s is not None: bands.append((s,prev))
for b0,b1 in bands[:12]:
    xs=[p[0] for p in pts if b0<=p[1]<=b1]
    if xs: print('band',b0,'-',b1,'x',min(xs),'-',max(xs))
