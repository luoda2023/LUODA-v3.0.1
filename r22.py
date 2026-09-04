from PIL import Image
import numpy as np
im=Image.open('_r5.png').convert('RGB')
a=np.asarray(im)
# bottom band y2000-2400, find text/button clusters: non-bg(239,240,241) pixels
h,w,_=a.shape
bg=np.array([239,240,241])
mask=(np.abs(a.astype(int)-bg).sum(axis=2)>120)
ys,xs=np.where(mask[2000:2400,:])
ys=ys+2000
if len(xs):
    print('bottom content pixels',len(xs))
    # cluster rows
    import collections
    yc=collections.Counter(ys//20*20)
    for yy in sorted(yc):
        if yc[yy]>5:
            xx=xs[(ys>=yy)&(ys<yy+20)]
            print('y',yy,'x',xx.min(),xx.max(),'cnt',yc[yy])
