from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
# nav strip find y range: icons ~ (2400*0.92 to 2400)
# detect the row band with icon-like colors near bottom above navbar
strip=a[2150:2320,:,:]
bg=np.array([248,248,249])
mask=(np.abs(strip.astype(int)-bg).sum(axis=2)>100)
colsum=mask.sum(axis=0)
# icon x clusters
xs=np.where(colsum>2)[0]
cl=[]
if len(xs):
    s=xs[0]; p=xs[0]
    for x in xs[1:]:
        if x-p>80: cl.append((s+p)//2); s=x
        p=x
    cl.append((s+p)//2)
print('icon centers y2150-2320:', cl)
# also detect label text rows below icons
