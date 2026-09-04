from PIL import Image
im=Image.open('_now.png').convert('RGB')
w,h=im.size
print('size',w,h)
# find distinct colored region (AtchDlg button green ~ (0,180,0)?) scan lower half for greenish
px=im.load()
found=[]
for y in range(int(h*0.5),h,5):
    for x in range(0,w,10):
        r,g,b=px[x,y]
        if g>150 and r<120 and b<120:
            found.append((x,y))
if found:
    xs=[p[0] for p in found]; ys=[p[1] for p in found]
    print('green region x',min(xs),max(xs),'y',min(ys),max(ys),'center',(sum(xs)//len(xs),sum(ys)//len(ys)))
else:
    print('no green found; sample colors')
    for y in range(int(h*0.5),h,80):
        print(y,[px[x,y] for x in range(100,w,200)])
