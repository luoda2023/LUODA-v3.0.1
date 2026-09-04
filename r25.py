from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
h,w,_=a.shape
print('size',w,h)
# bottom nav y~2230-2400 scan icon positions
bg=np.array([243,244,246])
# bottom strip colors
strip=a[2300:2400,:,:]
# find 4 nav icon centers: cluster by x of non-bg pixels in y 2300-2400
mask=(np.abs(strip.astype(int)-bg).sum(axis=2)>100)
colsum=mask.sum(axis=0)
# find clusters of x where colsum>3
xs=np.where(colsum>3)[0]
clusters=[]
if len(xs):
    s=xs[0]; p=xs[0]
    for x in xs[1:]:
        if x-p>60: clusters.append((s+p)//2); s=x
        p=x
    clusters.append((s+p)//2)
print('nav icons x centers:',clusters)
