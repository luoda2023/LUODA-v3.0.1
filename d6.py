from PIL import Image
im=Image.open('_d.png').convert('RGB')
w,h=im.size
px=im.load()
# bottom band 1750-2400: find colored button (green/blue) or bordered button
for y in range(1800,2400,8):
    row=[]
    for x in range(40,1041,100):
        r,g,b=px[x,y]
        row.append('%d,%d,%d'%(r//50*50,g//50*50,b//50*50))
    print(y, ' | '.join(row))
