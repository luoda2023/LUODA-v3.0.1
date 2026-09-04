from PIL import Image, ImageOps
im=Image.open('_r5.png').convert('RGB')
w,h=im.size
px=im.load()
# diff vs r4 (before scroll) - count changed px
im4=Image.open('_r4.png').convert('RGB')
p4=im4.load()
diff=sum(1 for y in range(0,h,10) for x in range(0,w,10) if abs(px[x,y][0]-p4[x,y][0])+abs(px[x,y][1]-p4[x,y][1])+abs(px[x,y][2]-p4[x,y][2])>40)
print('changed%', round(diff*100/((h//10)*(w//10)),1))
# find green buttons again
pts=[]
for y in range(0,h,2):
    for x in range(0,w,2):
        r,g,b=px[x,y]
        if g>140 and r<90 and b<120 and g>r+60: pts.append((x,y))
print('green',len(pts))
if pts:
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    print('x',min(xs),max(xs),'y',min(ys),max(ys))
