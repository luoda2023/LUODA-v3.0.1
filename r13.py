from PIL import Image, ImageOps
im=Image.open('_r3.png').convert('L')
w,h=im.size
# autocontrast + upscale top 40%
c=im.crop((0,0,w,int(h*0.42)))
c=ImageOps.autocontrast(c)
c=c.resize((c.width*2,c.height*2))
c.save('_r3_contrast.png')
print('ok')
