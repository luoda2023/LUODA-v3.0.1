from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
h,w,_=a.shape
# middle content 500-2100 empty? check per 300px band std
for y0 in range(400,2100,300):
    blk=a[y0:y0+300]
    print(y0,'-',y0+300,'std',int(blk.std()),'mean',blk.mean(axis=(0,1)).round(1))
