from PIL import Image
import numpy as np
im=Image.open('_a2.png').convert('RGB')
a=np.asarray(im)
h,w,_=a.shape
# Find input field (white box with border) and button (green) in page
green=((a[:,:,1].astype(int)-a[:,:,0].astype(int)>60)&(a[:,:,1]>140)&(a[:,:,1]-a[:,:,2]>40))
ys,xs=np.where(green)
if len(ys):
    import collections
    yc=collections.Counter(ys//60*60)
    for yy in sorted(yc):
        if yc[yy]>200:
            xx=xs[(ys>=yy)&(ys<yy+60)]
            print('green band y',yy,'-',yy+60,'x',xx.min(),xx.max(),'cnt',yc[yy])
# input box: look for rounded white box edges around y300-500: lines of gray border
