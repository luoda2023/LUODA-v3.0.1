from PIL import Image
im=Image.open('_r2.png').convert('RGB')
w,h=im.size
px=im.load()
# scan rows 2050-2350: find green regions x ranges
for y in range(2050,2360,10):
    greens=[x for x in range(0,w,4) if (lambda c: c[1]>140 and c[0]<90 and c[2]<120 and c[1]>c[0]+60)(px[x,y])]
    if greens:
        # cluster
        runs=[]; s=greens[0]; p=greens[0]
        for x in greens[1:]:
            if x-p>20: runs.append((s,p)); s=x
            p=x
        runs.append((s,p))
        print('y',y,[(a,b) for a,b in runs if b-a>30])
