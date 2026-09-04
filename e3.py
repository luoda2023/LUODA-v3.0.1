from PIL import Image
im=Image.open('_e2.png').convert('RGB')
w,h=im.size
px=im.load()
# The home page: need locate conversation rows - look at y 200-1300 for text rows
# green theme at top? print color bands to locate rows separators
for y in range(150,1500,50):
    row=[px[x,y] for x in (100,300,500,700,900)]
    # convert to gray-ish signature
    sig=tuple(sum(c)//3 for c in row)
    print(y,sig)
