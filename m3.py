from PIL import Image
import numpy as np
im=Image.open('_m1.png').convert('RGB')
a=np.asarray(im)
h,w,_=a.shape
# menu panel white area right side. find its bounds: white (255) region x>600
# find text rows (dark px) in x 550-1080, y 150-900
dark=((a[:,:,0]<120)&(a[:,:,1]<120)&(a[:,:,2]<120))
for y in range(120,900,15):
    row=dark[y,550:1080].sum()
    if row>3:
        # x extent
        xs=np.where(dark[y,550:1080])[0]+550
        print('y',y,'darkpx',row,'x',xs.min(),xs.max())
