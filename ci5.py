from PIL import Image
im=Image.open('_now.png').convert('RGB')
w,h=im.size
# find button-like bright regions in lower third
px=im.load()
# print row segments y 2100-2390
for y in range(2100,2400,20):
    row=[]
    for x in range(60,1021,120):
        r,g,b=px[x,y]
        row.append('(%d,%d,%d)'%(r//40*40,g//40*40,b//40*40))
    print(y,' '.join(row))
