from PIL import Image, ImageOps
im=Image.open('_r3.png').convert('L')
w,h=im.size
c=im.crop((0,int(h*0.75),w,h))
c=ImageOps.autocontrast(c)
c=c.resize((int(c.width*2),int(c.height*2)))
c.save('_r3_bcontrast.png')
print('ok')
