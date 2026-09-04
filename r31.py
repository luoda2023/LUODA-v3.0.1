from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
# top-right icons x>850 y<350 (more/add icons on green header)
crop=a[0:350, 800:1080, :]
bg=np.array([191,226,209]) # approx green header
# find non-green (white icons)
mask=(np.abs(crop.astype(int)-bg).sum(axis=2)>150)
ys,xs=np.where(mask)
if len(xs):
    # cluster icons by x
    import collections
    xc=collections.Counter(xs//40*40+800)
    print('top-right icon clusters x:', sorted(xc))
    # icon y
    print('icon y range:', ys.min(), ys.max())
