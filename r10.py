# -*- coding: utf-8 -*-
from PIL import Image
import collections
im=Image.open('_r3.png').convert('RGB')
w,h=im.size
px=im.load()
for y in range(1950,2400,12):
    cnt=collections.Counter()
    for x in range(0,w,6):
        r,g,b=px[x,y]
        cnt[(r//50*50,g//50*50,b//50*50)]+=1
    top=cnt.most_common(2)
    if not (len(top)==1 and top[0][0]==(200,200,200)):
        print(y, top)
