from PIL import Image
im=Image.open('_now.png').convert('RGB')
w,h=im.size
px=im.load()
# scan for non-dark pixels overall & cluster them
pts=[]
for y in range(0,h,4):
    for x in range(0,w,4):
        r,g,b=px[x,y]
        if r+g+b>180:
            pts.append((x,y))
print('bright pts', len(pts))
if pts:
    # cluster by y ranges
    ys=sorted(set(p[1] for p in pts))
    # print summary bands
    bands=[]
    prev=None; s=None
    for yy in ys:
        if prev is None or yy-prev>30:
            if s is not None: bands.append((s,prev))
            s=yy
        prev=yy
    if s is not None: bands.append((s,prev))
    for b0,b1 in bands[:15]:
        xs=[p[0] for p in pts if b0<=p[1]<=b1]
        print('y-band',b0,'-',b1,'x',min(xs),'-',max(xs),'center x',sum(xs)//len(xs))
