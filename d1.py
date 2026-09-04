from PIL import Image
im=Image.open('_d.png').convert('RGB')
w,h=im.size
print('size',w,h)
im.save('_d_view.png')
# find green button (dotchat primary ~07C160)
px=im.load()
pts=[]
for y in range(0,h,3):
    for x in range(0,w,3):
        r,g,b=px[x,y]
        if g>140 and g>r+40 and g>b+40:
            pts.append((x,y))
print('green pts', len(pts))
if pts:
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    print('x',min(xs),max(xs),'y',min(ys),max(ys))
