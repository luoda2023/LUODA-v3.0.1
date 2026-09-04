from PIL import Image
import numpy as np
im=Image.open('_a2.png').convert('RGB')
a=np.asarray(im)
h,w,_=a.shape
# full-width dark text rows to map all UI text y positions
dark=((a[:,:,0]<110)&(a[:,:,1]<110)&(a[:,:,2]<110))
lines=[]; inl=False
for y in range(100,h,2):
    c=dark[y,:].sum()
    if c>8 and not inl: start=y; inl=True
    elif c<=8 and inl:
        if y-start>10: lines.append((start,y))
        inl=False
if inl: lines.append((start,h-1))
# merge close
merged=[]
for ln in lines:
    if merged and ln[0]-merged[-1][1]<12: merged[-1]=(merged[-1][0],ln[1])
    else: merged.append(list(ln))
print('text lines:', [(a,b,(a+b)//2) for a,b in merged][:25])
