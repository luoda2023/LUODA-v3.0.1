from PIL import Image
im=Image.open('_r2.png').convert('RGB')
w,h=im.size
px=im.load()
# find green buttons (dotchat primary 07C160 ~ (7,193,96))
pts=[]
for y in range(0,h,2):
    for x in range(0,w,2):
        r,g,b=px[x,y]
        if g>140 and r<90 and b<120 and g>r+60:
            pts.append((x,y))
print('green',len(pts))
if pts:
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    print('x',min(xs),max(xs),'y',min(ys),max(ys))
    # cluster y
    import collections
    yc=collections.Counter(y//50*50 for y in ys)
    for yy,cnt in sorted(yc.items()):
        if cnt>20:
            xx=[p[0] for p in pts if yy<=p[1]<yy+50]
            print(' band y',yy,'x',min(xx),max(xx),'cnt',cnt)
