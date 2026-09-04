from PIL import Image
im=Image.open('_inst_screen.png').convert('RGB')
w,h=im.size
px=im.load()
# scan bottom half for green button (ColorOS install button often green ~ (0,180,0) area) or text
import collections
# sample rows y from 1800..2390 step 20 to find distinct bands
for y in range(1900,2400,25):
    row=[]
    for x in range(100,1000,150):
        row.append(px[x,y])
    # unique-ish
    print(y, row[:6])
