# -*- coding: utf-8 -*-
from PIL import Image
im=Image.open('_phone_now.png').convert('RGB')
w,h=im.size
# split into thirds with overlap
for name,y0,y1 in [('_ph_top',0,900),('_ph_mid',700,1700),('_ph_bot',1600,2400)]:
    im.crop((0,y0,w,y1)).resize((int(w*0.8),int((y1-y0)*0.8))).save('_crop_'+name+'.png')
print('saved')
