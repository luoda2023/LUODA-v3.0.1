from PIL import Image, ImageOps
im=Image.open('_r3.png').convert('L')
w,h=im.size
c=im.crop((0,int(h*0.35),w,int(h*0.8)))
c=ImageOps.autocontrast(c)
c=c.resize((int(c.width*1.8),int(c.height*1.8)))
c.save('_r3_mcontrast.png')
print('ok')
