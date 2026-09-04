from PIL import Image, ImageOps
im=Image.open('_r4.png').convert('L')
w,h=im.size
c=ImageOps.autocontrast(im)
c=c.resize((int(c.width*0.5),int(c.height*0.5)))
c.save('_r4_s.png')
print('ok')
