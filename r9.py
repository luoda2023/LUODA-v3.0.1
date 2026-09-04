from PIL import Image
im=Image.open('_r3.png').convert('RGB')
w,h=im.size
px=im.load()
# bottom nav icons: find colored icon clusters y~2230-2330
for y in range(2150,2400,10):
    row=[]
    for x in range(60,1021,120):
        r,g,b=px[x,y]
        row.append((r//60*60,g//60*60,b//60*60))
    # print if any non-gray
    if any(c!=(240//60*60,240//60*60,240//60*60) and not(c[0]>100 and c[1]>100 and c[2]>100) for c in row):
        print(y,row)
