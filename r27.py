from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
h,w,_=a.shape
# top header green area 0-350 - find ID text (dark on green)
crop=a[100:300,:,:]
# the green theme color ~ (90,200,110)? find
bg=np.array([244,244,246])
# header likely green gradient; get mean color of top area
print('header mean',a[0:350].mean(axis=(0,1)).round(1))
