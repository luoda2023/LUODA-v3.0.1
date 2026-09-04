from PIL import Image
im=Image.open('_r3.png').convert('RGB')
w,h=im.size
# y 0-900 area (green header + content below)
c=im.crop((0,0,w,900))
c.save('_r3_h.png')
print('saved',c.size)
# find all non-bg distinct color blocks rows y 0-900
px=im.load()
import collections
for y in range(0,900,30):
    cnt=collections.Counter()
    for x in range(0,w,8):
        r,g,b=px[x,y]
        cnt[(r//40*40,g//40*40,b//40*40)]+=1
    top=cnt.most_common(1)[0]
    if top[0]!=(240,240,240):
        print(y, top)
