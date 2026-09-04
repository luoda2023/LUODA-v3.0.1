from PIL import Image
im=Image.open('_e2.png').convert('RGB')
w,h=im.size
px=im.load()
# map clickable-ish: find card/avatar circles (colored) in list area y150-1400
# print coarse color map 6x8 grid
import collections
for gy in range(6):
    row=[]
    for gx in range(6):
        x0=gx*w//6; y0=150+gy*((1250)//6)
        # sample avg
        xs=range(x0+20,x0+w//6-20,12); ys=range(y0+15,y0+208,12)
        cs=[px[x,y] for x in xs for y in ys]
        avg=tuple(sum(c[i] for c in cs)//len(cs) for i in range(3))
        # dominant non-gray
        row.append(avg)
    print(gy, row)
