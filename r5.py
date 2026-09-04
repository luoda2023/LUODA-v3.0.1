from PIL import Image
im=Image.open('_r2.png').convert('RGB')
w,h=im.size
px=im.load()
# find full-width button-ish band: rows with >400px non-background same-ish color in y1900-2350
bg=(243,244,246) # guess
for y in range(1950,2380,8):
    colors={}
    for x in range(0,w,6):
        c=px[x,y]
        key=(c[0]//40*40,c[1]//40*40,c[2]//40*40)
        colors[key]=colors.get(key,0)+1
    top=sorted(colors.items(),key=lambda kv:-kv[1])[:2]
    print(y, top)
