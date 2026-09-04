from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
print('mean',a.mean(axis=(0,1)).round(1))
h,w,_=a.shape
for gy in range(8):
    blk=a[gy*h//8:(gy+1)*h//8]
    print('row',gy,'std',int(blk.std()))
