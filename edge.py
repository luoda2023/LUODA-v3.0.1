# -*- coding: utf-8 -*-
from PIL import Image
import os
for f in ['_p_top.png','_p_mid1.png','_p_mid2.png','_p_bot.png','_phone_now.png','_emu_now.png']:
    if not os.path.exists(f): 
        print(f,'missing'); continue
    im=Image.open(f).convert('RGB')
    w,h=im.size
    px=im.load()
    def col(x,y): return px[x,y]
    # sample borders: top row every 20px, bottom row, left col, right col
    def avg_row(y):
        xs=list(range(0,w, w//10))
        return [col(x,y) for x in xs]
    def avg_col(x):
        ys=list(range(0,h, h//10))
        return [col(x,y) for y in ys]
    print('==',f,w,'x',h)
    print(' top:',avg_row(0))
    print(' top2:',avg_row(min(2,h-1)))
    print(' bot:',avg_row(h-1))
    print(' bot2:',avg_row(max(0,h-3)))
    print(' left:',avg_col(0))
    print(' left2:',avg_col(min(2,w-1)))
    print(' right:',avg_col(w-1))
    print(' right2:',avg_col(max(0,w-3)))
