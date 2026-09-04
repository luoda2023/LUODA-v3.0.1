# -*- coding: utf-8 -*-
from PIL import Image
import os
# _p_mid1.png 1080x600: find horizontal runs of near-white from each edge per-row band
for f in ['_p_mid1.png','_p_bot.png','_p_mid2.png','_p_top.png']:
    im=Image.open(f).convert('RGB'); w,h=im.size; px=im.load()
    print('==',f,w,h)
    def is_white(c): return c[0]>245 and c[1]>245 and c[2]>245
    # per middle rows (y=h//2) measure white margin from left & right
    for yf in [0.2,0.5,0.8]:
        y=int(h*yf)
        l=0
        while l<w and is_white(px[l,y]): l+=1
        r=w-1
        while r>=0 and is_white(px[r,y]): r-=1
        print(' y=%.1f%% leftWhite=%d rightWhite=%d'%(yf*100,l,w-1-r))
    # top band: rows 0..30 count white in row y
    for y in [0,5,15,30,50]:
        cnt=sum(1 for x in range(w) if is_white(px[x,y]))
        print(' row %d whitePx=%d'%(y,cnt))
