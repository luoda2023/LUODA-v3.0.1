from PIL import Image
import numpy as np
im=Image.open('_m1.png').convert('RGB')
a=np.asarray(im)
# Menu white panel detection: white panel on right from some y. Get exact rows of text by scanning x572-830 for dark text lines with tighter threshold
dark=((a[:,:,0]<100)&(a[:,:,1]<100)&(a[:,:,2]<100))
lines=[]
inl=False
for y in range(150,1000):
    c=dark[y,560:840].sum()
    if c>5 and not inl:
        start=y; inl=True
    elif c<=5 and inl:
        lines.append((start,y-1)); inl=False
if inl: lines.append((start,999))
print('text lines y:', lines)
