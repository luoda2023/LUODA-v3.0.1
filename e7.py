from PIL import Image
im=Image.open('_e3.png').convert('RGB')
w,h=im.size
px=im.load()
# detect dark text rows and colored(icon) rows to map layout
for y in range(0,h,25):
    dark=0; green=0; blue=0
    for x in range(20,1061,6):
        r,g,b=px[x,y]
        if r<80 and g<80 and b<80: dark+=1
        elif g>120 and g>r+30 and g>b+30: green+=1
    if dark>2 or green>2:
        print('y',y,'dark',dark,'green',green)
