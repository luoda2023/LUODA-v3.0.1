from PIL import Image, ImageOps
im=Image.open('_r5.png').convert('RGB')
w,h=im.size
px=im.load()
# Find dark-text horizontal bands to detect button label rows in y2000-2360
import collections
for y in range(2050,2370,6):
    dark=0; colored=0
    for x in range(20,1061,5):
        r,g,b=px[x,y]
        if r<110 and g<110 and b<110: dark+=1
        if (g>130 and r<100 and b<110) or (r>130 and g<100) or (b>130 and r<100): colored+=1
    if dark>5 or colored>3:
        print(y,'dark',dark,'colored',colored)
