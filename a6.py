from PIL import Image
im=Image.open('_in.png').convert('RGB')
w,h=im.size
# check keyboard appeared: bottom half non-white
import numpy as np
a=np.asarray(im)
print('bottom std', int(a[1300:].std()))
c=im.crop((0,200,w,700))
c.save('_in_field.png')
c=im.crop((0,int(h*0.6),w,h))
c.resize((int(c.width*0.8),int(c.height*0.8))).save('_in_kb.png')
print('ok')
