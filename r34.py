from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
h,w,_=a.shape
# find green regions precisely
green=(a[:,:,1].astype(int)-a[:,:,0].astype(int)>40) & (a[:,:,1].astype(int)-a[:,:,2].astype(int)>40) & (a[:,:,1]>140)
ys,xs=np.where(green)
if len(ys):
    import collections
    yc=collections.Counter(ys//100*100)
    print('green bands (y,cnt):', sorted(yc.items())[:20])
    # x range per band
    for yy in sorted(yc):
        if yc[yy]>100:
            xx=xs[(ys>=yy)&(ys<yy+100)]
            print('  band',yy,'x',xx.min(),xx.max(),'cnt',yc[yy])
