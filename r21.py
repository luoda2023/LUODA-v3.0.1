from PIL import Image
import numpy as np
im=Image.open('_r5.png').convert('RGB')
a=np.asarray(im)
print('shape',a.shape)
print('min',a.min(axis=(0,1)),'max',a.max(axis=(0,1)),'mean',a.mean(axis=(0,1)).round(1))
# unique-ish region map - standard deviation per 100px block
h,w,_=a.shape
for gy in range(8):
    row=[]
    for gx in range(6):
        blk=a[gy*h//8:(gy+1)*h//8, gx*w//6:(gx+1)*w//6]
        row.append(int(blk.std()))
    print('row',gy,row)
